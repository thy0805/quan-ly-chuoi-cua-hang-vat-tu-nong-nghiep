import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:klcn186_mobile/auth/api_client.dart';
import 'package:klcn186_mobile/auth/auth_controller.dart';
import 'package:klcn186_mobile/transfers/models.dart';
import 'package:klcn186_mobile/transfers/repository.dart';

import 'auth_test.dart' as auth;
import 'sales_test.dart' as sales;
import 'transfer_fixtures.dart' as fixture;

void main() {
  test(
    'GET page uses Bearer, pagination, source OR destination branch',
    () async {
      final requests = <http.Request>[];
      final controller = await sales.ready((request) {
        requests.add(request);
        return auth.jsonResponse(
          fixture.page(
            rows: [
              fixture.summary(),
              fixture.summary(id: '20', from: '2', to: fixture.branchId),
              fixture.summary(id: '21', from: '2', to: '3'),
            ],
            current: 2,
            last: 3,
          ),
        );
      });
      addTearDown(controller.dispose);
      final result = await TransferRepository(controller).page(2);
      expect(result.rows.map((row) => row.id), [fixture.transferId, '20']);
      expect(result.current, 2);
      expect(result.hasNext, true);
      expect(requests.single.method, 'GET');
      expect(requests.single.url.path, '/api/stock-transfers');
      expect(requests.single.url.queryParameters, {
        'page': '2',
        'per_page': '50',
      });
      expect(requests.single.headers['authorization'], 'Bearer test-token');
      expect(requests.single.headers.containsKey('cookie'), false);
    },
  );

  test(
    'detail preserves BIGINT and quantity scale; timezone is Vietnam',
    () async {
      final controller = await sales.ready((request) {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/stock-transfers/${fixture.transferId}');
        return auth.jsonResponse(fixture.detail());
      });
      addTearDown(controller.dispose);
      final result = await TransferRepository(
        controller,
      ).detail(fixture.transferId);
      expect(result.transfer.id, fixture.transferId);
      expect(result.items.single.requested.toString(), '2.125');
      expect(result.items.single.lost.toString(), '0.250');
      expect(transferDate(result.transfer.requestedAt), '16/10/2026 01:30');
      expect(result.reconciliationReason, contains('hao hụt'));
    },
  );

  for (final state in transferStatuses.keys) {
    test('status $state comes from API without inferring from quantities', () {
      expect(
        TransferDetail.fromJson(fixture.detail(status: state)).transfer.status,
        state,
      );
    });
  }

  for (final invalid in [
    'numeric ID',
    'unknown status',
    'double quantity',
    'excess precision',
    'negative quantity',
    'missing quantity',
    'duplicate line',
    'missing timezone',
  ]) {
    test('invalid transfer response rejected: $invalid', () async {
      final data = fixture.detail();
      final row = data['data'] as Map<String, dynamic>;
      final items = data['items'] as List;
      switch (invalid) {
        case 'numeric ID':
          row['id'] = 9007199254741011;
        case 'unknown status':
          row['status'] = 'delivered';
        case 'double quantity':
          items.first['requested_quantity'] = 2.125;
        case 'excess precision':
          items.first['requested_quantity'] = '2.0001';
        case 'negative quantity':
          items.first['received_quantity'] = '-1.000';
        case 'missing quantity':
          items.first.remove('lost_quantity');
        case 'duplicate line':
          items.add(fixture.line());
        case 'missing timezone':
          row['requested_at'] = '2026-10-16T01:30:00';
      }
      final controller = await sales.ready((_) => auth.jsonResponse(data));
      addTearDown(controller.dispose);
      await expectLater(
        TransferRepository(controller).detail(fixture.transferId),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.kind,
            'kind',
            ApiFailureKind.invalidResponse,
          ),
        ),
      );
    });
  }

  test(
    'detail cannot display another ID or unrelated current branch',
    () async {
      for (final data in [
        fixture.detail(id: '3'),
        fixture.detail(from: '2', to: '3'),
      ]) {
        final controller = await sales.ready((_) => auth.jsonResponse(data));
        addTearDown(controller.dispose);
        await expectLater(
          TransferRepository(controller).detail(fixture.transferId),
          throwsA(isA<ApiFailure>().having((e) => e.status, 'status', 404)),
        );
      }
    },
  );

  test('bad page or mismatched pagination fails before display', () async {
    final controller = await sales.ready(
      (_) => auth.jsonResponse(fixture.page(current: 2, last: 2)),
    );
    addTearDown(controller.dispose);
    await expectLater(
      TransferRepository(controller).page(1),
      throwsA(isA<ApiFailure>()),
    );
    await expectLater(
      TransferRepository(controller).page(0),
      throwsArgumentError,
    );
    expect(
      () => TransferPage.fromJson(fixture.page(current: 2, last: 1)),
      throwsFormatException,
    );
  });

  test(
    'client route allowlist blocks actions, bad IDs and injected options query',
    () async {
      var count = 0;
      final client = auth.testApi((_) {
        count++;
        return auth.jsonResponse({});
      });
      addTearDown(client.close);
      for (final path in [
        '/api/stock-transfers/options?branch_id=2',
        '/api/stock-transfers/1/approve',
        '/api/sales-orders',
        '/api/stock-transfers/9223372036854775808',
        '/api/stock-transfers?page=1&per_page=50&branch_id=2',
        'https://another.test/api/stock-transfers',
      ]) {
        expect(
          () => client.readTransfers(auth.validSession(), path),
          throwsA(anything),
        );
      }
      expect(count, 0);
    },
  );

  for (final status in [401, 403, 404, 429, 500]) {
    test('typed HTTP $status and appropriate session state', () async {
      final controller = await sales.ready(
        (_) => auth.jsonResponse({'message': 'SQL secret hidden'}, status),
      );
      addTearDown(controller.dispose);
      await expectLater(
        TransferRepository(controller).page(1),
        throwsA(
          isA<ApiFailure>()
              .having((e) => e.status, 'status', status)
              .having(
                (e) => e.message.contains('SQL secret'),
                'no raw error',
                false,
              ),
        ),
      );
      expect(
        controller.stage,
        status == 401
            ? AuthStage.signedOut
            : status == 403
            ? AuthStage.unavailable
            : AuthStage.ready,
      );
    });
  }

  test('no branch means no transfer GET', () async {
    var calls = 0;
    final controller = await sales.ready((_) {
      calls++;
      return auth.jsonResponse(fixture.page());
    });
    addTearDown(controller.dispose);
    controller.changeScope();
    await expectLater(
      TransferRepository(controller).page(1),
      throwsA(isA<ApiFailure>()),
    );
    expect(calls, 0);
  });

  test(
    'old response after scope change is rejected by shared auth guard',
    () async {
      final response = Completer<http.Response>();
      final controller = await sales.ready((_) => response.future);
      addTearDown(controller.dispose);
      final result = TransferRepository(controller).page(1);
      final assertion = expectLater(result, throwsA(isA<ApiFailure>()));
      controller.changeScope();
      response.complete(auth.jsonResponse(fixture.page()));
      await assertion;
    },
  );

  test('network and timeout reads are typed and never retried', () async {
    var count = 0;
    final controller = await sales.ready((_) {
      count++;
      throw http.ClientException('offline');
    });
    addTearDown(controller.dispose);
    await expectLater(
      TransferRepository(controller).page(1),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.kind,
          'network',
          ApiFailureKind.network,
        ),
      ),
    );
    expect(count, 1);
    final client = auth.testApi(
      (_) => Completer<http.Response>().future,
      timeout: const Duration(milliseconds: 10),
    );
    addTearDown(client.close);
    await expectLater(
      client.readTransfers(
        auth.validSession(),
        '/api/stock-transfers?page=1&per_page=50',
      ),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.kind,
          'timeout',
          ApiFailureKind.timeout,
        ),
      ),
    );
  });
}
