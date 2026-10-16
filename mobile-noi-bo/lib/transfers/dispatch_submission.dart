import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../auth/api_client.dart';
import '../auth/auth_controller.dart';
import '../core/numbers.dart';
import 'dispatch_models.dart';
import 'dispatch_store.dart';
import 'models.dart';
import 'request_models.dart';

enum DispatchState {
  loading,
  ready,
  sending,
  unknown,
  verified,
  handledElsewhere,
  denied,
  storageBlocked,
}

class _Envelope {
  _Envelope(this.origin, this.user, this.active, this.journal);
  factory _Envelope.decode(String raw, String origin, String user) {
    final data = jsonDecode(raw) as TransferJson;
    if (data.length != 5 ||
        !data.containsKey('active') ||
        data['version'] != 1 ||
        data['origin'] != origin ||
        data['user_id'] != user) {
      throw const FormatException('Sai namespace xuất kho.');
    }
    final active = data['active'] == null
        ? null
        : DispatchAttempt.fromJson(data['active'] as TransferJson);
    final journal = (data['journal'] as List).map((item) {
      final row = item as TransferJson;
      final attempt = DispatchAttempt.fromJson(row['attempt'] as TransferJson);
      if (!{
            'verified',
            'handled_elsewhere',
            'denied',
          }.contains(attempt.phase) ||
          !DateTime.parse(row['archived_at'] as String).isUtc) {
        throw const FormatException('Journal không hợp lệ.');
      }
      final observation = row['observation'] as TransferJson;
      if (observation['transfer_id'] != attempt.id ||
          !transferStatuses.containsKey(observation['status'])) {
        throw const FormatException('Thiếu đối chiếu phiếu trong journal.');
      }
      if (attempt.phase != 'denied') {
        final actor = jsonId(observation['dispatched_by']);
        final time = DateTime.parse(observation['dispatched_at'] as String);
        final lines = dispatchLines(observation['items']);
        if (!time.isUtc ||
            !{
              'dispatched',
              'received',
              'discrepancy',
              'reconciled',
            }.contains(observation['status']) ||
            lines.length != attempt.lines.length ||
            lines.any(
              (line) => !attempt.lines.any((e) => e.lotId == line.lotId),
            ) ||
            attempt.phase == 'verified' &&
                (actor != user ||
                    lines.any(
                      (line) => !attempt.lines.any(
                        (e) =>
                            e.lotId == line.lotId &&
                            e.quantity.compareTo(line.quantity) == 0,
                      ),
                    ))) {
          throw const FormatException('Journal xuất kho thiếu bằng chứng.');
        }
      }
      return row;
    }).toList();
    final ids = journal
        .map((row) => (row['attempt'] as TransferJson)['attempt_id'])
        .toList();
    if (ids.toSet().length != ids.length ||
        active != null && ids.contains(active.attemptId)) {
      throw const FormatException('Trùng dấu vết.');
    }
    return _Envelope(origin, user, active, journal);
  }
  final String origin, user;
  final DispatchAttempt? active;
  final List<TransferJson> journal;
  String encode() => jsonEncode({
    'version': 1,
    'origin': origin,
    'user_id': user,
    'active': active?.toJson(),
    'journal': journal,
  });
}

class TransferDispatches extends ChangeNotifier {
  TransferDispatches(this.auth, this.store) {
    auth.addListener(_authChanged);
  }
  final AuthController auth;
  final TransferDispatchStore store;
  _Envelope? _envelope;
  DispatchDetail? _detail;
  TransferOptions? _options;
  DispatchState _state = DispatchState.loading;
  ApiFailure? _error;
  String? _bound, _diskRaw, _targetId;
  int? _revision;
  bool busy = false, _opened = false, _disposed = false;
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
      visible &&
      (_envelope?.active == null || attempt!.branchId == auth.branch?.id);
  DispatchAttempt? get attempt => visible ? _envelope?.active : null;
  DispatchDetail? get detail => _sameBranch ? _detail : null;
  DispatchState get state => visible ? _state : DispatchState.loading;
  ApiFailure? get error => visible ? _error : null;
  TransferStock? stockFor(String lot) =>
      detail == null ||
          !(_options?.sources.any(
                (e) => e.id == detail!.detail.transfer.fromWarehouseId,
              ) ??
              false)
      ? null
      : _options
            ?.lotsFor(detail!.detail.transfer.fromWarehouseId)
            .where((e) => e.lotId == lot)
            .firstOrNull;
  List<TransferJson> get journal => visible && _envelope != null
      ? List.unmodifiable(
          (jsonDecode(_envelope!.encode())['journal'] as List).map(
            (e) => Map<String, dynamic>.unmodifiable(e as TransferJson),
          ),
        )
      : const [];
  bool get canDispatch =>
      visible &&
      !busy &&
      _envelope?.active == null &&
      _state == DispatchState.ready &&
      (_detail?.allowed(auth.branch!.id) ?? false);
  bool get canComplete =>
      _sameBranch &&
      !busy &&
      _envelope?.active != null &&
      _detail != null &&
      {
        DispatchState.verified,
        DispatchState.handledElsewhere,
        DispatchState.denied,
      }.contains(_state);

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void _authChanged() {
    _detail = null;
    _options = null;
    _emit();
    if (_opened && !busy && _key != null && !visible) unawaited(open());
  }

