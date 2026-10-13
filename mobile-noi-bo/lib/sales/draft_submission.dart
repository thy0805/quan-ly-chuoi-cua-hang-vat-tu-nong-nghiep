import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../auth/api_client.dart';
import '../auth/auth_controller.dart';
import '../core/numbers.dart';
import 'cart.dart';
import 'draft_attempt_store.dart';
import 'models.dart';
import 'repository.dart';

class DraftPayload {
  DraftPayload.fromJson(Json json) {
    if (json.keys.toSet().difference({
      'branch_id',
      'warehouse_id',
      'customer_id',
      'items',
    }).isNotEmpty) {
      throw const FormatException('Trường tạo nháp không hợp lệ.');
    }
    branchId = jsonId(json['branch_id']);
    warehouseId = jsonId(json['warehouse_id']);
    customerId = json['customer_id'] == null
        ? null
        : jsonId(json['customer_id']);
    final rows = json['items'] as List;
    if (rows.isEmpty || rows.length > 50) {
      throw const FormatException('Đơn nháp cần từ 1 đến 50 lô.');
    }
    final seen = <String>{};
    items = List.unmodifiable(
      rows.map((row) {
        final item = row as Json;
        if (item.keys.toSet().difference({
          'lot_id',
          'quantity',
          'discount_amount',
        }).isNotEmpty) {
          throw const FormatException('Không gửi giá hoặc thuế.');
        }
        final lot = jsonId(item['lot_id']);
        if (!seen.add(lot)) throw const FormatException('Lô bị lặp.');
        return Map<String, String>.unmodifiable({
          'lot_id': lot,
          'quantity': cartNumber(
            item['quantity'] as String,
            quantity: true,
          ).toString(),
          'discount_amount': cartNumber(
            item['discount_amount'] as String,
            quantity: false,
          ).toString(),
        });
      }),
    );
  }

  factory DraftPayload.fromCart(SalesCart cart, String branchId, DateTime now) {
    cart.totals(now);
    if (cart.customerId != null &&
        !cart.options.customers.any(
          (customer) => customer.id == cart.customerId,
        )) {
      throw const FormatException('Khách không thuộc chuỗi đang làm việc.');
    }
    if (!cart.options.warehouses.any(
      (warehouse) =>
          warehouse.id == cart.warehouseId && warehouse.branchId == branchId,
    )) {
      throw const FormatException('Chọn kho thuộc chi nhánh đang làm việc.');
    }
    return DraftPayload.fromJson({
      'branch_id': branchId,
      'warehouse_id': cart.warehouseId,
      'customer_id': cart.customerId,
      'items': [
        for (final line in cart.lines)
          {
            'lot_id': line.stock.lotId,
            'quantity': cartNumber(
              line.quantityText,
              quantity: true,
            ).toString(),
            'discount_amount': cartNumber(
              line.discountText,
              quantity: false,
            ).toString(),
          },
      ],
    });
  }

  late final String branchId, warehouseId;
  late final String? customerId;
  late final List<Map<String, String>> items;
  Json toJson() => {
    'branch_id': branchId,
    'warehouse_id': warehouseId,
    'customer_id': customerId,
    'items': items,
  };
  String get fingerprint => jsonEncode(toJson());

  bool matches(SalesOrderDetail detail, String userId) =>
      detail.createdBy == userId &&
      detail.order.branchId == branchId &&
      detail.warehouseId == warehouseId &&
      detail.order.customerId == customerId &&
      detail.items.length == items.length &&
      items.every(
        (expected) =>
            detail.items
                    .where((item) => item.lotId == expected['lot_id'])
                    .length ==
                1 &&
            detail.items.any(
              (item) =>
                  item.lotId == expected['lot_id'] &&
                  item.quantity.toString() == expected['quantity'] &&
                  item.discount.toString() == expected['discount_amount'],
            ),
      );
}

enum DraftState {
  editing,
  loading,
  sending,
  knownId,
  unknownOutcome,
  rejected,
  storageBlocked,
}

