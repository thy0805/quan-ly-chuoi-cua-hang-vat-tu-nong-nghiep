import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../auth/api_client.dart';
import '../auth/auth_controller.dart';
import '../core/numbers.dart';
import 'models.dart';
import 'request_models.dart';
import 'request_store.dart';

enum TransferRequestState {
  loading,
  editing,
  sending,
  knownId,
  unknownOutcome,
  rejected,
  storageBlocked,
}

class TransferAttempt {
  TransferAttempt({
    required this.attemptId,
    required this.createdAt,
    required this.payload,
    required this.state,
    this.transferId,
  });

  factory TransferAttempt.fromJson(TransferJson json) {
    final state = json['state'] as String;
    final id = json['transfer_id'];
    final attemptId = json['attempt_id'] as String;
    final createdAt = json['created_at'] as String;
    if (!{
          'pending',
          'known_id',
          'unknown_outcome',
          'rejected',
        }.contains(state) ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(attemptId) ||
        !DateTime.parse(createdAt).isUtc ||
        ((state == 'known_id') != (id != null))) {
      throw const FormatException('Marker không hợp lệ.');
    }
    final payload = TransferPayload.fromJson(
      json['payload'] as TransferJson,
      jsonId(json['branch_id']),
    );
    if (payload.fingerprint != json['fingerprint']) {
      throw const FormatException('Payload đã thay đổi.');
    }
    return TransferAttempt(
      attemptId: attemptId,
      createdAt: createdAt,
      payload: payload,
      state: state,
      transferId: id == null ? null : jsonId(id),
    );
  }

  final String attemptId, createdAt, state;
  final String? transferId;
  final TransferPayload payload;
  TransferAttempt withState(String state, [String? id]) => TransferAttempt(
    attemptId: attemptId,
    createdAt: createdAt,
    payload: payload,
    state: state,
    transferId: id,
  );
  TransferJson toJson() => {
    'attempt_id': attemptId,
    'created_at': createdAt,
    'state': state,
    'transfer_id': transferId,
    'branch_id': payload.branchId,
    'payload': payload.toJson(),
    'fingerprint': payload.fingerprint,
  };
}

class _Envelope {
  _Envelope(this.origin, this.user, this.active, this.journal);
  factory _Envelope.decode(String raw, String origin, String user) {
    final json = jsonDecode(raw) as TransferJson;
    if (json.length != 5 ||
        !json.keys.toSet().containsAll({
          'version',
          'origin',
          'user_id',
          'active',
          'journal',
        }) ||
        json['version'] != 1 ||
        json['origin'] != origin ||
        json['user_id'] != user) {
      throw const FormatException('Sai namespace/phiên bản lưu trữ.');
    }
    final active = json['active'] == null
        ? null
        : TransferAttempt.fromJson(json['active'] as TransferJson);
    final journal = (json['journal'] as List).map((e) {
      final row = e as TransferJson;
      final attempt = TransferAttempt.fromJson(row['attempt'] as TransferJson);
      if (!{'known_id', 'rejected'}.contains(attempt.state) ||
          !DateTime.parse(row['archived_at'] as String).isUtc) {
        throw const FormatException('Sai journal.');
      }
      return Map<String, dynamic>.unmodifiable(row);
    }).toList();
    final ids = journal
        .map((e) => (e['attempt'] as TransferJson)['attempt_id'])
        .toList();
    if (ids.toSet().length != ids.length ||
        active != null && ids.contains(active.attemptId)) {
      throw const FormatException('Trùng attempt.');
    }
    return _Envelope(origin, user, active, List.unmodifiable(journal));
  }
  final String origin, user;
  final TransferAttempt? active;
  final List<TransferJson> journal;
  String encode() => jsonEncode({
    'version': 1,
    'origin': origin,
    'user_id': user,
    'active': active?.toJson(),
    'journal': journal,
  });
}

class TransferSubmission extends ChangeNotifier {
  TransferSubmission(this.auth, this.store) {
    auth.addListener(_authChanged);
  }
  final AuthController auth;
  final TransferAttemptStore store;
  _Envelope? _envelope;
  TransferOptions? _options;
  TransferDetail? _detail;
  TransferRequestState _state = TransferRequestState.loading;
  ApiFailure? _error;
  String? _bound;
  int? _revision;
  bool busy = false, _disposed = false, _opened = false;
  final Map<String, String> _unsaved = {};