  void _finish() {
    busy = false;
    _emit();
    if (!_disposed && _opened && _key != null && !visible) unawaited(open());
  }

  void _blocked() {
    _state = DispatchState.storageBlocked;
    _detail = null;
    _error = const ApiFailure(
      'Không xác minh được bộ nhớ xuất kho. Đã khóa thao tác. Chỉ đọc lại dấu vết khi bộ nhớ hoạt động.',
    );
  }

  DispatchState _stateOf(String? phase) => switch (phase) {
    null => DispatchState.ready,
    'verified' => DispatchState.verified,
    'handled_elsewhere' => DispatchState.handledElsewhere,
    'denied' => DispatchState.denied,
    _ => DispatchState.unknown,
  };
  Future<void> _persist(_Envelope value) async {
    final key = '${value.origin}|${value.user}', raw = value.encode();
    _unsaved[key] = raw;
    await store.write(value.origin, value.user, raw);
    if (await store.read(value.origin, value.user) != raw) {
      throw StateError('Read-back khác dữ liệu ghi.');
    }
    _unsaved.remove(key);
    _diskRaw = raw;
    _envelope = value;
  }

  Future<void> _read(String origin, String user, int revision) async {
    _bound = '$origin|$user';
    _revision = revision;
    _envelope = null;
    _detail = null;
    _options = null;
    _error = null;
    _state = DispatchState.loading;
    _emit();
    if (_unsaved[_bound] != null) {
      await _persist(_Envelope.decode(_unsaved[_bound]!, origin, user));
    }
    _diskRaw = await store.read(origin, user);
    _envelope = _diskRaw == null
        ? _Envelope(origin, user, null, [])
        : _Envelope.decode(_diskRaw!, origin, user);
    _state = _stateOf(_envelope!.active?.phase);
  }

  Future<DispatchDetail> _get(String id) async {
    try {
      final result = DispatchDetail.fromJson(
        await auth.readTransfers('/api/stock-transfers/$id'),
      );
      if (result.detail.transfer.id != id ||
          result.chainId != auth.branch!.chainId ||
          !result.detail.transfer.belongsTo(auth.branch!.id)) {
        throw const FormatException('Sai phiếu hoặc phạm vi.');
      }
      return result;
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw const ApiFailure(
        'Chi tiết hoặc quyền xuất kho không đúng định dạng.',
        kind: ApiFailureKind.invalidResponse,
      );
    }
  }

  Future<void> open({String? id}) async {
    _opened = true;
    if (busy || _key == null) return;
    busy = true;
    _targetId = id;
    try {
      await _read(
        auth.api.storageNamespace,
        auth.profile!.userId,
        auth.authorizationRevision,
      );
      if (visible && _sameBranch) await _loadDetail();
    } catch (_) {
      _blocked();
    } finally {
      _finish();
    }
  }

  Future<void> _loadDetail() async {
    final active = attempt;
    final id = active?.id ?? _targetId;
    _detail = null;
    _options = null;
    _error = null;
    if (id == null || !_sameBranch) return;
    try {
      final result = await _get(id);
      if (!visible || !_sameBranch) return;
      if (active != null && result.fingerprint != active.fingerprint) {
        throw const ApiFailure(
          'Nội dung phiếu khác dấu vết đã lưu. Giữ khóa thao tác, không gửi lại.',
          kind: ApiFailureKind.invalidResponse,
        );
      }
      _detail = result;
      if (active == null && result.allowed(auth.branch!.id)) {
        try {
          final options = TransferOptions.fromJson(
            await auth.readTransfers('/api/stock-transfers/options'),
          );
          if (!visible || !_sameBranch) return;
          result.validateOptionsScope(options);
          _options = options;
        } on ApiFailure catch (e) {
          _error = e;
        } catch (_) {
          _error = const ApiFailure(
            'Không đọc được tồn nguồn theo contract.',
            kind: ApiFailureKind.invalidResponse,
          );
        }
      }
      if (active != null) {
        final phase = result.evidence(active, _envelope!.user);
        if (phase != null) {
          await _persist(
            _Envelope(
              _envelope!.origin,
              _envelope!.user,
              active.withPhase(phase),
              _envelope!.journal,
            ),
          );
          _state = _stateOf(phase);
        } else if (active.phase != 'denied') {
          _state = DispatchState.unknown;
        }
      }
    } on ApiFailure catch (e) {
      _error = e;
    } catch (_) {
      _blocked();
    }
  }

