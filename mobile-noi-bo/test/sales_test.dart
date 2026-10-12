import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:klcn186_mobile/auth/api_client.dart';
import 'package:klcn186_mobile/auth/auth_controller.dart';
import 'package:klcn186_mobile/auth/models.dart';
import 'package:klcn186_mobile/sales/models.dart';
import 'package:klcn186_mobile/sales/repository.dart';

import 'auth_test.dart' as support;
import 'sales_fixtures.dart' as fixture;

Future<AuthController> ready(
  FutureOr<http.Response> Function(http.Request) handler, {
  support.MemoryStore? store,
}) async {
  final controller = AuthController(
    support.testApi(
      (request) => request.url.path == '/api/me'
          ? support.jsonResponse(support.profileJson())
          : handler(request),
    ),
    store ??
        (support.MemoryStore()
          ..session = support.validSession(branchId: fixture.branchId)),
  );
  await controller.restore();
  return controller;
}

void main() {
  test(
    'options preserve BIGINT decimals and filter branch, chain and warehouse',
    () {
      final scoped = SalesOptions.fromJson(
        fixture.options(),
      ).forBranch(fixture.branchId, '1');
      expect(scoped.warehouses.single.id, '11');
      expect(scoped.customers.single.id, '21');
      expect(scoped.stock.single.quantity.toString(), '100.125');
      expect(scoped.stock.single.taxRate, isNull);
      expect(scoped.stock.single.expiresOn, isNull);
    },
  );
  test('profile identifies current creator without converting BIGINT', () {
    expect(Profile.fromJson(support.profileJson()).userId, '9007199254740993');
  });
  test(
    'draft uses stored net plus tax instead of zero header; confirmed uses API',
    () {
      final draft = SalesOrderDetail.fromJson(fixture.detail(draft: true));
      expect(draft.order.total.toString(), '0.00');
      expect(draft.displayedTotal.toString(), '257400.00');
      expect(draft.items.single.unitCost, isNull);
      final confirmed = SalesOrderDetail.fromJson(fixture.detail());
      expect(confirmed.displayedTotal.toString(), '257400.00');
      expect(confirmed.paid.toString(), '100000.00');
      expect(confirmed.remaining.toString(), '157400.00');
      expect(confirmed.items.single.unitCost.toString(), '80000.123456');
    },
  );
  test('missing tax or empty lines is unknown draft total, not zero', () {
    expect(
      SalesOrderDetail.fromJson(
        fixture.detail(draft: true, missingTax: true),
      ).displayedTotal,
      isNull,
    );
    final empty = fixture.detail(draft: true)..['items'] = [];
    expect(SalesOrderDetail.fromJson(empty).displayedTotal, isNull);
  });
  test(
    'rejects numeric IDs, double money, mismatched lines and invalid tax',
    () {
      final cases = [
        fixture.detail(),
        fixture.detail(),
        fixture.detail(),
        fixture.detail(),
      ];
      (cases[0]['data'] as Json)['id'] = 9007199254740997;
      (cases[1]['items'] as List).first['unit_price'] = 125000.0;
      (cases[2]['items'] as List).first['order_id'] = '1';
      (cases[3]['items'] as List).first['tax_rate_snapshot'] = '101.00';
      for (final json in cases) {
        expect(
          () => SalesOrderDetail.fromJson(json),
          throwsA(anyOf(isA<FormatException>(), isA<TypeError>())),
        );
      }
    },
  );
  test(
    'history, detail and options are only GET with existing Bearer and selected scope',
    () async {
      final requests = <http.Request>[];
      final controller = await ready((request) {
        requests.add(request);
        return support.jsonResponse(switch (request.url.path) {
          '/api/sales-orders/options' => fixture.options(),
          '/api/sales-orders' => fixture.history(),
          _ => fixture.detail(),
        });
      });
      addTearDown(controller.dispose);
      final repository = SalesRepository(controller);
      expect((await repository.history()).length, 2);
      expect((await repository.options()).warehouses.length, 1);
      expect(
        (await repository.detail(fixture.orderId)).order.id,
        fixture.orderId,
      );
      expect(requests.length, 3);
      for (final request in requests) {
        expect(request.method, 'GET');
        expect(request.headers['Authorization'], 'Bearer test-token');
        expect(request.body, isEmpty);
      }
      expect(
        () => controller.api.readSales(
          support.validSession(),
          '/api/sales-orders/1/confirm',
        ),
        throwsFormatException,
      );
    },
  );
  for (final entry in {
    401: ApiFailureKind.unauthenticated,
    403: ApiFailureKind.forbidden,
    404: ApiFailureKind.notFound,
    409: ApiFailureKind.conflict,
    422: ApiFailureKind.validation,
    429: ApiFailureKind.rateLimited,
    500: ApiFailureKind.server,
  }.entries) {
    test(
      'HTTP ${entry.key} is typed and never retried; session gating is correct',
      () async {
        var calls = 0;
        final store = support.MemoryStore()
          ..session = support.validSession(branchId: fixture.branchId);
        final controller = await ready((_) {
          calls++;
          return support.jsonResponse({
            'message': 'private SQL token',
          }, entry.key);
        }, store: store);
        addTearDown(controller.dispose);
        await expectLater(
          SalesRepository(controller).history(),
          throwsA(
            isA<ApiFailure>()
                .having((error) => error.kind, 'kind', entry.value)
                .having(
                  (error) => error.message.contains('private SQL'),
                  'safe message',
                  false,
                ),
          ),
        );
        expect(calls, 1);
        expect(
          controller.stage,
          entry.key == 401
              ? AuthStage.signedOut
              : entry.key == 403
              ? AuthStage.unavailable
              : AuthStage.ready,
        );
        expect(store.session == null, entry.key == 401);
      },
    );
  }
  test(
    '422 exposes only structured validation and malformed JSON is typed',
    () async {
      final api = support.testApi(
        (_) => support.jsonResponse({
          'errors': {
            'amount': ['Tiền không hợp lệ'],
            'bad key': ['hidden'],
          },
          'message': 'SQL',
        }, 422),
      );
      addTearDown(api.close);
      await expectLater(
        api.readSales(support.validSession(), '/api/sales-orders'),
        throwsA(
          isA<ApiFailure>().having(
            (error) => error.fieldErrors.keys.toList(),
            'fields',
            ['amount'],
          ),
        ),
      );
      final malformed = support.testApi(
        (_) => http.Response('<html>SQL</html>', 200),
      );
      addTearDown(malformed.close);
      await expectLater(
        malformed.readSales(support.validSession(), '/api/sales-orders'),
        throwsA(
          isA<ApiFailure>().having(
            (error) => error.kind,
            'kind',
            ApiFailureKind.invalidResponse,
          ),
        ),
      );
    },
  );
  test('network and timeout do not retry or discard valid session', () async {
    var calls = 0;
    final controller = await ready((_) {
      calls++;
      throw http.ClientException('offline');
    });
    addTearDown(controller.dispose);
    await expectLater(
      SalesRepository(controller).history(),
      throwsA(
        isA<ApiFailure>().having(
          (error) => error.kind,
          'kind',
          ApiFailureKind.network,
        ),
      ),
    );
    expect(calls, 1);
    expect(controller.stage, AuthStage.ready);
    final slow = support.testApi(
      (_) => Completer<http.Response>().future,
      timeout: const Duration(milliseconds: 5),
    );
    addTearDown(slow.close);
    await expectLater(
      slow.readSales(support.validSession(), '/api/sales-orders'),
      throwsA(
        isA<ApiFailure>().having(
          (error) => error.kind,
          'kind',
          ApiFailureKind.timeout,
        ),
      ),
    );
  });
  test(
    'invalid model response and wrong branch detail cannot be used',
    () async {
      var badFormat = true;
      final controller = await ready((_) {
        if (badFormat) return support.jsonResponse({'data': []});
        final other = fixture.detail();
        (other['data'] as Json)['branch_id'] = '2';
        return support.jsonResponse(other);
      });
      addTearDown(controller.dispose);
      final repository = SalesRepository(controller);
      await expectLater(
        repository.detail(fixture.orderId),
        throwsA(
          isA<ApiFailure>().having(
            (error) => error.kind,
            'kind',
            ApiFailureKind.invalidResponse,
          ),
        ),
      );
      badFormat = false;
      await expectLater(
        repository.detail(fixture.orderId),
        throwsA(
          isA<ApiFailure>().having((error) => error.status, 'status', 404),
        ),
      );
    },
  );
  test(
    'old read response is rejected after permission refresh completes',
    () async {
      final response = Completer<http.Response>();
      final controller = await ready((_) => response.future);
      addTearDown(controller.dispose);
      final future = SalesRepository(controller).history();
      final assertion = expectLater(future, throwsA(isA<ApiFailure>()));
      await controller.refresh();
      response.complete(support.jsonResponse(fixture.history()));
      await assertion;
      expect(controller.stage, AuthStage.ready);
    },
  );
  test(
    'old 401 after revalidation does not clear renewed valid context',
    () async {
      final response = Completer<http.Response>();
      final controller = await ready((_) => response.future);
      addTearDown(controller.dispose);
      final assertion = expectLater(
        SalesRepository(controller).history(),
        throwsA(isA<ApiFailure>()),
      );
      await controller.refresh();
      response.complete(support.jsonResponse({}, 401));
      await assertion;
      expect(controller.stage, AuthStage.ready);
    },
  );
  test(
    'no business GET when scope unverified and timezone is Vietnam',
    () async {
      var calls = 0;
      final controller = await ready((_) {
        calls++;
        return support.jsonResponse(fixture.history());
      });
      addTearDown(controller.dispose);
      controller.changeScope();
      await expectLater(
        SalesRepository(controller).history(),
        throwsA(isA<ApiFailure>()),
      );
      expect(calls, 0);
      expect(saleDate('2026-10-12T03:30:00Z'), '12/10/2026 • 10:30');
      expect(saleDate('2026-10-12T10:30:00+07:00'), '12/10/2026 • 10:30');
    },
  );
}