  String? get _key =>
      auth.stage == AuthStage.ready &&
          !auth.busy &&
          auth.profile != null &&
          auth.branch != null
      ? '${auth.api.storageNamespace}|${auth.profile!.userId}'
      : null;
  bool get visible =>
      _key != null && _key == _bound && _revision == auth.authorizationRevision;
  bool get _sameBranch =>
      visible && attempt?.payload.branchId == auth.branch?.id;
  TransferRequestState get state =>
      visible ? _state : TransferRequestState.loading;
  TransferAttempt? get attempt => visible ? _envelope?.active : null;
  TransferOptions? get options => visible ? _options : null;
  TransferDetail? get detail => _sameBranch ? _detail : null;
  ApiFailure? get error => visible ? _error : null;
  List<TransferJson> get journal => visible && _envelope != null
      ? List.unmodifiable(
          (jsonDecode(_envelope!.encode())['journal'] as List).map(
            (e) => Map<String, dynamic>.unmodifiable(e as TransferJson),
          ),
        )
      : const [];
  bool get canCreate =>
      visible &&
      !busy &&
      _state == TransferRequestState.editing &&
      _options != null;
  bool get canComplete =>
      !busy &&
      _sameBranch &&
      _detail != null &&
      _state == TransferRequestState.knownId;

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void _authChanged() {
    _options = null;
    _detail = null;
    _emit();
    if (_opened && !busy && _key != null && !visible) unawaited(open());
  }

  void _finish() {
    busy = false;
    _emit();
    if (!_disposed && _opened && _key != null && !visible) unawaited(open());
  }

  void _blocked() {
    _state = TransferRequestState.storageBlocked;
    _detail = null;
    _error = const ApiFailure(
      'Không xác minh được bộ nhớ điều chuyển. Đã khóa gửi để tránh tạo trùng. Chỉ đọc lại trạng thái khi bộ nhớ hoạt động.',
    );
  }

  Future<void> _persist(_Envelope value) async {
    final key = '${value.origin}|${value.user}';
    final raw = value.encode();
    _unsaved[key] = raw;
    await store.write(value.origin, value.user, raw);
    if (await store.read(value.origin, value.user) != raw) {
      throw StateError('Lưu trữ không khớp read-back.');
    }
    _unsaved.remove(key);
    _envelope = value;
  }

  Future<void> _read(String origin, String user, int revision) async {
    _bound = '$origin|$user';
    _revision = revision;
    _envelope = null;
    _detail = null;
    _error = null;
    _state = TransferRequestState.loading;
    _emit();
    final rawUnsaved = _unsaved[_bound];
    if (rawUnsaved != null) {
      await _persist(_Envelope.decode(rawUnsaved, origin, user));
    }
    final raw = await store.read(origin, user);
    _envelope = raw == null
        ? _Envelope(origin, user, null, [])
        : _Envelope.decode(raw, origin, user);
    _state = switch (_envelope!.active?.state) {
      null => TransferRequestState.editing,
      'known_id' => TransferRequestState.knownId,
      'rejected' => TransferRequestState.rejected,
      _ => TransferRequestState.unknownOutcome,
    };
  }

  Future<void> open() async {
    _opened = true;
    if (busy || _key == null) return;
    busy = true;
    _options = null;
    try {
      await _read(
        auth.api.storageNamespace,
        auth.profile!.userId,
        auth.authorizationRevision,
      );
      if (!visible) return;
      if (_state == TransferRequestState.editing) {
        await _loadOptions();
      } else if (_state == TransferRequestState.knownId && _sameBranch) {
        await _loadDetail();
      }
    } catch (_) {
      _blocked();
    } finally {
      _finish();
    }
  }

  Future<void> _loadOptions() async {
    try {
      final data = await auth.readTransfers('/api/stock-transfers/options');
      final parsed = TransferOptions.fromJson(data);
      if (visible) _options = parsed;
    } on ApiFailure catch (e) {
      _error = e;
    } catch (_) {
      _error = const ApiFailure(
        'Options điều chuyển không đúng định dạng.',
        kind: ApiFailureKind.invalidResponse,
      );
    }
  }

