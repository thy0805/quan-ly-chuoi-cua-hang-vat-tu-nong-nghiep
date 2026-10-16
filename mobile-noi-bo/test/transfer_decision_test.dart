import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:klcn186_mobile/transfers/decision_models.dart';
import 'package:klcn186_mobile/transfers/decision_submission.dart';

import 'auth_test.dart' as auth;
import 'transfer_decision_fixtures.dart' as f;

void main() {
  for (final action in TransferAction.values) {
    test(
      '${action.name}: durable marker before POST; exact path/payload; GET proof; journal',
      () async {
        final store = f.DecisionMemoryStore(), calls = <http.Request>[];
        var status = 'requested';
        final controller = await f.ready((r) {
          calls.add(r);
          if (r.method == 'POST') {
            final marker = (jsonDecode(store.raw!) as Map)['active'] as Map;
            expect(marker['phase'], 'pending');
            expect(marker['transfer_id'], f.transferId);
            expect(store.reads, greaterThan(store.writes));
            expect(r.headers['Authorization'], 'Bearer test-token');
            expect(
              r.url.path,
              '/api/stock-transfers/${f.transferId}/${action.name}',
            );
            expect(
              jsonDecode(r.body),
              action == TransferAction.approve
                  ? {}
                  : {'reason': 'Không phù hợp'},
            );
            status = action == TransferAction.approve ? 'approved' : 'rejected';
            return auth.jsonResponse({'status': status});
          }
          return auth.jsonResponse(
            f.detail(
              status: status,
              reason: action == TransferAction.reject && status == 'rejected'
                  ? 'Không phù hợp'
                  : null,
            ),
          );
        }, store: store);
        addTearDown(controller.dispose);
        final flow = controller.transferDecisions;
        await flow.open(id: f.transferId);
        expect(flow.canDecide(action), isTrue);
        await flow.submit(
          action,
          reason: action == TransferAction.reject ? ' Không phù hợp ' : null,
        );
        expect(calls.where((r) => r.method == 'POST'), hasLength(1));
        expect(flow.state, DecisionState.verified);
        expect(flow.canComplete, isTrue);
        await flow.complete();
        expect(flow.journal, hasLength(1));
        expect((jsonDecode(store.raw!) as Map)['active'], isNull);
        expect(flow.state, DecisionState.ready);
        expect(calls.every((r) => r.url.path.contains(f.transferId)), isTrue);
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
      final flow = controller.transferDecisions;
      await flow.open(id: f.transferId);
      final first = flow.submit(TransferAction.approve);
      while (posts == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      await flow.submit(TransferAction.reject);
      await flow.open(id: '3');
      await flow.reload();
      held.complete(auth.jsonResponse({'status': 'approved'}));
      await first;
      expect(posts, 1);
      expect(flow.state, DecisionState.unknown);
      expect(flow.canComplete, isFalse);
    },
  );

  for (final code in [401, 403, 404, 409, 422, 429, 500, 503]) {
    test(
      'POST $code then GET requested: no replay or assumed success',
      () async {
        var posts = 0;
        final store = f.DecisionMemoryStore();
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
        final flow = controller.transferDecisions;
        await flow.open(id: f.transferId);
        await flow.submit(TransferAction.approve);
        final saved = jsonDecode(store.raw!) as Map;
        expect(
          (saved['active'] as Map)['phase'],
          {401, 403, 422}.contains(code) ? 'denied' : 'unknown',
        );
        await flow.reload();
        await flow.submit(TransferAction.approve);
        expect(posts, 1);
        expect(flow.state, isNot(DecisionState.verified));
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
        final store = f.DecisionMemoryStore();
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
                return auth.jsonResponse({'status': 'approved'});
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
                return auth.jsonResponse({'status': 'approved'}, 201);
            }
          },
          store: store,
          timeout: const Duration(milliseconds: 10),
        );
        await controller.transferDecisions.open(id: f.transferId);
        await controller.transferDecisions.submit(TransferAction.approve);
        expect((jsonDecode(store.raw!)['active'] as Map)['phase'], 'unknown');
        controller.dispose();
        final restored = await f.ready((r) {
          if (r.method == 'POST') posts++;
          return auth.jsonResponse(f.detail());
        }, store: store);
        addTearDown(restored.dispose);
        await restored.transferDecisions.open(id: f.transferId);
        await restored.transferDecisions.reload();
        await restored.transferDecisions.submit(TransferAction.approve);
        await restored.transferDecisions.complete();
        expect(posts, 1);
        expect(restored.transferDecisions.state, DecisionState.unknown);
        expect(restored.transferDecisions.journal, isEmpty);
      },
    );
  }

  test(
    'lost POST response resolves using GET actor/time/unchanged snapshot; later dispatch keeps approval proof',
    () async {
      var status = 'requested', posts = 0;
      final controller = await f.ready((r) {
        if (r.method == 'POST') {
          posts++;
          status = 'dispatched';
          throw http.ClientException('lost');
        }
        return auth.jsonResponse(f.detail(status: status));
      });
      addTearDown(controller.dispose);
      final flow = controller.transferDecisions;
      await flow.open(id: f.transferId);
      await flow.submit(TransferAction.approve);
      expect(flow.state, DecisionState.verified);
      expect(flow.detail!.detail.transfer.status, 'dispatched');
      await flow.reload();
      expect(posts, 1);
    },
  );

  for (final variant in [
    'otherActor',
    'opposite',
    'missingActor',
    'missingTime',
    'differentReason',
    'differentItems',
  ]) {
    test('GET evidence $variant is not claimed as action success', () async {
      var sent = false;
      final controller = await f.ready((r) {
        if (r.method == 'POST') {
          sent = true;
          return auth.jsonResponse({'status': 'rejected'});
        }
        final data = f.detail(
          status: sent ? 'rejected' : 'requested',
          reason: sent ? 'A' : null,
        );
        if (sent) {
          final row = data['data'] as Map<String, dynamic>;
          switch (variant) {
            case 'otherActor':
              row['rejected_by'] = '8';
            case 'opposite':
              return auth.jsonResponse(f.detail(status: 'approved'));
            case 'missingActor':
              row['rejected_by'] = null;
            case 'missingTime':
              row['rejected_at'] = null;
            case 'differentReason':
              row['rejection_reason'] = 'B';
            case 'differentItems':
              (data['items'] as List).first['requested_quantity'] = '3.000';
          }
        }
        return auth.jsonResponse(data);
      });
      addTearDown(controller.dispose);
      final flow = controller.transferDecisions;
      await flow.open(id: f.transferId);
      await flow.submit(TransferAction.reject, reason: 'A');
      expect(flow.state, isNot(DecisionState.verified));
      if ({'otherActor', 'opposite', 'differentReason'}.contains(variant)) {
        expect(flow.state, DecisionState.handledElsewhere);
      } else {
        expect(flow.canComplete, isFalse);
      }
    });
  }

  for (final variant in [
    'self',
    'noPermission',
    'changedPermission',
    'changedItems',
    'changedStatus',
    'otherBranch',
    'badId',
    'missingFlags',
  ]) {
    test('preflight $variant blocks POST', () async {
      var gets = 0, posts = 0;
      final controller = await f.ready((r) {
        if (r.method == 'POST') posts++;
        gets++;
        final data = f.detail(
          creator: variant == 'self' ? f.userId : '7',
          permission:
              variant != 'noPermission' &&
              !(variant == 'changedPermission' && gets > 1),
          status: variant == 'changedStatus' && gets > 1
              ? 'approved'
              : 'requested',
        );
        final row = data['data'] as Map<String, dynamic>;
        if (variant == 'changedItems' && gets > 1) {
          (data['items'] as List).first['requested_quantity'] = '3.000';
        }
        if (variant == 'otherBranch') {
          row['from_branch_id'] = '8';
          row['to_branch_id'] = '9';
        }
        if (variant == 'badId') row['id'] = 9007199254741011;
        if (variant == 'missingFlags') row.remove('can_approve');
        return auth.jsonResponse(data);
      });
      addTearDown(controller.dispose);
      await controller.transferDecisions.open(id: f.transferId);
      await controller.transferDecisions.submit(TransferAction.approve);
      expect(posts, 0);
    });
  }

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
      final store = f.DecisionMemoryStore();
      var posts = 0, status = 'requested';
      final controller = await f.ready((r) {
        if (r.method == 'POST') {
          posts++;
          status = 'approved';
          return auth.jsonResponse({'status': 'approved'});
        }
        return auth.jsonResponse(f.detail(status: status));
      }, store: store);
      addTearDown(controller.dispose);
      final flow = controller.transferDecisions;
      if (point == 'read') store.failReadAt = 1;
      await flow.open(id: f.transferId);
      if (point == 'write') store.failWriteAt = 1;
      if (point == 'readback') store.mismatchAt = store.reads + 3;
      if (point == 'outcomeWrite') store.failWriteAt = 2;
      if (point == 'outcomeReadback') store.mismatchAt = store.reads + 4;
      await flow.submit(TransferAction.approve);
      if (point == 'journalWrite') store.failWriteAt = store.writes + 2;
      if (point == 'journalReadback') store.mismatchAt = store.reads + 3;
      if (point.startsWith('journal')) await flow.complete();
      expect(flow.state, DecisionState.storageBlocked);
      expect(flow.canDecide(TransferAction.approve), isFalse);
      await flow.submit(TransferAction.approve);
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
      final store = f.DecisionMemoryStore();
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
      await controller.transferDecisions.open(id: f.transferId);
      await controller.transferDecisions.submit(TransferAction.approve);
      expect(controller.transferDecisions.state, DecisionState.storageBlocked);
      expect(posts, 0);
    });
  }

  test(
    'GET unavailable after POST retains marker ID; restart and GET recovery verify',
    () async {
      final store = f.DecisionMemoryStore();
      var posted = false, offline = true, posts = 0;
      final controller = await f.ready((r) {
        if (r.method == 'POST') {
          posted = true;
          posts++;
          return auth.jsonResponse({'status': 'approved'});
        }
        if (posted && offline) {
          return auth.jsonResponse({'message': 'not found'}, 404);
        }
        return auth.jsonResponse(
          f.detail(status: posted ? 'approved' : 'requested'),
        );
      }, store: store);
      await controller.transferDecisions.open(id: f.transferId);
      await controller.transferDecisions.submit(TransferAction.approve);
      expect(controller.transferDecisions.state, DecisionState.unknown);
      expect(controller.transferDecisions.attempt!.id, f.transferId);
      controller.dispose();
      offline = false;
      final restored = await f.ready((r) {
        if (r.method == 'POST') posts++;
        return auth.jsonResponse(f.detail(status: 'approved'));
      }, store: store);
      addTearDown(restored.dispose);
      await restored.transferDecisions.open();
      expect(restored.transferDecisions.state, DecisionState.verified);
      expect(posts, 1);
    },
  );

  test(
    'late POST after logout/new user writes only original namespace; restart original user preserves pending',
    () async {
      final store = f.DecisionMemoryStore(), held = Completer<http.Response>();
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
      final flow = controller.transferDecisions;
      await flow.open(id: f.transferId);
      final sending = flow.submit(TransferAction.approve);
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
      held.complete(auth.jsonResponse({'status': 'approved'}));
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
      expect(flow.state, DecisionState.unknown);
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
      final flow = controller.transferDecisions;
      await flow.open(id: f.transferId);
      final send = flow.submit(TransferAction.approve);
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
      final store = f.DecisionMemoryStore();
      final controller = await f.ready(
        (r) => auth.jsonResponse(f.detail()),
        store: store,
      );
      await controller.transferDecisions.open(id: f.transferId);
      final d = controller.transferDecisions.detail!;
      store.raw = jsonEncode({
        'version': 1,
        'origin': f.origin,
        'user_id': f.userId,
        'active': DecisionAttempt(
          attemptId: 'a' * 32,
          id: f.transferId,
          branchId: f.branchId,
          action: TransferAction.approve,
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
      await restored.transferDecisions.open(id: '3');
      await restored.transferDecisions.submit(TransferAction.reject);
      await restored.transferDecisions.complete();
      expect(restored.transferDecisions.attempt!.id, f.transferId);
      expect(restored.transferDecisions.state, DecisionState.unknown);
      expect(posts, 0);
    },
  );

  test(
    'storage recovery preserves unsaved outcome, never sends twice; journal read-back failure recovers one entry',
    () async {
      final store = f.DecisionMemoryStore();
      var posts = 0, status = 'requested';
      final controller = await f.ready((r) {
        if (r.method == 'POST') {
          posts++;
          status = 'approved';
          return auth.jsonResponse({'status': status});
        }
        return auth.jsonResponse(f.detail(status: status));
      }, store: store);
      addTearDown(controller.dispose);
      final flow = controller.transferDecisions;
      await flow.open(id: f.transferId);
      store.failWriteAt = 2;
      await flow.submit(TransferAction.approve);
      expect(flow.state, DecisionState.storageBlocked);
      store.failWriteAt = null;
      await flow.open();
      expect(flow.state, DecisionState.verified);
      store.mismatchAt = store.reads + 3;
      await flow.complete();
      expect(flow.state, DecisionState.storageBlocked);
      store.mismatchAt = null;
      await flow.open();
      expect(flow.attempt, isNull);
      expect(flow.journal, hasLength(1));
      expect(flow.journal.single['observation']['approved_by'], f.userId);
      expect(posts, 1);
      (flow.journal.single['observation'] as Map)['approved_by'] =
          'tampered-copy';
      expect(flow.journal.single['observation']['approved_by'], f.userId);
    },
  );

  test(
    'GET404/permission errors at preflight are read-only; no marker or mock mutation',
    () async {
      var gets = 0, mutations = 0;
      final store = f.DecisionMemoryStore();
      final controller = await f.ready((r) {
        if (r.method == 'POST') mutations++;
        gets++;
        return gets == 1
            ? auth.jsonResponse(f.detail())
            : auth.jsonResponse({'message': 'gone'}, 404);
      }, store: store);
      addTearDown(controller.dispose);
      await controller.transferDecisions.open(id: f.transferId);
      await controller.transferDecisions.submit(TransferAction.approve);
      expect(mutations, 0);
      expect(store.raw, isNull);
      expect(controller.transferDecisions.error!.status, 404);
    },
  );

  test(
    'reason nullable/max1000 Unicode scalars and no unsupported action path',
    () async {
      final controller = await f.ready((r) => auth.jsonResponse(f.detail()));
      addTearDown(controller.dispose);
      await controller.transferDecisions.open(id: f.transferId);
      await controller.transferDecisions.submit(
        TransferAction.reject,
        reason: List.filled(1001, '🌱').join(),
      );
      expect(controller.transferDecisions.error!.status, 422);
      expect(controller.transferDecisions.attempt, isNull);
      expect(
        () => controller.api.decideTransfer(
          auth.validSession(),
          f.transferId,
          'dispatch',
        ),
        throwsArgumentError,
      );
    },
  );
}