class DraftAttempt {
  const DraftAttempt({
    required this.attemptId,
    required this.origin,
    required this.userId,
    required this.payload,
    required this.createdAt,
    required this.state,
    this.orderId,
  });

  final String attemptId, origin, userId, createdAt;
  final DraftPayload payload;
  final String state;
  final String? orderId;

  factory DraftAttempt.decode(String value, String origin, String userId) {
    final json = jsonDecode(value) as Json;
    final payload = DraftPayload.fromJson(json['payload'] as Json);
    final state = json['state'] as String;
    final id = json['order_id'] == null ? null : jsonId(json['order_id']);
    if (json['version'] != 1 ||
        json['origin'] != origin ||
        jsonId(json['user_id']) != userId ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(json['attempt_id'] as String) ||
        DateTime.tryParse(json['created_at'] as String) == null ||
        json['fingerprint'] != payload.fingerprint ||
        !{
          'pending',
          'known_id',
          'unknown_outcome',
          'rejected',
        }.contains(state) ||
        (state == 'known_id') != (id != null)) {
      throw const FormatException('Dấu vết tạo nháp không hợp lệ.');
    }
    return DraftAttempt(
      attemptId: json['attempt_id'] as String,
      origin: origin,
      userId: userId,
      payload: payload,
      createdAt: json['created_at'] as String,
      state: state,
      orderId: id,
    );
  }

  DraftAttempt withState(String state, {String? orderId}) => DraftAttempt(
    attemptId: attemptId,
    origin: origin,
    userId: userId,
    payload: payload,
    createdAt: createdAt,
    state: state,
    orderId: orderId,
  );
  String encode() => jsonEncode({
    'version': 1,
    'attempt_id': attemptId,
    'origin': origin,
    'user_id': userId,
    'payload': payload.toJson(),
    'fingerprint': payload.fingerprint,
    'created_at': createdAt,
    'state': state,
    'order_id': orderId,
  });
}

class DraftSubmission extends ChangeNotifier {
  DraftSubmission(this.auth, this.store) {
    auth.addListener(_authChanged);
  }

  final AuthController auth;
  final DraftAttemptStore store;
  bool busy = false;
  bool _active = false;
  bool _disposed = false;
  String? _boundKey;
  DraftAttempt? _attempt;
  SalesOrderDetail? _detail;
  ApiFailure? _error;
  DraftState _state = DraftState.loading;
  final Map<String, DraftAttempt> _unsaved = {};

  String? get _currentKey =>
      auth.stage == AuthStage.ready &&
          !auth.busy &&
          auth.profile != null &&
          auth.branch != null
      ? '${auth.api.storageNamespace}|${auth.profile!.userId}'
      : null;
  bool get visible => _currentKey != null && _currentKey == _boundKey;
  DraftState get state => visible ? _state : DraftState.loading;
  DraftAttempt? get attempt => visible ? _attempt : null;
  SalesOrderDetail? get detail =>
      visible && _attempt?.payload.branchId == auth.branch?.id ? _detail : null;
  ApiFailure? get error => visible ? _error : null;
  bool get canCreate =>
      visible &&
      !busy &&
      (_state == DraftState.editing || _state == DraftState.rejected);

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void _authChanged() {
    _detail = null;
    _emit();
    if (_active && !busy && _currentKey != null && _currentKey != _boundKey) {
      unawaited(restore());
    }
  }

  Future<void> _persist(DraftAttempt attempt) async {
    final key = '${attempt.origin}|${attempt.userId}';
    _unsaved[key] = attempt;
    final value = attempt.encode();
    await store.write(attempt.origin, attempt.userId, value);
    if (await store.read(attempt.origin, attempt.userId) != value) {
      throw StateError('Không xác minh được dữ liệu lưu.');
    }
    _unsaved.remove(key);
  }

  void _blocked() {
    _state = DraftState.storageBlocked;
    _detail = null;
    _error = const ApiFailure(
      'Không xác minh được bộ nhớ tạo nháp. Tạm khóa gửi để tránh tạo trùng. Kiểm tra bộ nhớ rồi đọc lại trạng thái.',
    );
  }