  Future<void> submit(TransferPayload payload) async {
    if (!canCreate || payload.branchId != auth.branch?.id) return;
    try {
      _options!.validate(payload, auth.branch!.chainId);
    } on FormatException catch (e) {
      _error = ApiFailure(e.message, status: 422);
      _emit();
      return;
    }
    final origin = auth.api.storageNamespace, user = auth.profile!.userId;
    final revision = auth.authorizationRevision;
    busy = true;
    _emit();
    try {
      await _read(origin, user, revision);
      if (_state != TransferRequestState.editing ||
          !visible ||
          auth.branch?.id != payload.branchId) {
        return;
      }
      final random = Random.secure();
      final pending = TransferAttempt(
        attemptId: List.generate(
          16,
          (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join(),
        createdAt: DateTime.now().toUtc().toIso8601String(),
        payload: payload,
        state: 'pending',
      );
      final journal = _envelope!.journal;
      _state = TransferRequestState.sending;
      await _persist(_Envelope(origin, user, pending, journal));
      _emit();
      TransferAttempt result;
      try {
        final id = await auth.createTransferRequest(
          payload.toJson(),
          userId: user,
          branchId: payload.branchId,
          revision: revision,
        );
        result = pending.withState('known_id', id);
      } on ApiFailure catch (e) {
        _error = e;
        result = pending.withState(
          e.definiteRejection ? 'rejected' : 'unknown_outcome',
        );
      } catch (_) {
        result = pending.withState('unknown_outcome');
      }
      await _persist(_Envelope(origin, user, result, journal));
      _state = switch (result.state) {
        'known_id' => TransferRequestState.knownId,
        'rejected' => TransferRequestState.rejected,
        _ => TransferRequestState.unknownOutcome,
      };
      if (visible && _sameBranch && result.transferId != null) {
        await _loadDetail();
      }
    } catch (_) {
      _blocked();
    } finally {
      _finish();
    }
  }

  Future<void> _loadDetail() async {
    final active = attempt;
    if (active?.transferId == null || !_sameBranch) return;
    _detail = null;
    _error = null;
    try {
      final raw = await auth.readTransfers(
        '/api/stock-transfers/${active!.transferId}',
      );
      final parsed = TransferDetail.fromJson(raw);
      if (parsed.transfer.id != active.transferId ||
          !active.payload.matches(parsed, _envelope!.user, raw)) {
        throw const FormatException('Không khớp yêu cầu đã lưu.');
      }
      if (visible && _sameBranch) _detail = parsed;
    } on ApiFailure catch (e) {
      _error = e;
    } catch (_) {
      _error = const ApiFailure(
        'Chi tiết không khớp dấu vết tạo yêu cầu. Giữ ID, không gửi lại.',
        kind: ApiFailureKind.invalidResponse,
      );
    }
  }

  Future<void> reloadDetail() async {
    if (!visible || busy || _state != TransferRequestState.knownId) return;
    busy = true;
    _emit();
    try {
      await _loadDetail();
    } finally {
      _finish();
    }
  }

  Future<void> complete() async {
    if (!canComplete) return;
    await _archive();
  }

  Future<void> editRejected() async {
    if (!visible || busy || _state != TransferRequestState.rejected) return;
    await _archive();
  }

  Future<void> _archive() async {
    busy = true;
    final active = _envelope!.active!;
    _emit();
    try {
      final origin = _envelope!.origin, user = _envelope!.user;
      final old = _envelope!;
      final raw = await store.read(origin, user);
      if (raw != old.encode()) throw StateError('Dấu vết đã thay đổi.');
      if (!visible || auth.branch?.id != active.payload.branchId) return;
      await _persist(
        _Envelope(origin, user, null, [
          ...old.journal,
          {
            'attempt': active.toJson(),
            'archived_at': DateTime.now().toUtc().toIso8601String(),
          },
        ]),
      );
      _state = TransferRequestState.editing;
      _detail = null;
      _options = null;
      _error = null;
      if (visible) await _loadOptions();
    } catch (_) {
      _blocked();
    } finally {
      _finish();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    auth.removeListener(_authChanged);
    super.dispose();
  }
}
