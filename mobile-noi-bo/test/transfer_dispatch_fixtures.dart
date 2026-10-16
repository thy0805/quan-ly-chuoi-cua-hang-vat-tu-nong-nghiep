import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:klcn186_mobile/auth/auth_controller.dart';
import 'package:klcn186_mobile/transfers/dispatch_models.dart';
import 'package:klcn186_mobile/transfers/dispatch_store.dart';

import 'auth_test.dart' as auth;
import 'transfer_request_fixtures.dart' as request;

const userId = request.userId;
const branchId = request.branchId;
const transferId = request.transferId;
const lotId = request.lotId;
const origin = request.origin;

class DispatchMemoryStore implements TransferDispatchStore {
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

Map<String, dynamic> detail({
  String status = 'approved',
  String? actor,
  bool permission = true,
  String quantity = '2.125',
}) {
  final result = request.detail();
  final data = result['data'] as Map<String, dynamic>;
  data.addAll({
    'status': status,
    'requested_by': userId,
    'can_dispatch': status == 'approved' && permission,
    'approved_by': '7',
    'approved_at': '2026-10-16T02:00:00Z',
    'dispatched_by': null,
    'dispatched_at': null,
    'can_approve': false,
    'can_reject': false,
  });
  if ({
    'dispatched',
    'received',
    'discrepancy',
    'reconciled',
  }.contains(status)) {
    data['dispatched_by'] = actor ?? userId;
    data['dispatched_at'] = '2026-10-16T03:00:00Z';
    (result['items'] as List).single['dispatched_quantity'] = quantity;
  }
  return result;
}

List<DispatchLine> lines([String quantity = '2.125']) => [
  DispatchLine(lotId, quantity),
];
Map<String, dynamic> options() => request.options();

Future<AuthController> ready(
  FutureOr<http.Response> Function(http.Request) handler, {
  DispatchMemoryStore? store,
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
    dispatchStore: store ?? DispatchMemoryStore(),
  );
  await controller.restore();
  return controller;
}