  Future<void> reload() async {
    if (!visible || busy || _state == DispatchState.storageBlocked) return;
    busy = true;
    _emit();
    try {
      await _loadDetail();
    } finally {
      _finish();
    }
  }

  Future<void> submit(List<DispatchLine> input) async {
    if (!canDispatch) return;
    final lines = List<DispatchLine>.unmodifiable(input);
    try {
      _detail!.validate(lines, options: _options);
    } catch (e) {
      _error = ApiFailure(
        e is FormatException ? e.message : 'Số xuất không hợp lệ.',
        status: 422,
      );
      _emit();
      return;
    }
    final expected = _detail!, id = expected.detail.transfer.id;
    final origin = auth.api.storageNamespace, user = auth.profile!.userId;
    final branch = auth.branch!.id, revision = auth.authorizationRevision;
    busy = true;
    _emit();
    try {
      await _read(origin, user, revision);
      if (!visible || auth.branch?.id != branch || _envelope!.active != null) {
        return;
      }
      DispatchDetail fresh;
      try {
        fresh = await _get(id);
      } on ApiFailure catch (e) {
        _error = e;
        return;
      }
      if (!visible || auth.branch?.id != branch) return;
      _detail = fresh;
      if (!fresh.allowed(branch) || fresh.fingerprint != expected.fingerprint) {
        _error = const ApiFailure(
          'Phiếu hoặc quyền đã đổi. Hãy kiểm tra lại dữ liệu mới trước khi thao tác.',
          status: 409,
        );
        return;
      }
      try {
        final options = TransferOptions.fromJson(
          await auth.readTransfers('/api/stock-transfers/options'),
        );
        if (!visible || auth.branch?.id != branch) return;
        fresh.validate(lines, options: options);
        _options = options;
      } on ApiFailure catch (e) {
        _error = e;
        return;
      } catch (e) {
        _error = ApiFailure(
          e is FormatException ? e.message : 'Không kiểm tra được tồn nguồn.',
          status: 422,
        );
        return;
      }
      if (await store.read(origin, user) != _diskRaw) {
        throw StateError('Dấu vết đã đổi.');
      }
      if (!visible || auth.branch?.id != branch) return;
      final random = Random.secure();
      final pending = DispatchAttempt(
        attemptId: List.generate(
          16,
          (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join(),
        id: id,
        branchId: branch,
        lines: lines,
        fingerprint: fresh.fingerprint,
        createdAt: DateTime.now().toUtc().toIso8601String(),
        phase: 'pending',
      );
      final journal = _envelope!.journal;
      _state = DispatchState.sending;
      await _persist(_Envelope(origin, user, pending, journal));
      _emit();
      var phase = 'unknown';
      try {
        await auth.dispatchTransfer(
          id,
          {
            'items': [for (final line in lines) line.toJson()],
          },
          userId: user,
          branchId: branch,
          revision: revision,
        );
      } on ApiFailure catch (e) {
        _error = e;
        if (e.definiteRejection) phase = 'denied';
      } catch (_) {}
      await _persist(
        _Envelope(origin, user, pending.withPhase(phase), journal),
      );
      _state = _stateOf(phase);
      if (visible && _sameBranch) await _loadDetail();
    } catch (_) {
      _blocked();
    } finally {
      _finish();
    }
  }

  Future<void> complete() async {
    if (!canComplete) return;
    busy = true;
    _emit();
    try {
      await _loadDetail();
      if (!visible ||
          !_sameBranch ||
          _detail == null ||
          !{
            DispatchState.verified,
            DispatchState.handledElsewhere,
            DispatchState.denied,
          }.contains(_state)) {
        return;
      }
      final old = _envelope!, active = _envelope!.active!;
      if (await store.read(old.origin, old.user) != _diskRaw) {
        throw StateError('Dấu vết đã đổi.');
      }
      if (!visible || !_sameBranch) return;
      await _persist(
        _Envelope(old.origin, old.user, null, [
          ...old.journal,
          {
            'attempt': active.toJson(),
            'observation': _detail!.observation,
            'archived_at': DateTime.now().toUtc().toIso8601String(),
          },
        ]),
      );
      _state = DispatchState.ready;
      _detail = null;
      _targetId = null;
      _error = null;
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
