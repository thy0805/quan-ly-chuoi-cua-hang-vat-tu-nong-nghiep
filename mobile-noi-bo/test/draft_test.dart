import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:klcn186_mobile/auth/auth_controller.dart';
import 'package:klcn186_mobile/auth/models.dart';
import 'package:klcn186_mobile/sales/draft_submission.dart';
import 'package:klcn186_mobile/sales/repository.dart';

import 'auth_test.dart' as support;
import 'draft_fixtures.dart' as fixture;
import 'sales_fixtures.dart' as sales;

Future<void> send(AuthController controller) => controller.drafts.submit(
  fixture.payload(),
  origin: fixture.origin,
  userId: fixture.userId,
);

void main() {
  for (final count in [0, 1, 50]) {
    test('history $count and matching detail cannot resolve UNKNOWN', () async {
      final store = fixture.MemoryDraftStore();
      final original = fixture.attempt(state: 'unknown_outcome').encode();
      store.values[store.key(fixture.origin, fixture.userId)] = original;
      var posts = 0;
      final controller = await fixture.ready((request) {
        if (request.method == 'POST') posts++;
        if (request.url.path == '/api/sales-orders') {
          return support.jsonResponse({
            'data': List.generate(count, (_) => sales.summary(draft: true)),
          });
        }
        return support.jsonResponse(fixture.detail());
      }, store: store);
      addTearDown(controller.dispose);
      await controller.drafts.restore();
      final repository = SalesRepository(controller);
      expect((await repository.history()).length, count);
      await repository.detail(sales.draftId);
      await controller.drafts.restore();
      await send(controller);
      expect(posts, 0);
      expect(controller.drafts.state, DraftState.unknownOutcome);
      expect(controller.drafts.attempt!.orderId, isNull);
      expect(store.values.values.single, original);
    });
  }

  test(
    'payload rejects invalid discount, foreign customer and missing tax before marker',
    () {
      for (final invalid in ['-1', '1.001', '10000000000000000', '1e3']) {
        expect(
          () => DraftPayload.fromJson({
            ...fixture.payload().toJson(),
            'items': [
              {'lot_id': '31', 'quantity': '1', 'discount_amount': invalid},
            ],
          }),
          throwsFormatException,
        );
      }
      final cart = fixture.salesCart()..customerId = '22';
      expect(
        () => DraftPayload.fromCart(cart, sales.branchId, DateTime.now()),
        throwsFormatException,
      );
    },
  );

  test(
    'session expires after marker but before transport: no POST, durable REJECTED',
    () async {
      var posts = 0;
      final store = fixture.MemoryDraftStore();
      final controller = await fixture.ready(
        (_) {
          posts++;
          return fixture.created();
        },
        store: store,
        session: Session(
          token: 'test-token',
          expiresAt: DateTime.now().add(const Duration(milliseconds: 80)),
          branchId: sales.branchId,
        ),
      );
      addTearDown(controller.dispose);
      var reads = 0;
      store.beforeRead = () async {
        if (++reads == 2) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      };
      await send(controller);
      expect(posts, 0);
      expect(jsonDecode(store.values.values.single)['state'], 'rejected');
    },
  );

  test(
    'crash before persisting ID: new process sees pending as UNKNOWN, never POSTs',
    () async {
      final store = fixture.MemoryDraftStore()..failWrite = 2;
      var posts = 0;
      final controller = await fixture.ready((_) {
        posts++;
        return fixture.created();
      }, store: store);
      await send(controller);
      expect(controller.drafts.state, DraftState.storageBlocked);
      controller.dispose();
      store.failWrite = null;
      final restarted = await fixture.ready((_) {
        posts++;
        return fixture.created();
      }, store: store);
      addTearDown(restarted.dispose);
      await restarted.drafts.restore();
      expect(restarted.drafts.state, DraftState.unknownOutcome);
      expect(restarted.drafts.attempt!.orderId, isNull);
      await send(restarted);
      expect(posts, 1);
    },
  );

  test('UNKNOWN save failure retains pending, restart fail-closed', () async {
    final store = fixture.MemoryDraftStore()..failWrite = 2;
    var posts = 0;
    final controller = await fixture.ready((_) {
      posts++;
      return http.Response('error', 500);
    }, store: store);
    await send(controller);
    expect(controller.drafts.state, DraftState.storageBlocked);
    controller.dispose();
    final restarted = await fixture.ready((_) {
      posts++;
      return fixture.created();
    }, store: store);
    addTearDown(restarted.dispose);
    await restarted.drafts.restore();
    expect(restarted.drafts.state, DraftState.unknownOutcome);
    await send(restarted);
    expect(posts, 1);
  });

  test(
    'branch change during create preserves ID, hides detail, GET only in original branch',
    () async {
      final store = fixture.MemoryDraftStore();
      final response = Completer<http.Response>();
      var posts = 0;
      var gets = 0;
      final controller = await fixture.ready(
        (request) {
          if (request.method == 'POST') {
            posts++;
            return response.future;
          }
          gets++;
          return support.jsonResponse(fixture.detail());
        },
        store: store,
        profile: () {
          final json = support.profileJson();
          (json['branches'] as List).add({
            'id': '2',
            'chain_id': '1',
            'code': 'CN02',
            'name': 'Chi nhánh hai',
          });
          return json;
        },
      );
      addTearDown(controller.dispose);
      final pending = send(controller);
      await Future<void>.delayed(Duration.zero);
      await controller.chooseBranch('2');
      response.complete(fixture.created());
      await pending;
      expect(controller.drafts.attempt!.orderId, sales.draftId);
      expect(controller.drafts.detail, isNull);
      await controller.drafts.reloadDetail();
      await send(controller);
      expect(gets, 0);
      await controller.chooseBranch(sales.branchId);
      await controller.drafts.reloadDetail();
      expect(gets, 1);
      expect(controller.drafts.detail, isNotNull);
      await controller.chooseBranch('2');
      expect(controller.drafts.detail, isNull);
      expect(posts, 1);
    },
  );
  test(
    'canonical payload preserves BIGINT, fixed scale and immutable cart snapshot',
    () {
      final cart = fixture.salesCart();
      final value = DraftPayload.fromCart(cart, sales.branchId, DateTime.now());
      cart.lines.first.quantityText = '9';
      expect(value.toJson(), {
        'branch_id': sales.branchId,
        'warehouse_id': '11',
        'customer_id': null,
        'items': [
          {'lot_id': '31', 'quantity': '2.000', 'discount_amount': '20000.00'},
        ],
      });
      expect(() => value.items.first['quantity'] = '9', throwsUnsupportedError);
      expect(
        () => DraftPayload.fromJson({...value.toJson(), 'total_amount': '1'}),
        throwsFormatException,
      );
      expect(
        () => DraftPayload.fromJson({...value.toJson(), 'branch_id': 1}),
        throwsFormatException,
      );
      expect(
        () => DraftPayload.fromJson({
          ...value.toJson(),
          'warehouse_id': '9223372036854775808',
        }),
        throwsFormatException,
      );
      expect(
        () => DraftPayload.fromJson({...value.toJson(), 'items': []}),
        throwsFormatException,
      );
      expect(
        () => DraftPayload.fromJson({
          ...value.toJson(),
          'items': List.filled(51, value.items.first),
        }),
        throwsFormatException,
      );
      expect(
        () => DraftPayload.fromJson({
          ...value.toJson(),
          'items': [value.items.first, value.items.first],
        }),
        throwsFormatException,
      );
    },
  );

  for (final invalid in ['1.0001', '1000000000000000', '1e3', '-1', '0']) {
    test('payload rejects quantity $invalid', () {
      final json = fixture.payload().toJson();
      json['items'] = [
        {'lot_id': '31', 'quantity': invalid, 'discount_amount': '0'},
      ];
      expect(() => DraftPayload.fromJson(json), throwsFormatException);
    });
  }

  test(
    'marker decode validates owner/origin/version/fingerprint/state; no token or PII',
    () {
      final value = fixture.attempt();
      final json = jsonDecode(value.encode()) as Map<String, dynamic>;
      expect(
        DraftAttempt.decode(
          value.encode(),
          fixture.origin,
          fixture.userId,
        ).payload.fingerprint,
        fixture.payload().fingerprint,
      );
      for (final patch in [
        {'version': 2},
        {'user_id': '2'},
        {'origin': 'https://other.test'},
        {'fingerprint': 'bad'},
        {'state': 'unknown'},
        {'order_id': sales.draftId},
        {'attempt_id': 'bad'},
        {'created_at': 'bad'},
      ]) {
        expect(
          () => DraftAttempt.decode(
            jsonEncode({...json, ...patch}),
            fixture.origin,
            fixture.userId,
          ),
          throwsFormatException,
        );
      }
      expect(value.encode(), isNot(contains('test-token')));
      expect(value.encode(), isNot(contains('password')));
      expect(value.encode(), isNot(contains('customer_phone')));
    },
  );

  test(
    'marker before POST; 201 ID saved/read-back before GET; only Bearer exact payload',
    () async {
      final store = fixture.MemoryDraftStore();
      final requests = <http.Request>[];
      final controller = await fixture.ready((request) {
        requests.add(request);
        final saved = DraftAttempt.decode(
          store.values.values.single,
          fixture.origin,
          fixture.userId,
        );
        if (request.method == 'POST') {
          expect(saved.state, 'pending');
          expect(jsonDecode(request.body), fixture.payload().toJson());
          expect(request.headers['Authorization'], 'Bearer test-token');
          expect(request.followRedirects, false);
          return fixture.created();
        }
        expect(saved.orderId, sales.draftId);
        expect(saved.state, 'known_id');
        return support.jsonResponse(fixture.detail());
      }, store: store);
      addTearDown(controller.dispose);
      await send(controller);
      expect(requests.map((request) => request.method), ['POST', 'GET']);
      expect(controller.drafts.state, DraftState.knownId);
      expect(controller.drafts.detail!.displayedTotal.toString(), '189000.00');
      expect(controller.drafts.detail!.order.total.toString(), '0.00');
      expect(controller.drafts.canCreate, false);
    },
  );

  test(
    'shared coordinator double tap locks before await and no second screen POST',
    () async {
      final response = Completer<http.Response>();
      var posts = 0;
      final controller = await fixture.ready((request) {
        if (request.method == 'POST') {
          posts++;
          return response.future;
        }
        return support.jsonResponse(fixture.detail());
      }, store: fixture.MemoryDraftStore());
      addTearDown(controller.dispose);
      final first = send(controller);
      await send(controller);
      await Future<void>.delayed(Duration.zero);
      expect(posts, 1);
      response.complete(fixture.created());
      await first;
      await send(controller);
      expect(posts, 1);
    },
  );

  for (final fail in ['read', 'first-write', 'silent-write']) {
    test('storage $fail blocks before POST, read-back required', () async {
      final store = fixture.MemoryDraftStore()
        ..failRead = fail == 'read'
        ..failWrite = fail == 'first-write' ? 1 : null
        ..dropWrites = fail == 'silent-write';
      var requests = 0;
      final controller = await fixture.ready((_) {
        requests++;
        return fixture.created();
      }, store: store);
      addTearDown(controller.dispose);
      await send(controller);
      expect(requests, 0);
      expect(controller.drafts.state, DraftState.storageBlocked);
      expect(controller.drafts.canCreate, false);
    });
  }

  test(
    'ID write fails: disk pending, no GET; manual storage recovery saves same ID only',
    () async {
      final store = fixture.MemoryDraftStore()..failWrite = 2;
      var posts = 0;
      var gets = 0;
      final controller = await fixture.ready((request) {
        if (request.method == 'POST') {
          posts++;
          return fixture.created();
        }
        gets++;
        return support.jsonResponse(fixture.detail());
      }, store: store);
      addTearDown(controller.dispose);
      await send(controller);
      expect(controller.drafts.state, DraftState.storageBlocked);
      expect(jsonDecode(store.values.values.single)['state'], 'pending');
      expect(gets, 0);
      store.failWrite = null;
      await controller.drafts.restore();
      expect(controller.drafts.attempt!.orderId, sales.draftId);
      await controller.drafts.reloadDetail();
      await send(controller);
      expect(posts, 1);
      expect(gets, 1);
    },
  );

  for (final error in [401, 403, 404, 500, 200]) {
    test(
      'known ID GET failure $error preserves ID across restart, retries GET only',
      () async {
        final store = fixture.MemoryDraftStore();
        var posts = 0;
        var healthy = false;
        FutureOr<http.Response> handler(http.Request request) {
          if (request.method == 'POST') {
            posts++;
            return fixture.created();
          }
          return healthy
              ? support.jsonResponse(fixture.detail())
              : error == 200
              ? http.Response('bad-json', 200)
              : support.jsonResponse({'message': 'test'}, error);
        }

        final controller = await fixture.ready(handler, store: store);
        await send(controller);
        expect(
          jsonDecode(store.values.values.single)['order_id'],
          sales.draftId,
        );
        expect(controller.drafts.detail, isNull);
        controller.dispose();
        healthy = true;
        final restarted = await fixture.ready(handler, store: store);
        addTearDown(restarted.dispose);
        await restarted.drafts.restore();
        await restarted.drafts.reloadDetail();
        expect(restarted.drafts.detail, isNotNull);
        await send(restarted);
        expect(posts, 1);
      },
    );
  }

  final ambiguous = <String, FutureOr<http.Response> Function(http.Request)>{
    'network': (_) => throw const SocketException('network'),
    'timeout': (_) => throw TimeoutException('timeout'),
    '500': (_) => support.jsonResponse({'message': 'server'}, 500),
    'redirect': (_) =>
        http.Response('', 302, headers: {'location': '/api/sales-orders'}),
    '200-instead-201': (_) =>
        support.jsonResponse({'id': sales.draftId, 'status': 'draft'}),
    '201-malformed': (_) => http.Response('{', 201),
    '201-no-id': (_) => support.jsonResponse({'status': 'draft'}, 201),
    '201-numeric-id': (_) =>
        support.jsonResponse({'id': 123, 'status': 'draft'}, 201),
    '201-overflow-id': (_) => support.jsonResponse({
      'id': '9223372036854775808',
      'status': 'draft',
    }, 201),
    '201-wrong-status': (_) =>
        support.jsonResponse({'id': sales.draftId, 'status': 'confirmed'}, 201),
    '422-html': (_) => http.Response('<html>error</html>', 422),
    '422-no-errors': (_) => support.jsonResponse({'message': 'error'}, 422),
    '429': (_) => support.jsonResponse({'message': 'throttled'}, 429),
  };
  for (final entry in ambiguous.entries) {
    test(
      'UNKNOWN ${entry.key}; restore/resume/new tap never retries POST',
      () async {
        final store = fixture.MemoryDraftStore();
        var requests = 0;
        final controller = await fixture.ready((request) {
          requests++;
          return entry.value(request);
        }, store: store);
        addTearDown(controller.dispose);
        await send(controller);
        expect(controller.drafts.state, DraftState.unknownOutcome);
        await controller.drafts.restore();
        await controller.refresh();
        await send(controller);
        expect(requests, 1);
        expect(controller.drafts.canCreate, false);
      },
    );
  }

  for (final state in ['pending', 'unknown_outcome', 'known_id']) {
    test(
      'restart $state never POSTs; absent list evidence cannot unlock',
      () async {
        final store = fixture.MemoryDraftStore();
        store.values[store.key(fixture.origin, fixture.userId)] = fixture
            .attempt(state: state)
            .encode();
        var requests = 0;
        final controller = await fixture.ready((_) {
          requests++;
          return support.jsonResponse({'data': []});
        }, store: store);
        addTearDown(controller.dispose);
        await controller.drafts.restore();
        await send(controller);
        expect(requests, 0);
        expect(controller.drafts.canCreate, false);
        expect(store.values.length, 1);
      },
    );
  }

  test('corrupt marker is retained and fail-closed, never deleted', () async {
    final store = fixture.MemoryDraftStore();
    store.values[store.key(fixture.origin, fixture.userId)] = '{bad';
    var posts = 0;
    final controller = await fixture.ready((_) {
      posts++;
      return fixture.created();
    }, store: store);
    addTearDown(controller.dispose);
    await controller.drafts.restore();
    expect(controller.drafts.state, DraftState.storageBlocked);
    await send(controller);
    expect(posts, 0);
    expect(store.values.values.single, '{bad');
  });

  for (final status in [401, 403, 422]) {
    test(
      'definitive JSON rejection $status persists; no automatic resend',
      () async {
        final store = fixture.MemoryDraftStore();
        var posts = 0;
        final controller = await fixture.ready((_) {
          posts++;
          return support.jsonResponse({
            'message': 'rejected',
            'errors': {
              'items.0.quantity': ['Số lượng sai'],
            },
          }, status);
        }, store: store);
        addTearDown(controller.dispose);
        await send(controller);
        expect(jsonDecode(store.values.values.single)['state'], 'rejected');
        expect(posts, 1);
        await controller.drafts.restore();
        expect(posts, 1);
        if (status == 422) {
          expect(controller.drafts.error, isNull);
          await send(controller);
          expect(posts, 2);
        }
      },
    );
  }

  test(
    'late 201 after logout saved for original actor, not shown to another actor',
    () async {
      final store = fixture.MemoryDraftStore();
      final response = Completer<http.Response>();
      var actor = fixture.userId;
      var posts = 0;
      final controller = await fixture.ready(
        (request) {
          if (request.method == 'POST') {
            posts++;
            return response.future;
          }
          throw StateError('No detail GET while another actor selected');
        },
        store: store,
        profile: () =>
            support.profileJson()
              ..['user'] = {'id': actor, 'username': 'fixture'},
      );
      addTearDown(controller.dispose);
      final pending = send(controller);
      await Future<void>.delayed(Duration.zero);
      await controller.logout();
      expect(controller.drafts.attempt, isNull);
      actor = '2';
      (controller.store as support.MemoryStore).session = support.validSession(
        branchId: sales.branchId,
      );
      await controller.restore();
      response.complete(fixture.created());
      await pending;
      await Future<void>.delayed(Duration.zero);
      expect(posts, 1);
      expect(
        jsonDecode(
          store.values[store.key(fixture.origin, fixture.userId)]!,
        )['order_id'],
        sales.draftId,
      );
      expect(controller.drafts.attempt, isNull);
      actor = fixture.userId;
      await controller.refresh();
      await controller.drafts.restore();
      expect(controller.drafts.attempt!.orderId, sales.draftId);
    },
  );

  test(
    'another API origin cannot read marker; switching branch cannot clear it',
    () async {
      final store = fixture.MemoryDraftStore();
      store.values[store.key(fixture.origin, fixture.userId)] = fixture
          .attempt()
          .encode();
      final other = await fixture.ready(
        (_) => throw StateError('No HTTP'),
        store: store,
        baseUrl: 'https://other.example.test',
      );
      addTearDown(other.dispose);
      await other.drafts.restore();
      expect(other.drafts.attempt, isNull);
      final controller = await fixture.ready(
        (_) => throw StateError('No HTTP'),
        store: store,
      );
      addTearDown(controller.dispose);
      await controller.drafts.restore();
      controller.changeScope();
      expect(controller.drafts.attempt, isNull);
      await controller.chooseBranch(sales.branchId);
      await controller.drafts.restore();
      expect(controller.drafts.state, DraftState.unknownOutcome);
      expect(store.values.length, 1);
    },
  );

  test(
    'late transport after actual timeout does not trigger ID lookup or another POST',
    () async {
      final store = fixture.MemoryDraftStore();
      final response = Completer<http.Response>();
      var posts = 0;
      final controller = await fixture.ready(
        (_) {
          posts++;
          return response.future;
        },
        store: store,
        timeout: const Duration(milliseconds: 5),
      );
      addTearDown(controller.dispose);
      await send(controller);
      expect(controller.drafts.state, DraftState.unknownOutcome);
      response.complete(fixture.created());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await send(controller);
      expect(posts, 1);
      expect(controller.drafts.attempt!.orderId, isNull);
    },
  );

  test('expired session before send cannot issue business POST', () async {
    var posts = 0;
    final controller = await fixture.ready((_) {
      posts++;
      return fixture.created();
    }, store: fixture.MemoryDraftStore());
    addTearDown(controller.dispose);
    controller.changeScope();
    await send(controller);
    expect(posts, 0);
  });

  for (final mismatch in [
    'creator',
    'warehouse',
    'customer',
    'quantity',
    'lot',
  ]) {
    test(
      'detail $mismatch mismatch keeps ID, refuses binding and never creates again',
      () async {
        var posts = 0;
        final controller = await fixture.ready((request) {
          if (request.method == 'POST') {
            posts++;
            return fixture.created();
          }
          final json = fixture.detail();
          final data = json['data'] as Map;
          final item = (json['items'] as List).first as Map;
          switch (mismatch) {
            case 'creator':
              data['created_by'] = '2';
            case 'warehouse':
              data['warehouse_id'] = '2';
            case 'customer':
              data['customer_id'] = '2';
            case 'quantity':
              item['quantity'] = '3.000';
            case 'lot':
              item['lot_id'] = '2';
          }
          return support.jsonResponse(json);
        }, store: fixture.MemoryDraftStore());
        addTearDown(controller.dispose);
        await send(controller);
        expect(controller.drafts.detail, isNull);
        expect(controller.drafts.attempt!.orderId, sales.draftId);
        await send(controller);
        expect(posts, 1);
      },
    );
  }
}
