import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:klcn186_mobile/transfers/dispatch_models.dart';
import 'package:klcn186_mobile/transfers/dispatch_submission.dart';

import 'auth_test.dart' as auth;
import 'transfer_dispatch_fixtures.dart' as f;

void main() {
  for (final statusAfter in ['received', 'discrepancy', 'reconciled']) {
    test(
      'GET $statusAfter retains original dispatch actor/time/quantity evidence',
      () async {
        var sent = false;
        final controller = await f.ready((r) {
          if (r.method == 'POST') {
            sent = true;
            return auth.jsonResponse({'status': 'dispatched'});
          }
          return auth.jsonResponse(
            f.detail(status: sent ? statusAfter : 'approved'),
          );
        });
        addTearDown(controller.dispose);
        await controller.transferDispatches.open(id: f.transferId);
        await controller.transferDispatches.submit(f.lines());
        expect(controller.transferDispatches.state, DispatchState.verified);
      },
    );
  }

  test(
    'payload is immutable across preflight await; source caller cannot alter amount later',
    () async {
      var gets = 0;
      final held = Completer<http.Response>();
      final posted = <Map>[];
      final controller = await f.ready((r) {
        if (r.method == 'POST') {
          posted.add(jsonDecode(r.body) as Map);
          return auth.jsonResponse({'status': 'dispatched'});
        }
        gets++;
        return gets == 2 ? held.future : auth.jsonResponse(f.detail());
      });
      addTearDown(controller.dispose);
      final flow = controller.transferDispatches;
      await flow.open(id: f.transferId);
      final lines = f.lines('1');
      final sending = flow.submit(lines);
      while (gets < 2) {
        await Future<void>.delayed(Duration.zero);
      }
      lines[0] = DispatchLine(f.lotId, '999');
      held.complete(auth.jsonResponse(f.detail()));
      await sending;
      expect(posted.single['items'][0]['dispatched_quantity'], '1.000');
    },
  );

  test(
    'multiple lots exact set and reordered GET items keep dispatch fingerprint',
    () async {
      var sent = false, posts = 0;
      final controller = await f.ready(
        (r) {
          if (r.method == 'POST') {
            sent = true;
            posts++;
            return auth.jsonResponse({'status': 'dispatched'});
          }
          final data = f.detail(status: sent ? 'dispatched' : 'approved');
          final second = Map<String, dynamic>.from(data['items'][0] as Map);
          second.addAll({
            'id': '9007199254741021',
            'lot_id': '9007199254741023',
          });
          data['items'].add(second);
          if (sent) data['items'] = (data['items'] as List).reversed.toList();
          return auth.jsonResponse(data);
        },
        optionsHandler: (r) {
          final data = f.options();
          final extra = Map<String, dynamic>.from(data['lots'][0] as Map)
            ..['lot_id'] = '9007199254741023';
          data['lots'].add(extra);
          return auth.jsonResponse(data);
        },
      );
      addTearDown(controller.dispose);
      final flow = controller.transferDispatches;
      await flow.open(id: f.transferId);
      await flow.submit([
        ...f.lines(),
        DispatchLine('9007199254741023', '2.125'),
      ]);
      expect(posts, 1);
      expect(flow.state, DispatchState.verified);
    },
  );

  for (final corruption in ['actor', 'time', 'quantity', 'duplicate']) {
    test('corrupt journal $corruption remains fail-closed', () async {
      final store = f.DispatchMemoryStore();
      var sent = false;
      final controller = await f.ready((r) {
        if (r.method == 'POST') {
          sent = true;
          return auth.jsonResponse({'status': 'dispatched'});
        }
        return auth.jsonResponse(
          f.detail(status: sent ? 'dispatched' : 'approved'),
        );
      }, store: store);
      addTearDown(controller.dispose);
      final flow = controller.transferDispatches;
      await flow.open(id: f.transferId);
      await flow.submit(f.lines());
      await flow.complete();
      final data = jsonDecode(store.raw!) as Map;
      final entry = data['journal'][0] as Map,
          observation = data['journal'][0]['observation'] as Map;
      if (corruption == 'actor') observation['dispatched_by'] = '8';
      if (corruption == 'time') observation.remove('dispatched_at');
      if (corruption == 'quantity') {
        observation['items'][0]['dispatched_quantity'] = '1.000';
      }
      if (corruption == 'duplicate') data['journal'].add(entry);
      store.raw = jsonEncode(data);
      await flow.open();
      expect(flow.state, DispatchState.storageBlocked);
      expect(flow.canDispatch, isFalse);
    });
  }
  test(
    'exact payload; marker read-back precedes POST; GET evidence and durable journal',
    () async {
      final store = f.DispatchMemoryStore();
      var status = 'approved', posts = 0, optionReads = 0;
      final controller = await f.ready(
        (r) {
          if (r.method == 'POST') {
            posts++;
            expect(r.url.path, '/api/stock-transfers/${f.transferId}/dispatch');
            expect(r.headers['Authorization'], 'Bearer test-token');
            expect(jsonDecode(r.body), {
              'items': [
                {'lot_id': f.lotId, 'dispatched_quantity': '1.250'},
              ],
            });
            final marker = jsonDecode(store.raw!)['active'] as Map;
            expect(marker['phase'], 'pending');
            expect(marker['items'], jsonDecode(r.body)['items']);
            expect(store.reads, greaterThan(store.writes));
            status = 'dispatched';
            return auth.jsonResponse({'status': status});
          }
          return auth.jsonResponse(f.detail(status: status, quantity: '1.250'));
        },
        store: store,
        optionsHandler: (r) {
          optionReads++;
          return auth.jsonResponse(f.options());
        },
      );
      addTearDown(controller.dispose);
      final flow = controller.transferDispatches;
      await flow.open(id: f.transferId);
      expect(flow.canDispatch, isTrue);
      await flow.submit(f.lines('1.250'));
      expect(posts, 1);
      expect(optionReads, 2);
      expect(flow.state, DispatchState.verified);
      await flow.complete();
      expect(flow.journal, hasLength(1));
      expect(flow.journal.single['observation']['dispatched_by'], f.userId);
      expect(
        flow
            .journal
            .single['observation']['items']
            .single['dispatched_quantity'],
        '1.250',
      );
      expect(jsonDecode(store.raw!)['active'], isNull);
    },
  );

  for (final value in [
    '0',
    '-1',
    '1.0001',
    '1000000000000000',
    '1e2',
    '1,25',
    '',
    'NaN',
  ]) {
    test('reject invalid scale/precision/quantity $value', () {
      expect(() => DispatchLine(f.lotId, value), throwsFormatException);
    });
  }
  test(
    'max NUMERIC(18,3) and BIGINT stay exact; sets must match each lot once',
    () {
      expect(
        DispatchLine(
          '9223372036854775807',
          '999999999999999.999',
        ).quantity.toString(),
        '999999999999999.999',
      );
      expect(
        () => DispatchLine('9223372036854775808', '1'),
        throwsFormatException,
      );
      final detail = DispatchDetail.fromJson(f.detail());
      expect(() => detail.validate([]), throwsFormatException);
      expect(
        () => detail.validate([...f.lines(), ...f.lines()]),
        throwsFormatException,
      );
      expect(
        () => detail.validate([DispatchLine('9', '1')]),
        throwsFormatException,
      );
      expect(() => detail.validate(f.lines('2.126')), throwsFormatException);
      detail.validate(f.lines('0.001'));
    },
  );

  for (final variant in [
    'noPermission',
    'changedPermission',
    'changedItems',
    'changedStatus',
    'destinationOnly',
    'otherBranch',
    'otherChain',
    'numberId',
    'missingFlag',
  ]) {
    test('preflight $variant never POST', () async {
      var gets = 0, posts = 0;
      final controller = await f.ready((r) {
        if (r.method == 'POST') posts++;
        gets++;
        final data = f.detail(
          permission:
              variant != 'noPermission' &&
              !(variant == 'changedPermission' && gets > 1),
          status: variant == 'changedStatus' && gets > 1
              ? 'dispatched'
              : 'approved',
        );
        final row = data['data'] as Map;
        if (variant == 'changedItems' && gets > 1) {
          data['items'][0]['requested_quantity'] = '3.000';
        }
        if (variant == 'destinationOnly') {
          row['from_branch_id'] = '2';
          row['to_branch_id'] = f.branchId;
        }
        if (variant == 'otherBranch') {
          row['from_branch_id'] = '8';
          row['to_branch_id'] = '9';
        }
        if (variant == 'otherChain') row['chain_id'] = '8';
        if (variant == 'numberId') row['id'] = 9007199254741011;
        if (variant == 'missingFlag') row.remove('can_dispatch');
        return auth.jsonResponse(data);
      });
      addTearDown(controller.dispose);
      await controller.transferDispatches.open(id: f.transferId);
      await controller.transferDispatches.submit(f.lines());
      expect(posts, 0);
    });
  }

  for (final variant in [
    'lowInitially',
    'stockChanged',
    'optionsOffline',
    'foreignSource',
    'unlistedLot',
  ]) {
    test(
      'fresh options $variant; missing stock is unknown snapshot, not invented zero',
      () async {
        var reads = 0, posts = 0;
        final controller = await f.ready(
          (r) {
            if (r.method == 'POST') {
              posts++;
              return auth.jsonResponse({'status': 'dispatched'});
            }
            return auth.jsonResponse(f.detail());
          },
          optionsHandler: (r) {
            reads++;
            if (variant == 'optionsOffline') {
              throw http.ClientException('offline');
            }
            final options = f.options();
            if (variant == 'lowInitially' ||
                variant == 'stockChanged' && reads > 1) {
              options['lots'][0]['quantity'] = '1.000';
            }
            if (variant == 'foreignSource') {
              options['sources'][0]['chain_id'] = '8';
            }
            if (variant == 'unlistedLot') options['lots'] = [];
            return auth.jsonResponse(options);
          },
        );
        addTearDown(controller.dispose);
        await controller.transferDispatches.open(id: f.transferId);
        await controller.transferDispatches.submit(f.lines());
        expect(posts, variant == 'unlistedLot' ? 1 : 0);
      },
    );
  }

  for (final variant in [
    'otherActor',
    'differentQuantity',
    'missingActor',
    'missingTime',
    'differentItems',
  ]) {
    test(
      'GET evidence $variant never assumes current attempt succeeded',
      () async {
        var sent = false;
        final controller = await f.ready((r) {
          if (r.method == 'POST') {
            sent = true;
            return auth.jsonResponse({'status': 'dispatched'});
          }
          final data = f.detail(status: sent ? 'dispatched' : 'approved');
          if (sent) {
            final row = data['data'] as Map;
            if (variant == 'otherActor') row['dispatched_by'] = '8';
            if (variant == 'missingActor') row['dispatched_by'] = null;
            if (variant == 'missingTime') row['dispatched_at'] = null;
            if (variant == 'differentQuantity') {
              data['items'][0]['dispatched_quantity'] = '1.000';
            }
            if (variant == 'differentItems') data['items'][0]['lot_id'] = '8';
          }
          return auth.jsonResponse(data);
        });
        addTearDown(controller.dispose);
        final flow = controller.transferDispatches;
        await flow.open(id: f.transferId);
        await flow.submit(f.lines());
        expect(flow.state, isNot(DispatchState.verified));
        if ({'otherActor', 'differentQuantity'}.contains(variant)) {
          expect(flow.state, DispatchState.handledElsewhere);
        } else {
          expect(flow.canComplete, isFalse);
        }
      },
    );
  }
  test(
    'double tap shared coordinator produces one POST; busy refresh cannot overwrite target',
    () async {
      final held = Completer<http.Response>();
      var posts = 0;
      final controller = await f.ready((r) {
        if (r.method == 'POST') {
          posts++;
          return held.future;
        }
        return auth.jsonResponse(f.detail());
      });
      addTearDown(controller.dispose);
      final flow = controller.transferDispatches;
      await flow.open(id: f.transferId);
      final first = flow.submit(f.lines());
      while (posts == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      await flow.submit(f.lines());
      await flow.open(id: '3');
      await flow.reload();
      held.complete(auth.jsonResponse({'status': 'dispatched'}));
      await first;
      expect(posts, 1);
      expect(flow.state, DispatchState.unknown);
      expect(flow.canComplete, isFalse);
    },
  );

  for (final code in [401, 403, 404, 409, 422, 429, 500, 503]) {
    test(
      'POST $code then GET requested: no replay or assumed success',
      () async {
        var posts = 0;
        final store = f.DispatchMemoryStore();
        final controller = await f.ready((r) {
          if (r.method == 'POST') {
            posts++;
            return auth.jsonResponse({
              'message': 'Fixture rejection',
              if (code == 422)
                'errors': {
                  'reason': ['Fixture invalid'],
                },
            }, code);
          }
          return auth.jsonResponse(f.detail());
        }, store: store);
        addTearDown(controller.dispose);
        final flow = controller.transferDispatches;
        await flow.open(id: f.transferId);
        await flow.submit(f.lines());
        final saved = jsonDecode(store.raw!) as Map;
        expect(
          (saved['active'] as Map)['phase'],
          {401, 403, 422}.contains(code) ? 'denied' : 'unknown',
        );
        await flow.reload();
        await flow.submit(f.lines());
        expect(posts, 1);
        expect(flow.state, isNot(DispatchState.verified));
      },
    );
  }

  for (final error in [
    'network',
    'timeout',
    'html403',
    'bad200',
    'wrongStatus',
    'wrongCode',
  ]) {
    test(
      'uncertain $error retained across process restart; GET only',
      () async {
        final store = f.DispatchMemoryStore();
        var posts = 0;
        final controller = await f.ready(
          (r) async {
            if (r.method != 'POST') return auth.jsonResponse(f.detail());
            posts++;
            switch (error) {
              case 'network':
                throw http.ClientException('fixture offline');
              case 'timeout':
                await Future<void>.delayed(const Duration(milliseconds: 20));
                return auth.jsonResponse({'status': 'dispatched'});
              case 'html403':
                return http.Response('<html>denied</html>', 403);
              case 'bad200':
                return http.Response(
                  'bad',
                  200,
                  headers: {'content-type': 'application/json'},
                );
              case 'wrongStatus':
                return auth.jsonResponse({'status': 'rejected'});
              default:
                return auth.jsonResponse({'status': 'dispatched'}, 201);
            }
          },
          store: store,
          timeout: const Duration(milliseconds: 10),
        );
        await controller.transferDispatches.open(id: f.transferId);
        await controller.transferDispatches.submit(f.lines());
        expect((jsonDecode(store.raw!)['active'] as Map)['phase'], 'unknown');
        controller.dispose();
        final restored = await f.ready((r) {
          if (r.method == 'POST') posts++;
          return auth.jsonResponse(f.detail());
        }, store: store);
        addTearDown(restored.dispose);
        await restored.transferDispatches.open(id: f.transferId);
        await restored.transferDispatches.reload();
        await restored.transferDispatches.submit(f.lines());
        await restored.transferDispatches.complete();
        expect(posts, 1);
        expect(restored.transferDispatches.state, DispatchState.unknown);
        expect(restored.transferDispatches.journal, isEmpty);
      },
    );
  }

  test(
    'lost POST response resolves using GET actor/time/unchanged snapshot; later dispatch keeps approval proof',
    () async {
      var status = 'approved', posts = 0;
      final controller = await f.ready((r) {
        if (r.method == 'POST') {
          posts++;
          status = 'dispatched';
          throw http.ClientException('lost');
        }
        return auth.jsonResponse(f.detail(status: status));
      });
      addTearDown(controller.dispose);
      final flow = controller.transferDispatches;
      await flow.open(id: f.transferId);
      await flow.submit(f.lines());
      expect(flow.state, DispatchState.verified);
      expect(flow.detail!.detail.transfer.status, 'dispatched');
      await flow.reload();
      expect(posts, 1);
    },
  );

  for (final point in [
    'read',
    'write',
    'readback',
    'outcomeWrite',
    'outcomeReadback',
    'journalWrite',
    'journalReadback',
  ]) {
    test('storage $point fails closed without extra POST', () async {
      final store = f.DispatchMemoryStore();
      var posts = 0, status = 'approved';
      final controller = await f.ready((r) {
        if (r.method == 'POST') {
          posts++;
          status = 'dispatched';
          return auth.jsonResponse({'status': 'dispatched'});
        }
        return auth.jsonResponse(f.detail(status: status));
      }, store: store);
      addTearDown(controller.dispose);
      final flow = controller.transferDispatches;
      if (point == 'read') store.failReadAt = 1;
      await flow.open(id: f.transferId);
      if (point == 'write') store.failWriteAt = 1;
      if (point == 'readback') store.mismatchAt = store.reads + 3;
      if (point == 'outcomeWrite') store.failWriteAt = 2;
      if (point == 'outcomeReadback') store.mismatchAt = store.reads + 4;
      await flow.submit(f.lines());
      if (point == 'journalWrite') store.failWriteAt = store.writes + 2;
      if (point == 'journalReadback') store.mismatchAt = store.reads + 3;
      if (point.startsWith('journal')) await flow.complete();
      expect(flow.state, DispatchState.storageBlocked);
      expect(flow.canDispatch, isFalse);
      await flow.submit(f.lines());
      expect(posts, {'read', 'write', 'readback'}.contains(point) ? 0 : 1);
    });
  }

  for (final corrupt in [
    'badJson',
    'foreignUser',
    'foreignOrigin',
    'version',
    'missingActive',
    'badPhase',
    'numberId',
  ]) {
    test('corrupt $corrupt blocks send', () async {
      final store = f.DispatchMemoryStore();
      var posts = 0;
      final data = <String, dynamic>{
        'version': 1,
        'origin': f.origin,
        'user_id': f.userId,
        'active': null,
        'journal': [],
      };
      switch (corrupt) {
        case 'foreignUser':
          data['user_id'] = '8';
        case 'foreignOrigin':
          data['origin'] = 'https://elsewhere.test';
        case 'version':
          data['version'] = 2;
        case 'missingActive':
          data.remove('active');
        case 'badPhase':
        case 'numberId':
          data['active'] = {'phase': 'oops', 'transfer_id': 12};
      }
      store.raw = corrupt == 'badJson' ? '{' : jsonEncode(data);
      final controller = await f.ready((r) {
        if (r.method == 'POST') posts++;
        return auth.jsonResponse(f.detail());
      }, store: store);
      addTearDown(controller.dispose);
      await controller.transferDispatches.open(id: f.transferId);
      await controller.transferDispatches.submit(f.lines());
      expect(controller.transferDispatches.state, DispatchState.storageBlocked);
      expect(posts, 0);
    });
  }

  test(
    'GET unavailable after POST retains marker ID; restart and GET recovery verify',
    () async {
      final store = f.DispatchMemoryStore();
      var posted = false, offline = true, posts = 0;
      final controller = await f.ready((r) {
        if (r.method == 'POST') {
          posted = true;
          posts++;
          return auth.jsonResponse({'status': 'dispatched'});
        }
        if (posted && offline) {
          return auth.jsonResponse({'message': 'not found'}, 404);
        }
        return auth.jsonResponse(
          f.detail(status: posted ? 'dispatched' : 'approved'),
        );
      }, store: store);
      await controller.transferDispatches.open(id: f.transferId);
      await controller.transferDispatches.submit(f.lines());
      expect(controller.transferDispatches.state, DispatchState.unknown);
      expect(controller.transferDispatches.attempt!.id, f.transferId);
      controller.dispose();
      offline = false;
      final restored = await f.ready((r) {
        if (r.method == 'POST') posts++;
        return auth.jsonResponse(f.detail(status: 'dispatched'));
      }, store: store);
      addTearDown(restored.dispose);
      await restored.transferDispatches.open();
      expect(restored.transferDispatches.state, DispatchState.verified);
      expect(posts, 1);
    },
  );

  test(
    'late POST after logout/new user writes only original namespace; restart original user preserves pending',
    () async {
      final store = f.DispatchMemoryStore(), held = Completer<http.Response>();
      var currentUser = f.userId, posts = 0;
      final controller = await f.ready(
        (r) {
          if (r.url.path.endsWith('/logout')) {
            return auth.jsonResponse({'message': 'ok'});
          }
          if (r.method == 'POST') {
            posts++;
            return held.future;
          }
          return auth.jsonResponse(f.detail());
        },
        store: store,
        profile: () {
          final data = auth.profileJson();
          (data['user'] as Map)['id'] = currentUser;
          return data;
        },
      );
      addTearDown(controller.dispose);
      final flow = controller.transferDispatches;
      await flow.open(id: f.transferId);
      final sending = flow.submit(f.lines());
      while (posts == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      await controller.logout();
      expect(flow.attempt, isNull);
      currentUser = '8';
      (controller.store as auth.MemoryStore).session = auth.validSession(
        branchId: f.branchId,
      );
      await controller.restore();
      held.complete(auth.jsonResponse({'status': 'dispatched'}));
      await sending;
      while (flow.busy) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(flow.visible, isTrue);
      expect(flow.attempt, isNull);
      expect(flow.journal, isEmpty);
      expect((jsonDecode(store.raw!)['active'] as Map)['phase'], 'unknown');
      currentUser = f.userId;
      await controller.restore();
      while (flow.busy) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(flow.attempt!.id, f.transferId);
      expect(flow.state, DispatchState.unknown);
      expect(posts, 1);
    },
  );

  test(
    'scope changes during preflight never POST; stale detail is hidden',
    () async {
      final held = Completer<http.Response>();
      var gets = 0, posts = 0;
      final controller = await f.ready((r) {
        if (r.method == 'POST') posts++;
        gets++;
        return gets == 2 ? held.future : auth.jsonResponse(f.detail());
      });
      addTearDown(controller.dispose);
      final flow = controller.transferDispatches;
      await flow.open(id: f.transferId);
      final send = flow.submit(f.lines());
      while (gets < 2) {
        await Future<void>.delayed(Duration.zero);
      }
      controller.changeScope();
      held.complete(auth.jsonResponse(f.detail()));
      await send;
      expect(posts, 0);
      expect(flow.detail, isNull);
      expect(flow.attempt, isNull);
    },
  );

  test(
    'process death after pending marker remains UNKNOWN without any POST or forced clear',
    () async {
      final store = f.DispatchMemoryStore();
      final controller = await f.ready(
        (r) => auth.jsonResponse(f.detail()),
        store: store,
      );
      await controller.transferDispatches.open(id: f.transferId);
      final d = controller.transferDispatches.detail!;
      store.raw = jsonEncode({
        'version': 1,
        'origin': f.origin,
        'user_id': f.userId,
        'active': DispatchAttempt(
          attemptId: 'a' * 32,
          id: f.transferId,
          branchId: f.branchId,
          lines: f.lines(),
          fingerprint: d.fingerprint,
          createdAt: DateTime.now().toUtc().toIso8601String(),
          phase: 'pending',
        ).toJson(),
        'journal': [],
      });
      controller.dispose();
      var posts = 0;
      final restored = await f.ready((r) {
        if (r.method == 'POST') posts++;
        return auth.jsonResponse(f.detail());
      }, store: store);
      addTearDown(restored.dispose);
      await restored.transferDispatches.open(id: '3');
      await restored.transferDispatches.submit(f.lines());
      await restored.transferDispatches.complete();
      expect(restored.transferDispatches.attempt!.id, f.transferId);
      expect(restored.transferDispatches.state, DispatchState.unknown);
      expect(posts, 0);
    },
  );

  test(
    'storage recovery preserves unsaved outcome, never sends twice; journal read-back failure recovers one entry',
    () async {
      final store = f.DispatchMemoryStore();
      var posts = 0, status = 'approved';
      final controller = await f.ready((r) {
        if (r.method == 'POST') {
          posts++;
          status = 'dispatched';
          return auth.jsonResponse({'status': status});
        }
        return auth.jsonResponse(f.detail(status: status));
      }, store: store);
      addTearDown(controller.dispose);
      final flow = controller.transferDispatches;
      await flow.open(id: f.transferId);
      store.failWriteAt = 2;
      await flow.submit(f.lines());
      expect(flow.state, DispatchState.storageBlocked);
      store.failWriteAt = null;
      await flow.open();
      expect(flow.state, DispatchState.verified);
      store.mismatchAt = store.reads + 3;
      await flow.complete();
      expect(flow.state, DispatchState.storageBlocked);
      store.mismatchAt = null;
      await flow.open();
      expect(flow.attempt, isNull);
      expect(flow.journal, hasLength(1));
      expect(flow.journal.single['observation']['dispatched_by'], f.userId);
      expect(posts, 1);
      (flow.journal.single['observation'] as Map)['dispatched_by'] =
          'tampered-copy';
      expect(flow.journal.single['observation']['dispatched_by'], f.userId);
    },
  );

  test(
    'GET404/permission errors at preflight are read-only; no marker or mock mutation',
    () async {
      var gets = 0, mutations = 0;
      final store = f.DispatchMemoryStore();
      final controller = await f.ready((r) {
        if (r.method == 'POST') mutations++;
        gets++;
        return gets == 1
            ? auth.jsonResponse(f.detail())
            : auth.jsonResponse({'message': 'gone'}, 404);
      }, store: store);
      addTearDown(controller.dispose);
      await controller.transferDispatches.open(id: f.transferId);
      await controller.transferDispatches.submit(f.lines());
      expect(mutations, 0);
      expect(store.raw, isNull);
      expect(controller.transferDispatches.error!.status, 404);
    },
  );
}