  Future<void> _read(String origin, String userId) async {
    _boundKey = '$origin|$userId';
    _attempt = null;
    _detail = null;
    _error = null;
    _state = DraftState.loading;
    _emit();
    final unsaved = _unsaved[_boundKey];
    if (unsaved != null) await _persist(unsaved);
    final raw = await store.read(origin, userId);
    if (raw == null) {
      _state = DraftState.editing;
    } else {
      _attempt = DraftAttempt.decode(raw, origin, userId);
      _state = switch (_attempt!.state) {
        'known_id' => DraftState.knownId,
        'rejected' => DraftState.rejected,
        _ => DraftState.unknownOutcome,
      };
    }
  }

  void _finish() {
    busy = false;
    _emit();
    if (!_disposed &&
        _active &&
        _currentKey != null &&
        _currentKey != _boundKey) {
      unawaited(restore());
    }
  }

  Future<void> restore() async {
    _active = true;
    if (busy || _currentKey == null) return;
    busy = true;
    final origin = auth.api.storageNamespace;
    final userId = auth.profile!.userId;
    try {
      await _read(origin, userId);
    } catch (_) {
      _blocked();
    } finally {
      _finish();
    }
  }

  Future<void> submit(
    DraftPayload payload, {
    required String origin,
    required String userId,
  }) async {
    _active = true;
    if (busy ||
        _currentKey != '$origin|$userId' ||
        auth.branch?.id != payload.branchId) {
      return;
    }
    busy = true;
    DraftAttempt? pending;
    var sendStarted = false;
    try {
      await _read(origin, userId);
      if (_state != DraftState.editing && _state != DraftState.rejected) return;
      if (_currentKey != _boundKey || auth.branch?.id != payload.branchId) {
        return;
      }
      final random = Random.secure();
      pending = DraftAttempt(
        attemptId: List.generate(
          16,
          (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join(),
        origin: origin,
        userId: userId,
        payload: payload,
        createdAt: DateTime.now().toUtc().toIso8601String(),
        state: 'pending',
      );
      _attempt = pending;
      _state = DraftState.sending;
      _emit();
      await _persist(pending);
      sendStarted = true;
      try {
        final id = await auth.createSalesDraft(
          payload.toJson(),
          userId: userId,
        );
        _attempt = pending.withState('known_id', orderId: id);
      } on ApiFailure catch (error) {
        _error = error;
        _attempt = pending.withState(
          error.definiteRejection ? 'rejected' : 'unknown_outcome',
        );
      } catch (_) {
        _attempt = pending.withState('unknown_outcome');
      }
      await _persist(_attempt!);
      _state = switch (_attempt!.state) {
        'known_id' => DraftState.knownId,
        'rejected' => DraftState.rejected,
        _ => DraftState.unknownOutcome,
      };
      if (_state == DraftState.knownId &&
          _currentKey == _boundKey &&
          auth.branch?.id == payload.branchId) {
        await _loadDetail();
      }
    } catch (_) {
      if (!sendStarted && pending != null) {
        _unsaved['$origin|$userId'] = pending.withState('rejected');
      }
      _blocked();
    } finally {
      _finish();
    }
  }

  Future<void> _loadDetail() async {
    final attempt = _attempt!;
    if (_currentKey != _boundKey ||
        auth.branch?.id != attempt.payload.branchId) {
      return;
    }
    _detail = null;
    _error = null;
    try {
      final detail = await SalesRepository(auth).detail(attempt.orderId!);
      if (!attempt.payload.matches(detail, attempt.userId)) {
        throw const ApiFailure(
          'Chi tiết không khớp lần tạo nháp đã lưu. Giữ ID để đối chiếu, không tạo lại.',
        );
      }
      if (_currentKey == _boundKey &&
          auth.branch?.id == attempt.payload.branchId) {
        _detail = detail;
      }
    } on ApiFailure catch (error) {
      _error = error;
    }
  }

  Future<void> reloadDetail() async {
    if (!visible || busy || _state != DraftState.knownId) return;
    busy = true;
    _emit();
    try {
      await _loadDetail();
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
