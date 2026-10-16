import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:klcn186_mobile/auth/auth_controller.dart';
import 'package:klcn186_mobile/transfers/request_models.dart';
import 'package:klcn186_mobile/transfers/request_submission.dart';

import 'auth_test.dart' as auth;
import 'transfer_request_fixtures.dart' as f;

void main() {
  test(
    'missing active field is corruption, never interpreted as an empty pending slot',
    () async {
      final store = f.TransferMemoryStore()
        ..raw = jsonEncode({
          'version': 1,
          'origin': f.origin,
          'user_id': f.userId,
          'journal': [],
        });
      var calls = 0;
      final controller = await f.ready((r) {
        calls++;
        return auth.jsonResponse(f.options());
      }, store: store);
      addTearDown(controller.dispose);
      await controller.transfers.open();
      expect(controller.transfers.state, TransferRequestState.storageBlocked);
      expect(calls, 0);
    },
  );
  for (final status in [401, 403, 404]) {
    test('options HTTP$status keeps typed error and cannot submit', () async {
      var calls = 0;
      final controller = await f.ready((r) {
        calls++;
        expect(r.method, 'GET');
        expect(r.url.path, '/api/stock-transfers/options');
        return auth.jsonResponse({'message': 'not available'}, status);
      }, store: f.TransferMemoryStore());
      addTearDown(controller.dispose);
      await controller.transfers.open();
      expect(controller.transfers.canCreate, false);
      expect(controller.transfers.options, isNull);
      if (status == 404) {
        expect(controller.transfers.error!.status, 404);
      } else {
        expect(
          controller.stage,
          status == 401 ? AuthStage.signedOut : AuthStage.unavailable,
        );
      }
      expect(calls, 1);
    });
  }

  test(
    'real client timeout ignores late 201 response, no automatic POST retry',
    () async {
      final response = Completer<http.Response>();
      var posts = 0;
      final store = f.TransferMemoryStore();
      final controller = await f.ready(
        (r) {
          if (r.method == 'GET') return auth.jsonResponse(f.options());
          posts++;
          return response.future;
        },
        store: store,
        timeout: const Duration(milliseconds: 10),
      );
      addTearDown(controller.dispose);
      await controller.transfers.open();
      await controller.transfers.submit(f.payload());
      expect(controller.transfers.state, TransferRequestState.unknownOutcome);
      response.complete(auth.jsonResponse({'id': f.transferId}, 201));
      await Future<void>.delayed(Duration.zero);
      await controller.transfers.open();
      expect(controller.transfers.state, TransferRequestState.unknownOutcome);
      expect(controller.transfers.attempt!.transferId, isNull);
      expect(posts, 1);
    },
  );

  test(
    'options filter source branch/chain, destination same chain, lots by warehouse',
    () {
      final options = TransferOptions.fromJson(f.options());
      final sources = options.sourcesFor(f.branchId, '1');
      expect(sources.single.id, '11');
      expect(options.destinationsFor(sources.single).single.id, '12');
      expect(options.lotsFor('11').single.quantity.toString(), '10.125');
      options.validate(f.payload(), '1');
      expect(f.payload().toJson().keys, [
        'from_warehouse_id',
        'to_warehouse_id',
        'items',
      ]);
      expect(f.payload().toJson()['items'], [
        {'lot_id': f.lotId, 'requested_quantity': '2.125'},
      ]);
    },
  );

  for (final bad in [
    '0',
    '-1',
    '1.0001',
    '1000000000000000',
    '1e3',
    'NaN',
    '1,2',
  ]) {
    test('quantity rejects $bad before POST', () {
      expect(() => f.payload(qty: bad), throwsFormatException);
    });
  }
  test(
    'quantity accepts maximum 15 integer digits and scale3 without double',
    () {
      expect(
        f.payload(qty: '999999999999999.999').lines.single.quantity.toString(),
        '999999999999999.999',
      );
      expect(f.payload(qty: '0.001').lines.single.quantity.toString(), '0.001');
    },
  );
  for (final bad in [
    'same warehouse',
    'duplicate',
    'empty',
    '51 lines',
    'numeric id',
    'foreign field',
  ]) {
    test('invalid payload: $bad', () {
      expect(() {
        final json = f.payload().toJson();
        switch (bad) {
          case 'same warehouse':
            json['to_warehouse_id'] = '11';
          case 'duplicate':
            (json['items'] as List).add((json['items'] as List).first);
          case 'empty':
            json['items'] = [];
          case '51 lines':
            json['items'] = List.generate(
              51,
              (i) => {'lot_id': '${i + 1}', 'requested_quantity': '1'},
            );
          case 'numeric id':
            json['from_warehouse_id'] = 11;
          case 'foreign field':
            json['requested_by'] = f.userId;
        }
        TransferPayload.fromJson(json, f.branchId);
      }, throwsFormatException);
    });
  }
  for (final bad in [
    'duplicate source',
    'duplicate lot',
    'numeric id',
    'double quantity',
    'precision',
    'negative',
  ]) {
    test('invalid options rejected: $bad', () {
      final json = f.options();
      switch (bad) {
        case 'duplicate source':
          (json['sources'] as List).add((json['sources'] as List).first);
        case 'duplicate lot':
          (json['lots'] as List).add((json['lots'] as List).first);
        case 'numeric id':
          (json['sources'] as List).first['id'] = 11;
        case 'double quantity':
          (json['lots'] as List).first['quantity'] = 10.125;
        case 'precision':
          (json['lots'] as List).first['quantity'] = '1.0001';
        case 'negative':
          (json['lots'] as List).first['quantity'] = '-1';
      }
      expect(
        () => TransferOptions.fromJson(json),
        throwsA(anyOf(isA<FormatException>(), isA<TypeError>())),
      );
    });
  }

  test(
    'marker read-back before exactly one Bearer POST, ID before GET, durable journal unlock',
    () async {
      final store = f.TransferMemoryStore();
      final requests = <http.Request>[];
      final controller = await f.ready((r) {
        requests.add(r);
        expect(r.headers['authorization'], 'Bearer test-token');
        expect(r.headers.containsKey('cookie'), false);
        if (r.url.path.endsWith('options')) {
          return auth.jsonResponse(f.options());
        }
        final active = jsonDecode(store.raw!)['active'];
        if (r.method == 'POST') {
          expect(active['state'], 'pending');
          expect(store.reads, greaterThanOrEqualTo(3));
          expect(jsonDecode(r.body), f.payload().toJson());
          return auth.jsonResponse({'id': f.transferId}, 201);
        }
        expect(r.url.path, '/api/stock-transfers/${f.transferId}');
        expect(active['state'], 'known_id');
        expect(active['transfer_id'], f.transferId);
        return auth.jsonResponse(f.detail());
      }, store: store);
      addTearDown(controller.dispose);
      final flow = controller.transfers;
      await flow.open();
      await Future.wait([flow.submit(f.payload()), flow.submit(f.payload())]);
      expect(flow.state, TransferRequestState.knownId);
      expect(flow.detail!.items.single.requested.toString(), '2.125');
      await flow.submit(f.payload());
      await flow.reloadDetail();
      expect(requests.where((e) => e.method == 'POST').length, 1);
      await flow.complete();
      expect(flow.canCreate, true);
      expect(flow.journal.length, 1);
      expect(jsonDecode(store.raw!)['active'], isNull);
      expect(
        jsonDecode(store.raw!)['journal'].single['attempt']['transfer_id'],
        f.transferId,
      );
    },
  );

  for (final bad in [
    'overstock',
    'wrong source',
    'wrong chain destination',
    'wrong lot',
    'wrong branch',
  ]) {
    test('pre-send validation blocks $bad', () async {
      var posts = 0;
      final store = f.TransferMemoryStore();
      final controller = await f.ready((r) {
        if (r.method == 'POST') posts++;
        return auth.jsonResponse(f.options());
      }, store: store);
      addTearDown(controller.dispose);
      await controller.transfers.open();
      final json = f.payload().toJson();
      switch (bad) {
        case 'overstock':
          (json['items'] as List).first['requested_quantity'] = '10.126';
        case 'wrong source':
          json['from_warehouse_id'] = '13';
        case 'wrong chain destination':
          json['to_warehouse_id'] = '14';
        case 'wrong lot':
          (json['items'] as List).first['lot_id'] = '777';
      }
      await controller.transfers.submit(
        TransferPayload.fromJson(
          json,
          bad == 'wrong branch' ? '2' : f.branchId,
        ),
      );
      expect(posts, 0);
      expect(store.writes, 0);
    });
  }

  for (final fault in [
    'timeout',
    'network',
    '500',
    '409',
    '429',
    '404',
    '201 numeric id',
    '200',
    '201 html',
    'malformed 422',
  ]) {
    test(
      'uncertain $fault retains UNKNOWN across restart without POST replay',
      () async {
        var posts = 0;
        final store = f.TransferMemoryStore();
        FutureOr<http.Response> handler(http.Request r) {
          if (r.method == 'GET') return auth.jsonResponse(f.options());
          posts++;
          switch (fault) {
            case 'timeout':
              throw TimeoutException('lost');
            case 'network':
              throw http.ClientException('lost');
            case '201 numeric id':
              return auth.jsonResponse({'id': 123}, 201);
            case '200':
              return auth.jsonResponse({'id': f.transferId});
            case '201 html':
              return http.Response('ok', 201);
            case 'malformed 422':
              return http.Response('invalid', 422);
            default:
              return auth.jsonResponse({'message': 'failed'}, int.parse(fault));
          }
        }

        final controller = await f.ready(handler, store: store);
        await controller.transfers.open();
        await controller.transfers.submit(f.payload());
        expect(controller.transfers.state, TransferRequestState.unknownOutcome);
        final raw = store.raw;
        await controller.transfers.complete();
        await controller.transfers.editRejected();
        await controller.transfers.open();
        await controller.transfers.submit(f.payload());
        expect(store.raw, raw);
        controller.dispose();
        final restarted = await f.ready(handler, store: store);
        addTearDown(restarted.dispose);
        await restarted.transfers.open();
        expect(restarted.transfers.state, TransferRequestState.unknownOutcome);
        expect(restarted.transfers.canCreate, false);
        expect(posts, 1);
      },
    );
  }

  test(
    'pending marker from process death becomes UNKNOWN, never send on restore',
    () async {
      final store = f.TransferMemoryStore();
      final controller = await f.ready(
        (r) => r.method == 'GET'
            ? auth.jsonResponse(f.options())
            : auth.jsonResponse({'message': 'failed'}, 500),
        store: store,
      );
      await controller.transfers.open();
      await controller.transfers.submit(f.payload());
      final envelope = jsonDecode(store.raw!);
      envelope['active']['state'] = 'pending';
      store.raw = jsonEncode(envelope);
      controller.dispose();
      var requests = 0;
      final restarted = await f.ready((r) {
        requests++;
        return auth.jsonResponse({});
      }, store: store);
      addTearDown(restarted.dispose);
      await restarted.transfers.open();
      expect(restarted.transfers.state, TransferRequestState.unknownOutcome);
      expect(requests, 0);
    },
  );

  for (final fault in [
    'initial read',
    'pending write',
    'pending readback',
    'id write',
    'id readback',
    'journal write',
    'journal readback',
  ]) {
    test(
      'storage fail-closed at $fault; no replay; recover known ID when available',
      () async {
        var posts = 0, gets = 0;
        final store = f.TransferMemoryStore();
        final controller = await f.ready((r) {
          if (r.url.path.endsWith('options')) {
            return auth.jsonResponse(f.options());
          }
          if (r.method == 'POST') {
            posts++;
            return auth.jsonResponse({'id': f.transferId}, 201);
          }
          gets++;
          return auth.jsonResponse(f.detail());
        }, store: store);
        addTearDown(controller.dispose);
        final flow = controller.transfers;
        if (fault == 'initial read') store.failReadAt = 1;
        await flow.open();
        if (fault == 'pending write') store.failWriteAt = 1;
        if (fault == 'pending readback') store.mismatchAt = store.reads + 2;
        if (fault == 'id write') store.failWriteAt = 2;
        if (fault == 'id readback') store.failReadAt = store.reads + 3;
        await flow.submit(f.payload());
        if (fault.startsWith('journal')) {
          expect(flow.canComplete, true);
          if (fault == 'journal write') {
            store.failWriteAt = store.writes + 1;
          } else {
            store.failReadAt = store.reads + 2;
          }
          await flow.complete();
        }
        expect(flow.state, TransferRequestState.storageBlocked);
        expect(flow.canCreate, false);
        await flow.submit(f.payload());
        expect(
          posts,
          fault == 'initial read' || fault.startsWith('pending') ? 0 : 1,
        );
        if (fault.startsWith('id')) {
          expect(gets, 0);
          store.failReadAt = null;
          store.failWriteAt = null;
          await flow.open();
          expect(flow.state, TransferRequestState.knownId);
          expect(flow.detail, isNotNull);
          expect(posts, 1);
        }
      },
    );
  }

  for (final status in [401, 403, 422]) {
    test(
      'valid JSON $status is definite rejection; no automatic new POST',
      () async {
        var posts = 0;
        final store = f.TransferMemoryStore();
        final controller = await f.ready((r) {
          if (r.method == 'GET') return auth.jsonResponse(f.options());
          posts++;
          return auth.jsonResponse({
            'message': 'denied',
            'errors': {
              'items.0.requested_quantity': ['Tồn đã thay đổi.'],
            },
          }, status);
        }, store: store);
        addTearDown(controller.dispose);
        await controller.transfers.open();
        await controller.transfers.submit(f.payload());
        expect(jsonDecode(store.raw!)['active']['state'], 'rejected');
        expect(posts, 1);
        if (status == 422) {
          expect(controller.transfers.state, TransferRequestState.rejected);
          await controller.transfers.editRejected();
          expect(controller.transfers.canCreate, true);
          expect(
            controller.transfers.journal.single['attempt']['state'],
            'rejected',
          );
          expect(posts, 1);
        } else {
          expect(
            controller.stage,
            status == 401 ? AuthStage.signedOut : AuthStage.unavailable,
          );
          expect(controller.transfers.attempt, isNull);
        }
      },
    );
  }

  for (final fault in [
    '404',
    'network',
    'wrong id',
    'wrong creator',
    'wrong quantity',
    'wrong warehouse',
  ]) {
    test(
      'GET $fault preserves KNOWN_ID and blocks completion without verified detail',
      () async {
        var posts = 0;
        final store = f.TransferMemoryStore();
        final controller = await f.ready((r) {
          if (r.url.path.endsWith('options')) {
            return auth.jsonResponse(f.options());
          }
          if (r.method == 'POST') {
            posts++;
            return auth.jsonResponse({'id': f.transferId}, 201);
          }
          if (fault == '404') {
            return auth.jsonResponse({'message': 'not found'}, 404);
          }
          if (fault == 'network') throw http.ClientException('lost GET');
          final json = f.detail();
          switch (fault) {
            case 'wrong id':
              json['data']['id'] = '777';
            case 'wrong creator':
              json['data']['requested_by'] = '777';
            case 'wrong quantity':
              json['items'][0]['requested_quantity'] = '2.124';
            case 'wrong warehouse':
              json['data']['to_warehouse_id'] = '777';
          }
          return auth.jsonResponse(json);
        }, store: store);
        addTearDown(controller.dispose);
        await controller.transfers.open();
        await controller.transfers.submit(f.payload());
        expect(controller.transfers.state, TransferRequestState.knownId);
        expect(controller.transfers.attempt!.transferId, f.transferId);
        expect(controller.transfers.detail, isNull);
        expect(controller.transfers.canComplete, false);
        await controller.transfers.complete();
        await controller.transfers.reloadDetail();
        expect(posts, 1);
      },
    );
  }

  test(
    'known ID restart uses exact GET; no POST; pending survives logout',
    () async {
      final store = f.TransferMemoryStore();
      var posts = 0;
      http.Response handler(http.Request r) {
        if (r.url.path.endsWith('options')) {
          return auth.jsonResponse(f.options());
        }
        if (r.url.path.endsWith('logout')) {
          return auth.jsonResponse({'message': 'ok'});
        }
        if (r.method == 'POST') {
          posts++;
          return auth.jsonResponse({'id': f.transferId}, 201);
        }
        expect(r.url.path, '/api/stock-transfers/${f.transferId}');
        return auth.jsonResponse(f.detail());
      }

      final first = await f.ready(handler, store: store);
      await first.transfers.open();
      await first.transfers.submit(f.payload());
      final raw = store.raw;
      await first.logout();
      expect(first.transfers.attempt, isNull);
      expect(store.raw, raw);
      first.dispose();
      final restarted = await f.ready(handler, store: store);
      addTearDown(restarted.dispose);
      await restarted.transfers.open();
      expect(restarted.transfers.canComplete, true);
      expect(posts, 1);
    },
  );

  test(
    'session revision changes during marker write prevent any POST',
    () async {
      final store = f.TransferMemoryStore();
      var posts = 0;
      final controller = await f.ready((r) {
        if (r.method == 'POST') posts++;
        return auth.jsonResponse(f.options());
      }, store: store);
      addTearDown(controller.dispose);
      await controller.transfers.open();
      final pending = controller.transfers.submit(f.payload());
      controller.changeScope();
      await pending;
      expect(posts, 0);
    },
  );

  test(
    'late POST saves original user ID before GET, does not leak to another user',
    () async {
      final store = f.TransferMemoryStore();
      final response = Completer<http.Response>();
      var user = f.userId, posts = 0, gets = 0;
      final controller = await f.ready(
        (r) {
          if (r.url.path.endsWith('options')) {
            return auth.jsonResponse(f.options());
          }
          if (r.method == 'POST') {
            posts++;
            return response.future;
          }
          gets++;
          return auth.jsonResponse(f.detail());
        },
        store: store,
        profile: () {
          final json = auth.profileJson();
          json['user']['id'] = user;
          return json;
        },
      );
      addTearDown(controller.dispose);
      await controller.transfers.open();
      final sent = controller.transfers.submit(f.payload());
      while (posts == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      user = '99';
      await controller.refresh();
      response.complete(auth.jsonResponse({'id': f.transferId}, 201));
      await sent;
      await controller.transfers.open();
      expect(jsonDecode(store.raw!)['active']['transfer_id'], f.transferId);
      expect(controller.transfers.attempt, isNull);
      expect(gets, 0);
      expect(controller.transfers.journal, isEmpty);
      user = f.userId;
      await controller.refresh();
      await controller.transfers.open();
      while (controller.transfers.busy) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(controller.transfers.detail, isNotNull);
      expect(posts, 1);
    },
  );

  test('old-scope options response is discarded on change/reselect', () async {
    final store = f.TransferMemoryStore();
    final response = Completer<http.Response>();
    final controller = await f.ready((r) => response.future, store: store);
    addTearDown(controller.dispose);
    final loading = controller.transfers.open();
    await Future<void>.delayed(Duration.zero);
    controller.changeScope();
    response.complete(auth.jsonResponse(f.options()));
    await loading;
    expect(controller.transfers.options, isNull);
  });

  for (final raw in [
    'broken JSON',
    '{"version":2}',
    '{"version":1,"origin":"foreign","user_id":"1"}',
  ]) {
    test('corrupt or foreign envelope locks storage', () async {
      final store = f.TransferMemoryStore()..raw = raw;
      var calls = 0;
      final controller = await f.ready((r) {
        calls++;
        return auth.jsonResponse({});
      }, store: store);
      addTearDown(controller.dispose);
      await controller.transfers.open();
      expect(controller.transfers.state, TransferRequestState.storageBlocked);
      expect(calls, 0);
      expect(store.raw, raw);
    });
  }
}
