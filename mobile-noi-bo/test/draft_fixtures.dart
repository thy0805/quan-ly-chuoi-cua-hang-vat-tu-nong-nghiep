import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:klcn186_mobile/auth/api_client.dart';
import 'package:klcn186_mobile/auth/auth_controller.dart';
import 'package:klcn186_mobile/auth/models.dart';
import 'package:klcn186_mobile/sales/cart.dart';
import 'package:klcn186_mobile/sales/draft_attempt_store.dart';
import 'package:klcn186_mobile/sales/draft_submission.dart';
import 'package:klcn186_mobile/sales/models.dart';

import 'auth_test.dart' as auth;
import 'cart_fixtures.dart' as cart;
import 'sales_fixtures.dart' as sales;

const origin = 'https://api.example.test';
const userId = '9007199254740993';

class MemoryDraftStore implements DraftAttemptStore {
  final values = <String, String>{};
  final operations = <String>[];
  bool failRead = false;
  int writes = 0;
  int? failWrite;
  bool dropWrites = false;
  Future<void> Function()? beforeRead;
  String key(String origin, String userId) => '$origin|$userId';

  @override
  Future<String?> read(String origin, String userId) async {
    operations.add('read:$userId');
    await beforeRead?.call();
    if (failRead) throw StateError('storage read failed');
    return values[key(origin, userId)];
  }

  @override
  Future<void> write(String origin, String userId, String value) async {
    writes++;
    operations.add('write:${jsonDecode(value)['state']}:$userId');
    if (failWrite == writes) throw StateError('storage write failed');
    if (!dropWrites) values[key(origin, userId)] = value;
  }
}

SalesCart salesCart() {
  final value = SalesCart(
    SalesOptions.fromJson(cart.options()),
    sales.branchId,
    '1',
  )..selectWarehouse('11');
  value.add(value.stock.first, DateTime.now());
  value.lines.first.quantityText = '2';
  value.lines.first.discountText = '20000';
  return value;
}

DraftPayload payload() =>
    DraftPayload.fromCart(salesCart(), sales.branchId, DateTime.now());

DraftAttempt attempt({
  String state = 'pending',
  String actor = userId,
  String server = origin,
}) => DraftAttempt(
  attemptId: 'a' * 32,
  origin: server,
  userId: actor,
  payload: payload(),
  createdAt: '2026-10-13T00:00:00Z',
  state: state,
  orderId: state == 'known_id' ? sales.draftId : null,
);

Json detail({bool missingTax = false}) {
  final value = sales.detail(draft: true, missingTax: missingTax);
  (value['items'] as List).first.addAll({
    'lot_id': '31',
    'quantity': '2.000',
    'unit_price': '100000.00',
    'discount_amount': '20000.00',
    'line_total': '180000.00',
    'tax_rate_snapshot': missingTax ? null : '5.00',
    'tax_amount': missingTax ? null : '9000.00',
  });
  return value;
}

Future<AuthController> ready(
  FutureOr<http.Response> Function(http.Request) handler, {
  required MemoryDraftStore store,
  Duration timeout = const Duration(seconds: 20),
  String baseUrl = origin,
  Json Function()? profile,
  Session? session,
}) async {
  final controller = AuthController(
    ApiClient(
      baseUrl: baseUrl,
      timeout: timeout,
      client: MockClient((request) async {
        if (request.url.path == '/api/me') {
          return auth.jsonResponse(profile?.call() ?? auth.profileJson());
        }
        if (request.url.path == '/api/mobile/logout') {
          return auth.jsonResponse({});
        }
        return handler(request);
      }),
    ),
    auth.MemoryStore()
      ..session = session ?? auth.validSession(branchId: sales.branchId),
    draftStore: store,
  );
  await controller.restore();
  return controller;
}

http.Response created() =>
    auth.jsonResponse({'id': sales.draftId, 'status': 'draft'}, 201);
