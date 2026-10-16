import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:klcn186_mobile/transfers/reconcile_models.dart';
import 'package:klcn186_mobile/transfers/reconcile_submission.dart';

import 'auth_test.dart' as auth;
import 'transfer_reconcile_fixtures.dart' as f;

void main() {
  test(
    'selected source branch can reconcile with explicit API permission',
    () async {
      final controller = await f.ready((r) {
        final result = f.detail();
        result['data']['from_branch_id'] = f.branchId;
        result['data']['to_branch_id'] = '2';
        return auth.jsonResponse(result);
      });
      addTearDown(controller.dispose);
      await controller.transferReconciliations.open(id: f.transferId);
      expect(controller.transferReconciliations.canReconcile, isTrue);
    },
  );

  test(
    'input allocation copied before await; reason trimmed into immutable marker',
    () async {
      final held = Completer<http.Response>();
      var gets = 0;
      Map<String, dynamic>? posted;
      final controller = await f.ready((r) {
        if (r.method == 'POST') {
          posted = jsonDecode(r.body);
          return auth.jsonResponse({'status': 'reconciled'});
        }
        gets++;
        return gets == 2 ? held.future : auth.jsonResponse(f.detail());
      });
      addTearDown(controller.dispose);
      final flow = controller.transferReconciliations;
      await flow.open(id: f.transferId);
      final input = f.lines();
      final sending = flow.submit(input, '  ${f.reason}  ');
      while (gets < 2) {
        await Future<void>.delayed(Duration.zero);
      }
      input[0] = ReconcileLine(f.lotId, '0', '0', '1');
      held.complete(auth.jsonResponse(f.detail()));
      await sending;
      expect(posted!['items'], [f.lines().single.toJson()]);
      expect(posted!['reason'], f.reason);
    },
  );

  for (final amounts in [
    ['1', '0', '0'],
    ['0', '1', '0'],
    ['0', '0', '1'],
    ['0.125', '0.250', '0.625'],
  ]) {
    test(
      'allocation $amounts; exact payload, marker before POST, GET proof, durable journal',
      () async {
        final store = f.ReconcileMemoryStore();
        Map<String, dynamic>? payload;
        var posts = 0;
        final controller = await f.ready((r) {
          if (r.method == 'POST') {
            posts++;
            payload = jsonDecode(r.body) as Map<String, dynamic>;
            expect(
              r.url.path,
              '/api/stock-transfers/${f.transferId}/reconcile',
            );
            expect(r.headers['Authorization'], 'Bearer test-token');
            expect(payload!.keys.toSet(), {'reason', 'items'});
            final saved = jsonDecode(store.raw!)['active'] as Map;
            expect(saved['phase'], 'pending');
            expect(saved['reason'], f.reason);
            expect(saved['items'], payload!['items']);
            expect(store.reads, greaterThan(store.writes));
            return auth.jsonResponse({'status': 'reconciled'});
          }
          return auth.jsonResponse(
            payload == null ? f.detail() : f.outcome(payload!),
          );
        }, store: store);
        final flow = controller.transferReconciliations;
        await flow.open(id: f.transferId);
        expect(flow.canReconcile, isTrue);
        await flow.submit(
          f.lines(amounts[0], amounts[1], amounts[2]),
          '  ${f.reason}  ',
        );
        expect(flow.state, ReconcileState.verified);
        expect(posts, 1);
        expect(payload!['items'], [
          ReconcileLine(f.lotId, amounts[0], amounts[1], amounts[2]).toJson(),
        ]);
        await flow.complete();
        expect(flow.journal, hasLength(1));
        expect(flow.attempt, isNull);
        controller.dispose();
        final restored = await f.ready((r) {
          if (r.method == 'POST') posts++;
          return auth.jsonResponse(f.outcome(payload!));
        }, store: store);
        addTearDown(restored.dispose);
        await restored.transferReconciliations.open();
        expect(restored.transferReconciliations.journal, hasLength(1));
        expect(posts, 1);
      },
    );
  }

  test(
    'multi lot, zero-shortage line, reordered result preserve exact conservation',
    () async {
      Map<String, dynamic>? payload;
      Map<String, dynamic> data() {
        final result = f.detail();
        final extra = Map<String, dynamic>.from(result['items'][0]);
        extra.addAll({
          'id': '9007199254741021',
          'lot_id': '9007199254741023',
          'received_quantity': '2.125',
        });
        result['items'].add(extra);
        if (payload != null) {
          result['data'].addAll({
            'status': 'reconciled',
            'reconciled_by': f.userId,
            'reconciled_at': '2026-10-16T05:00:00Z',
            'reconciliation_reason': f.reason,
          });
          for (var i = 0; i < 2; i++) {
            result['items'][i].addAll(payload!['items'][i]);
          }
          result['items'] = (result['items'] as List).reversed.toList();
        }
        return result;
      }

      final controller = await f.ready((r) {
        if (r.method == 'POST') {
          payload = jsonDecode(r.body);
          return auth.jsonResponse({'status': 'reconciled'});
        }
        return auth.jsonResponse(data());
      });
      addTearDown(controller.dispose);
      final flow = controller.transferReconciliations;
      await flow.open(id: f.transferId);
      await flow.submit([
        ...f.lines('0.125', '0.250', '0.625'),
        ReconcileLine('9007199254741023', '0', '0', '0'),
      ], f.reason);
      expect(flow.state, ReconcileState.verified);
    },
  );

  for (final value in [
    '-1',
    '1.0001',
    '1000000000000000',
    '1e0',
    'NaN',
    '1,0',
    '',
  ]) {
    test('strict decimal $value', () {
      expect(
        () => ReconcileLine(f.lotId, value, '0', '0'),
        throwsFormatException,
      );
    });
  }
  for (final reason in ['', '  ', 'ab', ' x ', 'a' * 1001]) {
    test('invalid reason length ${reason.length}; no marker or POST', () async {
      var posts = 0;
      final store = f.ReconcileMemoryStore();
      final controller = await f.ready((r) {
        if (r.method == 'POST') posts++;
        return auth.jsonResponse(f.detail());
      }, store: store);
      addTearDown(controller.dispose);
      final flow = controller.transferReconciliations;
      await flow.open(id: f.transferId);
      await flow.submit(f.lines(), reason);
      expect(posts, 0);
      expect(store.raw, isNull);
      expect(flow.error!.status, 422);
    });
  }
  test('reason counts Unicode code points, not UTF16 code units', () {
    expect(reconcileReason(' 😀😀😀 '), '😀😀😀');
    expect(() => reconcileReason('😀😀'), throwsFormatException);
    expect(reconcileReason('😀' * 1000).runes.length, 1000);
    expect(() => reconcileReason('😀' * 1001), throwsFormatException);
  });

  for (final variant in [
    'short',
    'over',
    'negative',
    'duplicate',
    'missing',
    'extra',
    'max51',
    'wrongKeys',
    'numberId',
  ]) {
    test('invalid allocation $variant never POST', () async {
      var posts = 0;
      final store = f.ReconcileMemoryStore();
      final controller = await f.ready((r) {
        if (r.method == 'POST') posts++;
        return auth.jsonResponse(f.detail());
      }, store: store);
      addTearDown(controller.dispose);
      final flow = controller.transferReconciliations;
      await flow.open(id: f.transferId);
      if (variant == 'negative') {
        expect(() => f.lines('-1'), throwsFormatException);
        return;
      }
      if (variant == 'wrongKeys' || variant == 'numberId') {
        final row = f.lines().single.toJson();
        if (variant == 'wrongKeys') {
          row['price'] = '0';
        } else {
          row['lot_id'] = 123;
        }
        expect(() => reconcileLines([row]), throwsFormatException);
        return;
      }
      final lines = switch (variant) {
        'short' => f.lines('0.999'),
        'over' => f.lines('1.001'),
        'duplicate' => [...f.lines(), ...f.lines()],
        'missing' => <ReconcileLine>[],
        'extra' => [...f.lines(), ReconcileLine('8', '0', '0', '0')],
        'max51' => [
          for (var i = 1; i <= 51; i++) ReconcileLine('$i', '0', '0', '0'),
        ],
        _ => f.lines(),
      };
      await flow.submit(lines, f.reason);
      expect(posts, 0);
      expect(store.raw, isNull);
      expect(flow.error!.status, 422);
    });
  }

  for (final mutation in [
    'permission',
    'status',
    'received',
    'branch',
    'chain',
    'id',
    'missingFlag',
  ]) {
    test('fresh GET changed $mutation blocks before marker', () async {
      var gets = 0, posts = 0;
      final store = f.ReconcileMemoryStore();
      final controller = await f.ready((r) {
        if (r.method == 'POST') posts++;
        final result = f.detail();
        gets++;
        if (gets >= 2) {
          switch (mutation) {
            case 'permission':
              result['data']['can_reconcile'] = false;
            case 'status':
              result['data']['status'] = 'reconciled';
            case 'received':
              result['items'][0]['received_quantity'] = '1.126';
            case 'branch':
              result['data']['to_branch_id'] = '8';
              result['data']['from_branch_id'] = '9';
            case 'chain':
              result['data']['chain_id'] = '8';
            case 'id':
              result['data']['id'] = '8';
            case 'missingFlag':
              result['data'].remove('can_reconcile');
          }
        }
        return auth.jsonResponse(result);
      }, store: store);
      addTearDown(controller.dispose);
      final flow = controller.transferReconciliations;
      await flow.open(id: f.transferId);
      await flow.submit(f.lines(), f.reason);
      expect(posts, 0);
      expect(store.raw, isNull);
      expect(flow.error, isNotNull);
    });
  }

  for (final mutation in [
    'actor',
    'reason',
    'allocation',
    'missingReason',
    'blankReason',
    'missingActor',
    'missingTime',
    'badConservation',
    'extraLot',
    'missingLot',
    'receivedSnapshot',
    'receiveActor',
    'receiveTime',
    'dispatchTime',
    'status',
  ]) {
    test('GET evidence $mutation cannot falsely verify attempt', () async {
      var posted = false, posts = 0;
      final controller = await f.ready((r) {
        if (r.method == 'POST') {
          posted = true;
          posts++;
          return auth.jsonResponse({'status': 'reconciled'});
        }
        final data = f.detail(status: posted ? 'reconciled' : 'discrepancy');
        if (posted) {
          switch (mutation) {
            case 'actor':
              data['data']['reconciled_by'] = '8';
            case 'reason':
              data['data']['reconciliation_reason'] = 'Lý do khác';
            case 'allocation':
              data['items'][0]['supplemental_received_quantity'] = '0';
              data['items'][0]['lost_quantity'] = '1';
            case 'missingReason':
              data['data'].remove('reconciliation_reason');
            case 'blankReason':
              data['data']['reconciliation_reason'] = '  ';
            case 'missingActor':
              data['data'].remove('reconciled_by');
            case 'missingTime':
              data['data'].remove('reconciled_at');
            case 'badConservation':
              data['items'][0]['supplemental_received_quantity'] = '0.999';
            case 'extraLot':
              final extra = Map<String, dynamic>.from(data['items'][0]);
              extra['id'] = '8';
              extra['lot_id'] = '8';
              data['items'].add(extra);
            case 'missingLot':
              data['items'] = [];
            case 'receivedSnapshot':
              data['items'][0]['received_quantity'] = '1.126';
            case 'receiveActor':
              data['data']['received_by'] = '8';
            case 'receiveTime':
              data['data']['received_at'] = '2026-10-16T04:01:00Z';
            case 'dispatchTime':
              data['data']['dispatched_at'] = '2026-10-16T03:01:00Z';
            case 'status':
              data['data']['status'] = 'received';
          }
        }
        return auth.jsonResponse(data);
      });
      addTearDown(controller.dispose);
      final flow = controller.transferReconciliations;
      await flow.open(id: f.transferId);
      await flow.submit(f.lines(), f.reason);
      final other = {'actor', 'reason', 'allocation'}.contains(mutation);
      expect(
        flow.state,
        other ? ReconcileState.handledElsewhere : ReconcileState.unknown,
      );
      expect(flow.attempt, isNotNull);
      await flow.submit(f.lines(), f.reason);
      expect(posts, 1);
    });
  }

  for (final corruption in [
    'actor',
    'time',
    'reason',
    'allocation',
    'conservation',
    'duplicate',
  ]) {
    test('journal $corruption fails closed', () async {
      final store = f.ReconcileMemoryStore();
      var sent = false;
      final controller = await f.ready((r) {
        if (r.method == 'POST') {
          sent = true;
          return auth.jsonResponse({'status': 'reconciled'});
        }
        return auth.jsonResponse(
          f.detail(status: sent ? 'reconciled' : 'discrepancy'),
        );
      }, store: store);
      addTearDown(controller.dispose);
      final flow = controller.transferReconciliations;
      await flow.open(id: f.transferId);
      await flow.submit(f.lines(), f.reason);
      await flow.complete();
      final data = jsonDecode(store.raw!) as Map;
      final entry = data['journal'][0] as Map;
      final o = entry['observation'] as Map;
      switch (corruption) {
        case 'actor':
          o['reconciled_by'] = '8';
        case 'time':
          o.remove('reconciled_at');
        case 'reason':
          o['reconciliation_reason'] = 'Lý do khác';
        case 'allocation':
          o['items'][0]['supplemental_received_quantity'] = '0';
          o['items'][0]['lost_quantity'] = '1';
        case 'conservation':
          o['items'][0]['supplemental_received_quantity'] = '1.001';
        case 'duplicate':
          data['journal'].add(entry);
      }
      store.raw = jsonEncode(data);
      await flow.open();
      expect(flow.state, ReconcileState.storageBlocked);
    });
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
      final flow = controller.transferReconciliations;
      await flow.open(id: f.transferId);
      final first = flow.submit(f.lines(), f.reason);
      while (posts == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      await flow.submit(f.lines(), f.reason);
      await flow.open(id: '3');
      await flow.reload();
      held.complete(auth.jsonResponse({'status': 'reconciled'}));
      await first;
      expect(posts, 1);
      expect(flow.state, ReconcileState.unknown);
      expect(flow.canComplete, isFalse);
    },
  );

  for (final code in [401, 403, 404, 409, 422, 429, 500, 503]) {
    test(
      'POST $code then GET requested: no replay or assumed success',
      () async {
        var posts = 0;
        final store = f.ReconcileMemoryStore();
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
        final flow = controller.transferReconciliations;
        await flow.open(id: f.transferId);
        await flow.submit(f.lines(), f.reason);
        final saved = jsonDecode(store.raw!) as Map;
        expect(
          (saved['active'] as Map)['phase'],
          {401, 403, 422}.contains(code) ? 'denied' : 'unknown',
        );
        await flow.reload();
        await flow.submit(f.lines(), f.reason);
        expect(posts, 1);
        expect(flow.state, isNot(ReconcileState.verified));
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
        final store = f.ReconcileMemoryStore();
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
                return auth.jsonResponse({'status': 'reconciled'});
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
                return auth.jsonResponse({'status': 'reconciled'}, 201);
            }
          },
          store: store,
          timeout: const Duration(milliseconds: 10),
        );
        await controller.transferReconciliations.open(id: f.transferId);
        await controller.transferReconciliations.submit(f.lines(), f.reason);
        expect((jsonDecode(store.raw!)['active'] as Map)['phase'], 'unknown');
        controller.dispose();
        final restored = await f.ready((r) {
          if (r.method == 'POST') posts++;
          return auth.jsonResponse(f.detail());
        }, store: store);
        addTearDown(restored.dispose);
        await restored.transferReconciliations.open(id: f.transferId);
        await restored.transferReconciliations.reload();
        await restored.transferReconciliations.submit(f.lines(), f.reason);
        await restored.transferReconciliations.complete();
        expect(posts, 1);
        expect(restored.transferReconciliations.state, ReconcileState.unknown);
        expect(restored.transferReconciliations.journal, isEmpty);
      },
    );
  }

  test(
    'lost POST response resolves using GET actor/time/unchanged snapshot; reconcile proof survives reload',
    () async {
      var status = 'discrepancy', posts = 0;
      final controller = await f.ready((r) {
        if (r.method == 'POST') {
          posts++;
          status = 'reconciled';
          throw http.ClientException('lost');
        }
        return auth.jsonResponse(f.detail(status: status));
      });
      addTearDown(controller.dispose);
      final flow = controller.transferReconciliations;
      await flow.open(id: f.transferId);
      await flow.submit(f.lines(), f.reason);
      expect(flow.state, ReconcileState.verified);
      expect(flow.detail!.detail.transfer.status, 'reconciled');
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
      final store = f.ReconcileMemoryStore();
      var posts = 0, status = 'discrepancy';
      final controller = await f.ready((r) {
        if (r.method == 'POST') {
          posts++;
          status = 'reconciled';
          return auth.jsonResponse({'status': 'reconciled'});
        }
        return auth.jsonResponse(f.detail(status: status));
      }, store: store);
      addTearDown(controller.dispose);
      final flow = controller.transferReconciliations;
      if (point == 'read') store.failReadAt = 1;
      await flow.open(id: f.transferId);
      if (point == 'write') store.failWriteAt = 1;
      if (point == 'readback') store.mismatchAt = store.reads + 3;
      if (point == 'outcomeWrite') store.failWriteAt = 2;
      if (point == 'outcomeReadback') store.mismatchAt = store.reads + 4;
      await flow.submit(f.lines(), f.reason);
      if (point == 'journalWrite') store.failWriteAt = store.writes + 2;
      if (point == 'journalReadback') store.mismatchAt = store.reads + 3;
      if (point.startsWith('journal')) await flow.complete();
      expect(flow.state, ReconcileState.storageBlocked);
      expect(flow.canReconcile, isFalse);
      await flow.submit(f.lines(), f.reason);
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
      final store = f.ReconcileMemoryStore();
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
      await controller.transferReconciliations.open(id: f.transferId);
      await controller.transferReconciliations.submit(f.lines(), f.reason);
      expect(
        controller.transferReconciliations.state,
        ReconcileState.storageBlocked,
      );
      expect(posts, 0);
    });
  }

  test(
    'GET unavailable after POST retains marker ID; restart and GET recovery verify',
    () async {
      final store = f.ReconcileMemoryStore();
      var posted = false, offline = true, posts = 0;
      final controller = await f.ready((r) {
        if (r.method == 'POST') {
          posted = true;
          posts++;
          return auth.jsonResponse({'status': 'reconciled'});
        }
        if (posted && offline) {
          return auth.jsonResponse({'message': 'not found'}, 404);
        }
        return auth.jsonResponse(
          f.detail(status: posted ? 'reconciled' : 'discrepancy'),
        );
      }, store: store);
      await controller.transferReconciliations.open(id: f.transferId);
      await controller.transferReconciliations.submit(f.lines(), f.reason);
      expect(controller.transferReconciliations.state, ReconcileState.unknown);
      expect(controller.transferReconciliations.attempt!.id, f.transferId);
      controller.dispose();
      offline = false;
      final restored = await f.ready((r) {
        if (r.method == 'POST') posts++;
        return auth.jsonResponse(f.detail(status: 'reconciled'));
      }, store: store);
      addTearDown(restored.dispose);
      await restored.transferReconciliations.open();
      expect(restored.transferReconciliations.state, ReconcileState.verified);
      expect(posts, 1);
    },
  );

  test(
    'late POST after logout/new user writes only original namespace; restart original user preserves pending',
    () async {
      final store = f.ReconcileMemoryStore(), held = Completer<http.Response>();
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
      final flow = controller.transferReconciliations;
      await flow.open(id: f.transferId);
      final sending = flow.submit(f.lines(), f.reason);
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
      held.complete(auth.jsonResponse({'status': 'reconciled'}));
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
      expect(flow.state, ReconcileState.unknown);
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
      final flow = controller.transferReconciliations;
      await flow.open(id: f.transferId);
      final send = flow.submit(f.lines(), f.reason);
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
      final store = f.ReconcileMemoryStore();
      final controller = await f.ready(
        (r) => auth.jsonResponse(f.detail()),
        store: store,
      );
      await controller.transferReconciliations.open(id: f.transferId);
      final d = controller.transferReconciliations.detail!;
      store.raw = jsonEncode({
        'version': 1,
        'origin': f.origin,
        'user_id': f.userId,
        'active': ReconcileAttempt(
          attemptId: 'a' * 32,
          id: f.transferId,
          branchId: f.branchId,
          lines: f.lines(),
          reason: f.reason,
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
      await restored.transferReconciliations.open(id: '3');
      await restored.transferReconciliations.submit(f.lines(), f.reason);
      await restored.transferReconciliations.complete();
      expect(restored.transferReconciliations.attempt!.id, f.transferId);
      expect(restored.transferReconciliations.state, ReconcileState.unknown);
      expect(posts, 0);
    },
  );

  test(
    'storage recovery preserves unsaved outcome, never sends twice; journal read-back failure recovers one entry',
    () async {
      final store = f.ReconcileMemoryStore();
      var posts = 0, status = 'discrepancy';
      final controller = await f.ready((r) {
        if (r.method == 'POST') {
          posts++;
          status = 'reconciled';
          return auth.jsonResponse({'status': status});
        }
        return auth.jsonResponse(f.detail(status: status));
      }, store: store);
      addTearDown(controller.dispose);
      final flow = controller.transferReconciliations;
      await flow.open(id: f.transferId);
      store.failWriteAt = 2;
      await flow.submit(f.lines(), f.reason);
      expect(flow.state, ReconcileState.storageBlocked);
      store.failWriteAt = null;
      await flow.open();
      expect(flow.state, ReconcileState.verified);
      store.mismatchAt = store.reads + 3;
      await flow.complete();
      expect(flow.state, ReconcileState.storageBlocked);
      store.mismatchAt = null;
      await flow.open();
      expect(flow.attempt, isNull);
      expect(flow.journal, hasLength(1));
      expect(flow.journal.single['observation']['reconciled_by'], f.userId);
      expect(posts, 1);
      (flow.journal.single['observation'] as Map)['reconciled_by'] =
          'tampered-copy';
      expect(flow.journal.single['observation']['reconciled_by'], f.userId);
    },
  );

  test(
    'GET404/permission errors at preflight are read-only; no marker or mock mutation',
    () async {
      var gets = 0, mutations = 0;
      final store = f.ReconcileMemoryStore();
      final controller = await f.ready((r) {
        if (r.method == 'POST') mutations++;
        gets++;
        return gets == 1
            ? auth.jsonResponse(f.detail())
            : auth.jsonResponse({'message': 'gone'}, 404);
      }, store: store);
      addTearDown(controller.dispose);
      await controller.transferReconciliations.open(id: f.transferId);
      await controller.transferReconciliations.submit(f.lines(), f.reason);
      expect(mutations, 0);
      expect(store.raw, isNull);
      expect(controller.transferReconciliations.error!.status, 404);
    },
  );
}
