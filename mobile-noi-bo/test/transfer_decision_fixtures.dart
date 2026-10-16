import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:klcn186_mobile/auth/auth_controller.dart';
import 'package:klcn186_mobile/transfers/decision_store.dart';

import 'auth_test.dart' as auth;
import 'transfer_request_fixtures.dart' as request;

const userId = request.userId;
const branchId = request.branchId;
const transferId = request.transferId;
const origin = request.origin;

class DecisionMemoryStore implements TransferDecisionStore {
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
  String status = 'requested',
  String? actor,
  String? reason,
  bool permission = true,
  String creator = '7',
}) {
  final data = request.detail();
  final row = data['data'] as Map<String, dynamic>;
  row.addAll({
    'status': status,
    'requested_by': creator,
    'approved_by': null,
    'rejected_by': null,
    'can_approve': permission && status == 'requested',
    'can_reject': permission && status == 'requested',
    'rejection_reason': reason,
  });
  if ({
    'approved',
    'dispatched',
    'received',
    'discrepancy',
    'reconciled',
  }.contains(status)) {
    row['approved_by'] = actor ?? userId;
    row['approved_at'] = '2026-10-16T03:00:00Z';
  }
  if (status == 'rejected') {
    row['rejected_by'] = actor ?? userId;
    row['rejected_at'] = '2026-10-16T03:00:00Z';
  }
  return data;
}

Future<AuthController> ready(
  FutureOr<http.Response> Function(http.Request) handler, {
  DecisionMemoryStore? store,
  Duration? timeout,
  Map<String, dynamic> Function()? profile,
}) async {
  final controller = AuthController(
    auth.testApi(
      (r) => r.url.path == '/api/me'
          ? auth.jsonResponse(profile?.call() ?? auth.profileJson())
          : handler(r),
      timeout: timeout,
    ),
    auth.MemoryStore()..session = auth.validSession(branchId: branchId),
    decisionStore: store ?? DecisionMemoryStore(),
  );
  await controller.restore();
  return controller;
}
