import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:klcn186_mobile/auth/auth_controller.dart';
import 'package:klcn186_mobile/transfers/request_models.dart';
import 'package:klcn186_mobile/transfers/request_store.dart';

import 'auth_test.dart' as auth;
import 'transfer_fixtures.dart' as transfer;

const userId = '9007199254740993';
const origin = 'https://api.example.test';
const branchId = transfer.branchId;
const lotId = '9007199254741015';
const transferId = transfer.transferId;

class TransferMemoryStore implements TransferAttemptStore {
  final Map<String, String> values = {};
  int reads = 0, writes = 0;
  int? failReadAt, failWriteAt, mismatchAt;
  String? get raw => values['$origin|$userId'];
  set raw(String? value) {
    if (value == null) {
      values.remove('$origin|$userId');
    } else {
      values['$origin|$userId'] = value;
    }
  }

  @override
  Future<String?> read(String origin, String userId) async {
    reads++;
    if (reads == failReadAt) throw StateError('read failed');
    if (reads == mismatchAt) return null;
    return values['$origin|$userId'];
  }

  @override
  Future<void> write(String origin, String userId, String value) async {
    writes++;
    if (writes == failWriteAt) throw StateError('write failed');
    values['$origin|$userId'] = value;
  }
}

Map<String, dynamic> options() {
  Map<String, dynamic> warehouse(String id, String branch, String chain) => {
    'id': id,
    'branch_id': branch,
    'chain_id': chain,
    'name': 'Kho $id vật tư nông nghiệp',
    'branch_name': 'Chi nhánh $branch',
  };
  return {
    'sources': [
      warehouse('11', branchId, '1'),
      warehouse('13', '2', '1'),
      warehouse('14', branchId, '2'),
    ],
    'destinations': [
      warehouse('11', branchId, '1'),
      warehouse('12', '2', '1'),
      warehouse('14', branchId, '2'),
    ],
    'lots': [
      for (final warehouse in ['11', '13'])
        <String, dynamic>{
          'warehouse_id': warehouse,
          'lot_id': lotId,
          'quantity': '10.125',
          'lot_no': 'LO-QA-26',
          'product_code': 'NPK-168',
          'product_name': 'Phân bón NPK 16-16-8',
          'unit_name': 'bao',
        },
    ],
  };
}

TransferPayload payload({String qty = '2.125', String branch = branchId}) =>
    TransferPayload(
      branchId: branch,
      fromId: '11',
      toId: '12',
      lines: [TransferRequestLine(lotId, qty)],
    );

Map<String, dynamic> detail() {
  final result = transfer.detail(status: 'requested');
  final data = result['data'] as Map<String, dynamic>;
  for (final key in [
    'approved_at',
    'rejected_at',
    'dispatched_at',
    'received_at',
    'reconciled_at',
  ]) {
    data[key] = null;
  }
  final line = (result['items'] as List).single as Map<String, dynamic>;
  for (final key in [
    'dispatched_quantity',
    'received_quantity',
    'supplemental_received_quantity',
    'returned_quantity',
    'lost_quantity',
  ]) {
    line[key] = '0.000';
  }
  return result;
}

Future<AuthController> ready(
  FutureOr<http.Response> Function(http.Request) handler, {
  required TransferMemoryStore store,
  Duration? timeout,
  Map<String, dynamic> Function()? profile,
}) async {
  final controller = AuthController(
    auth.testApi(
      (request) => request.url.path == '/api/me'
          ? auth.jsonResponse(profile?.call() ?? auth.profileJson())
          : handler(request),
      timeout: timeout,
    ),
    auth.MemoryStore()..session = auth.validSession(branchId: branchId),
    transferStore: store,
  );
  await controller.restore();
  return controller;
}
