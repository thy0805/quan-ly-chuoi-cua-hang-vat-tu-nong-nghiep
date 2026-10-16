import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:klcn186_mobile/auth/auth_controller.dart';
import 'package:klcn186_mobile/transfers/reconcile_models.dart';
import 'package:klcn186_mobile/transfers/reconcile_store.dart';

import 'auth_test.dart' as auth;
import 'transfer_request_fixtures.dart' as request;

const userId = request.userId;
const branchId = request.branchId;
const transferId = request.transferId;
const lotId = request.lotId;
const origin = request.origin;

class ReconcileMemoryStore implements TransferReconcileStore {
  final Map<String, String> values = {};
  int reads = 0, writes = 0;
  int? failReadAt, failWriteAt, mismatchAt;
  bool alwaysFail = false;
  String? get raw => values['$origin|$userId'];
  set raw(String? value) {
    if (value == null) {
      values.remove('$origin|$userId');
    } else {
      values['$origin|$userId'] = value;
    }
  }

  @override
  Future<String?> read(String origin, String user) async {
    reads++;
    if (alwaysFail || reads == failReadAt) {
      throw StateError('Fixture read failed');
    }
    if (reads == mismatchAt) return null;
    return values['$origin|$user'];
  }

  @override
  Future<void> write(String origin, String user, String value) async {
    writes++;
    if (alwaysFail || writes == failWriteAt) {
      throw StateError('Fixture write failed');
    }
    values['$origin|$user'] = value;
  }
}

const reason = 'Kiểm kê chênh lệch';
Map<String, dynamic> detail({
  String status = 'discrepancy',
  String? actor,
  bool permission = true,
  String supplemental = '1.000',
  String returned = '0.000',
  String lost = '0.000',
}) {
  final result = request.detail();
  final data = result['data'] as Map<String, dynamic>;
  data.addAll({
    'status': status,
    'requested_by': userId,
    'from_branch_id': '2',
    'to_branch_id': branchId,
    'can_reconcile': status == 'discrepancy' && permission,
    'can_receive': false,
    'can_approve': false,
    'can_reject': false,
    'can_dispatch': false,
    'approved_by': '7',
    'approved_at': '2026-10-16T02:00:00Z',
    'dispatched_by': '7',
    'dispatched_at': '2026-10-16T03:00:00Z',
    'received_by': '7',
    'received_at': '2026-10-16T04:00:00Z',
    'reconciled_by': status == 'reconciled' ? actor ?? userId : null,
    'reconciled_at': status == 'reconciled' ? '2026-10-16T05:00:00Z' : null,
    'reconciliation_reason': status == 'reconciled' ? reason : null,
  });
  (result['items'] as List).single.addAll({
    'dispatched_quantity': '2.125',
    'received_quantity': '1.125',
    'supplemental_received_quantity': status == 'reconciled'
        ? supplemental
        : '0.000',
    'returned_quantity': status == 'reconciled' ? returned : '0.000',
    'lost_quantity': status == 'reconciled' ? lost : '0.000',
  });
  return result;
}

List<ReconcileLine> lines([
  String supplemental = '1',
  String returned = '0',
  String lost = '0',
]) => [ReconcileLine(lotId, supplemental, returned, lost)];
Map<String, dynamic> options() => request.options();
Map<String, dynamic> outcome(Map<String, dynamic> payload, {String? actor}) {
  final result = detail(status: 'reconciled', actor: actor);
  result['data']['reconciliation_reason'] = payload['reason'];
  final original = Map<String, dynamic>.from(result['items'][0]);
  result['items'] = [
    for (final row in payload['items']) {...original, ...row},
  ];
  for (var i = 0; i < (result['items'] as List).length; i++) {
    result['items'][i]['id'] = (BigInt.parse(original['id']) + BigInt.from(i))
        .toString();
  }
  return result;
}

Future<AuthController> ready(
  FutureOr<http.Response> Function(http.Request) handler, {
  ReconcileMemoryStore? store,
  Duration? timeout,
  Map<String, dynamic> Function()? profile,
  FutureOr<http.Response> Function(http.Request)? optionsHandler,
}) async {
  final controller = AuthController(
    auth.testApi((r) {
      if (r.url.path == '/api/me') {
        return auth.jsonResponse(profile?.call() ?? auth.profileJson());
      }
      if (r.url.path == '/api/stock-transfers/options') {
        return optionsHandler?.call(r) ?? auth.jsonResponse(options());
      }
      return handler(r);
    }, timeout: timeout),
    auth.MemoryStore()..session = auth.validSession(branchId: branchId),
    reconcileStore: store ?? ReconcileMemoryStore(),
  );
  await controller.restore();
  return controller;
}
