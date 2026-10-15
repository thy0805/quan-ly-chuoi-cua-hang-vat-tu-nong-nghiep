import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:klcn186_mobile/sales/confirmation.dart';
import 'package:klcn186_mobile/sales/draft_submission.dart';
import 'package:klcn186_mobile/sales/models.dart';
import 'package:klcn186_mobile/sales/sale_envelope.dart';
import 'auth_test.dart' as auth;
import 'draft_fixtures.dart' as draft;
import 'confirm_fixtures.dart' as fixture;
import 'sales_fixtures.dart' as sales;

void main() {
  for (final amount in ['-1', '1.001', '1e3', 'NaN', '10000000000000000']) {
    test('initial payment rejects decimal $amount', () {
      expect(
        () => InitialPayment(amount: amount, method: 'cash'),
        throwsFormatException,
      );
    });
  }
  for (final method in ['qr', 'card', 'Cash']) {
    test(
      'method $method is forbidden',
      () => expect(
        () => InitialPayment(amount: '1', method: method),
        throwsFormatException,
      ),
    );
  }
  test('positive needs method, zero permits none, note bounded, whitelist', () {
    expect(() => InitialPayment(amount: '1'), throwsFormatException);
    expect(InitialPayment(amount: '0').toJson(), {'amount': '0.00'});
    expect(
      () => InitialPayment(amount: '0', note: 'a' * 201),
      throwsFormatException,
    );
    expect(
      () => InitialPayment.fromJson({'amount': '0', 'request_key': 'fake'}),
      throwsFormatException,
    );
  });
  for (final amount in ['189000.00', '100000.00', '0.00']) {
    test(
      'customer collection $amount persists before exact POST and GET invoice; complete journal opens next attempt',
      () async {
        final store = fixture.store(customer: true);
        var sold = false;
        var posts = 0;
        final controller = await fixture.ready(store, (request) {
          if (request.method == 'POST') {
            posts++;
            final saved = fixture.envelope(store);
            expect(saved.active!.orderId, sales.draftId);
            expect(saved.confirmation!.state, 'pending');
            expect(
              request.url.path,
              '/api/sales-orders/${sales.draftId}/confirm',
            );
            expect(request.headers['Authorization'], 'Bearer test-token');
            expect(request.followRedirects, false);
            expect(
              jsonDecode(request.body),
              InitialPayment(
                amount: amount,
                method: amount == '0.00' ? null : 'cash',
              ).toJson(),
            );
            sold = true;
            return fixture.confirmed();
          }
          return auth.jsonResponse(
            fixture.detail(confirmed: sold, customer: true, paid: amount),
          );
        });
        addTearDown(controller.dispose);
        await controller.drafts.confirm(
          InitialPayment(
            amount: amount,
            method: amount == '0.00' ? null : 'cash',
          ),
        );
        expect(posts, 1);
        expect(controller.drafts.canComplete, true);
        expect(controller.drafts.canConfirm, false);
        expect(
          controller.drafts.detail!.remaining!.toString(),
          amount == '189000.00'
              ? '0.00'
              : amount == '100000.00'
              ? '89000.00'
              : '189000.00',
        );
        await controller.drafts.confirm(
          InitialPayment(amount: amount, method: 'cash'),
        );
        expect(posts, 1);
        await controller.drafts.complete();
        expect(controller.drafts.canCreate, true);
        expect(controller.drafts.completedCount, 1);
        final saved = fixture.envelope(store);
        expect(saved.active, null);
        expect(saved.journal.single['invoice_id'], '9007199254741003');
        expect(saved.journal.single['order_id'], sales.draftId);
        expect(store.values.length, 1);
        expect(store.values.values.single, isNot(contains('test-token')));
        final restarted = await draft.ready(
          (_) => throw StateError('No automatic HTTP'),
          store: store,
        );
        addTearDown(restarted.dispose);
        await restarted.drafts.restore();
        expect(restarted.drafts.canCreate, true);
        expect(restarted.drafts.completedCount, 1);
      },
    );
  }
  for (final amount in ['0.00', '100000.00', '189000.01']) {
    test(
      'guest refuses underpayment/overpayment $amount without POST',
      () async {
        var posts = 0;
        final controller = await fixture.ready(fixture.store(), (request) {
          if (request.method == 'POST') posts++;
          return auth.jsonResponse(fixture.detail());
        });
        addTearDown(controller.dispose);
        await controller.drafts.confirm(
          InitialPayment(amount: amount, method: 'cash'),
        );
        expect(posts, 0);
        expect(controller.drafts.canConfirm, true);
      },
    );
  }
  test('guest full bank_transfer sends manual note and completes', () async {
    var sold = false;
    final store = fixture.store();
    final controller = await fixture.ready(store, (request) {
      if (request.method == 'POST') {
        expect(jsonDecode(request.body), {
          'amount': '189000.00',
          'method': 'bank_transfer',
          'reference_note': 'TX001',
        });
        sold = true;
        return fixture.confirmed();
      }
      return auth.jsonResponse(fixture.detail(confirmed: sold));
    });
    addTearDown(controller.dispose);
    await controller.drafts.confirm(
      InitialPayment(
        amount: '189000',
        method: 'bank_transfer',
        note: ' TX001 ',
      ),
    );
    expect(controller.drafts.canComplete, true);
  });
  for (final state in ['pending', 'known_id', 'unknown_outcome', 'rejected']) {
    test(
      'lazy v1 to v2 preserves $state exactly including ID and fingerprint',
      () async {
        final store = draft.MemoryDraftStore();
        final original = draft.attempt(state: state);
        store.values['${draft.origin}|${draft.userId}'] = original.encode();
        var calls = 0;
        final controller = await draft.ready((_) {
          calls++;
          return fixture.confirmed();
        }, store: store);
        addTearDown(controller.dispose);
        await controller.drafts.migrateStorage();
        expect(calls, 0);
        expect(fixture.envelope(store).active!.encode(), original.encode());
        await controller.drafts.restore();
        expect(controller.drafts.canCreate, state == 'rejected');
        expect(controller.drafts.attempt!.orderId, original.orderId);
      },
    );
  }
  for (final failure in ['write', 'silent', 'read', 'corrupt']) {
    test(
      'migration $failure blocks, preserves original and sends nothing',
      () async {
        final store = fixture.store();
        final original = store.values.values.single;
        if (failure == 'write') store.failWrite = 1;
        if (failure == 'silent') store.dropWrites = true;
        if (failure == 'read') store.failRead = true;
        if (failure == 'corrupt') {
          store.values[store.values.keys.single] = '{bad';
        }
        var calls = 0;
        final controller = await draft.ready((_) {
          calls++;
          return fixture.confirmed();
        }, store: store);
        addTearDown(controller.dispose);
        await controller.drafts.migrateStorage();
        expect(controller.drafts.state, DraftState.storageBlocked);
        expect(controller.drafts.canCreate, false);
        expect(calls, 0);
        if (failure != 'corrupt') expect(store.values.values.single, original);
      },
    );
  }
  for (final problem in [
    'tax',
    'net',
    'duplicate',
    'creator',
    'branch',
    'warehouse',
    'quantity',
  ]) {
    test('detail $problem prevents confirmation without POST', () async {
      final value = fixture.detail();
      final data = value['data'] as Json;
      final item = (value['items'] as List).first as Json;
      switch (problem) {
        case 'tax':
          item['tax_amount'] = null;
        case 'net':
          item['line_total'] = '1.00';
        case 'duplicate':
          (value['items'] as List).add({...item});
        case 'creator':
          data['created_by'] = '7';
        case 'branch':
          data['branch_id'] = '7';
        case 'warehouse':
          data['warehouse_id'] = '7';
        case 'quantity':
          item['quantity'] = '3.000';
      }
      var posts = 0;
      final controller = await fixture.ready(fixture.store(), (request) {
        if (request.method == 'POST') posts++;
        return auth.jsonResponse(value);
      });
      addTearDown(controller.dispose);
      await controller.drafts.confirm(
        InitialPayment(amount: '189000', method: 'cash'),
      );
      expect(controller.drafts.canConfirm, false);
      expect(posts, 0);
    });
  }
  for (final response in [
    'timeout',
    'network',
    '500',
    '302',
    '201',
    'bad',
    'wrong-id',
    'wrong-status',
    'html200',
    '422html',
  ]) {
    test(
      'ambiguous confirm $response retains ID through restart; draft GET never unlocks',
      () async {
        final store = fixture.store();
        var posts = 0;
        FutureOr<http.Response> handler(http.Request request) {
          if (request.method != 'POST') {
            return auth.jsonResponse(fixture.detail());
          }
          posts++;
          return switch (response) {
            'timeout' => Future<http.Response>.delayed(
              const Duration(milliseconds: 30),
              fixture.confirmed,
            ),
            'network' => throw const SocketException('offline'),
            '500' => auth.jsonResponse({'message': 'error'}, 500),
            '302' => http.Response('', 302),
            '201' => auth.jsonResponse({
              'id': sales.draftId,
              'status': 'confirmed',
            }, 201),
            'bad' => http.Response(
              '{bad',
              200,
              headers: {'content-type': 'application/json'},
            ),
            'wrong-id' => auth.jsonResponse({'id': '3', 'status': 'confirmed'}),
            'wrong-status' => auth.jsonResponse({
              'id': sales.draftId,
              'status': 'draft',
            }),
            'html200' => http.Response(
              '{}',
              200,
              headers: {'content-type': 'text/html'},
            ),
            _ => http.Response(
              'failure',
              422,
              headers: {'content-type': 'text/html'},
            ),
          };
        }

        final controller = await fixture.ready(
          store,
          handler,
          timeout: const Duration(milliseconds: 10),
        );
        await controller.drafts.confirm(
          InitialPayment(amount: '189000', method: 'cash'),
        );
        expect(fixture.envelope(store).confirmation!.state, 'unknown');
        expect(fixture.envelope(store).active!.orderId, sales.draftId);
        expect(controller.drafts.canConfirm, false);
        await controller.drafts.reloadDetail();
        await controller.drafts.complete();
        expect(controller.drafts.canCreate, false);
        controller.dispose();
        final restarted = await fixture.ready(store, handler);
        addTearDown(restarted.dispose);
        await restarted.drafts.confirm(
          InitialPayment(amount: '189000', method: 'cash'),
        );
        expect(posts, 1);
        expect(restarted.drafts.confirmUncertain, true);
        expect(restarted.drafts.canCreate, false);
      },
    );
  }
  for (final status in [401, 403, 422]) {
    test(
      'verified JSON $status rejection keeps ID; no automatic POST',
      () async {
        final store = fixture.store();
        var posts = 0;
        final controller = await fixture.ready(store, (request) {
          if (request.method != 'POST') {
            return auth.jsonResponse(fixture.detail());
          }
          posts++;
          return auth.jsonResponse({
            'message': 'Rejected',
            if (status == 422)
              'errors': {
                'amount': ['invalid'],
              },
          }, status);
        });
        addTearDown(controller.dispose);
        await controller.drafts.confirm(
          InitialPayment(amount: '189000', method: 'cash'),
        );
        expect(fixture.envelope(store).confirmation!.state, 'rejected');
        expect(fixture.envelope(store).active!.orderId, sales.draftId);
        expect(posts, 1);
        if (status == 422) {
          expect(controller.drafts.canConfirm, true);
          await controller.drafts.confirm(
            InitialPayment(amount: '189000', method: 'cash'),
          );
          expect(posts, 2);
          expect(fixture.envelope(store).confirmHistory.length, 1);
        }
      },
    );
  }
  for (final sold in [true, false]) {
    test('409 performs GET only; confirmed=$sold', () async {
      final store = fixture.store();
      var posted = false;
      var posts = 0;
      final controller = await fixture.ready(store, (request) {
        if (request.method == 'POST') {
          posted = true;
          posts++;
          return auth.jsonResponse({'message': 'Conflict'}, 409);
        }
        return auth.jsonResponse(fixture.detail(confirmed: posted && sold));
      });
      addTearDown(controller.dispose);
      await controller.drafts.confirm(
        InitialPayment(amount: '189000', method: 'cash'),
      );
      expect(controller.drafts.canComplete, sold);
      expect(controller.drafts.canConfirm, false);
      expect(posts, 1);
    });
  }
  test('double tap, restore, complete and create share lock', () async {
    final store = fixture.store();
    var posts = 0;
    final held = Completer<http.Response>();
    final controller = await fixture.ready(store, (request) {
      if (request.method == 'POST') {
        posts++;
        return held.future;
      }
      return auth.jsonResponse(fixture.detail());
    });
    addTearDown(controller.dispose);
    final payment = InitialPayment(amount: '189000', method: 'cash');
    final first = controller.drafts.confirm(payment);
    await Future<void>.delayed(Duration.zero);
    await controller.drafts.confirm(payment);
    await controller.drafts.restore();
    await controller.drafts.complete();
    await controller.drafts.submit(
      draft.payload(),
      origin: draft.origin,
      userId: draft.userId,
    );
    expect(posts, 1);
    held.complete(fixture.confirmed());
    await first;
    expect(posts, 1);
    expect(controller.drafts.canConfirm, false);
  });
  for (final failure in ['write', 'silent', 'read']) {
    test('pre-confirm storage $failure yields 0POST', () async {
      final store = fixture.store();
      var posts = 0;
      final controller = await fixture.ready(store, (request) {
        if (request.method == 'POST') posts++;
        return auth.jsonResponse(fixture.detail());
      });
      addTearDown(controller.dispose);
      if (failure == 'write') store.failWrite = store.writes + 1;
      if (failure == 'silent') store.dropWrites = true;
      if (failure == 'read') store.failRead = true;
      await controller.drafts.confirm(
        InitialPayment(amount: '189000', method: 'cash'),
      );
      expect(posts, 0);
      expect(controller.drafts.state, DraftState.storageBlocked);
      expect(controller.drafts.canCreate, false);
    });
  }
  for (final failure in ['write', 'silent', 'read-back']) {
    test(
      'journal $failure failclosed, retry storage never sends POST',
      () async {
        final store = fixture.store();
        var posts = 0;
        final controller = await fixture.ready(store, (request) {
          if (request.method == 'POST') posts++;
          return auth.jsonResponse(fixture.detail(confirmed: true));
        });
        addTearDown(controller.dispose);
        if (failure == 'write') store.failWrite = store.writes + 1;
        if (failure == 'silent') store.dropWrites = true;
        if (failure == 'read-back') {
          store.beforeRead = () async {
            if (store.writes > 0) store.failRead = true;
          };
        }
        await controller.drafts.complete();
        expect(controller.drafts.state, DraftState.storageBlocked);
        expect(controller.drafts.canCreate, false);
        store.failWrite = null;
        store.dropWrites = false;
        store.failRead = false;
        store.beforeRead = null;
        await controller.drafts.restore();
        expect(controller.drafts.canCreate, true);
        expect(controller.drafts.completedCount, 1);
        expect(posts, 0);
      },
    );
  }
  for (final field in [
    'invoice_id',
    'subtotal',
    'paid_amount',
    'remaining_amount',
    'issued_at',
    'cost_total',
    'total_amount',
  ]) {
    test('invalid invoice $field cannot complete', () async {
      final value = fixture.detail(confirmed: true);
      if (field == 'cost_total') {
        (value['items'] as List).first[field] = null;
      } else {
        (value['data'] as Json)[field] = field == 'total_amount'
            ? '1.00'
            : null;
      }
      final controller = await fixture.ready(
        fixture.store(),
        (_) => auth.jsonResponse(value),
      );
      addTearDown(controller.dispose);
      expect(controller.drafts.canComplete, false);
      await controller.drafts.complete();
      expect(controller.drafts.canCreate, false);
    });
  }
  test(
    'acknowledgement write failure keeps pending; restart only GET resolves',
    () async {
      final store = fixture.store();
      var sold = false;
      var posts = 0;
      final controller = await fixture.ready(store, (request) {
        if (request.method == 'POST') {
          posts++;
          sold = true;
          store.failWrite = store.writes + 1;
          return fixture.confirmed();
        }
        return auth.jsonResponse(fixture.detail(confirmed: sold));
      });
      await controller.drafts.confirm(
        InitialPayment(amount: '189000', method: 'cash'),
      );
      expect(controller.drafts.state, DraftState.storageBlocked);
      expect(fixture.envelope(store).confirmation!.state, 'pending');
      controller.dispose();
      store.failWrite = null;
      final restarted = await fixture.ready(
        store,
        (_) => auth.jsonResponse(fixture.detail(confirmed: true)),
      );
      addTearDown(restarted.dispose);
      expect(restarted.drafts.canComplete, true);
      expect(posts, 1);
    },
  );
  test('local zero total valid; tax rounding per line fixed-scale', () {
    final value = fixture.detail();
    final item = (value['items'] as List).first as Json;
    item.addAll({
      'discount_amount': '200000.00',
      'line_total': '0.00',
      'tax_amount': '0.00',
    });
    InitialPayment(amount: '0').validate(SalesOrderDetail.fromJson(value));
    expect(
      verifiedSaleTotal(SalesOrderDetail.fromJson(value)).toString(),
      '0.00',
    );
  });
  test(
    'late confirm response after logout saved for original account only',
    () async {
      final store = fixture.store();
      final held = Completer<http.Response>();
      final controller = await fixture.ready(
        store,
        (request) => request.method == 'POST'
            ? held.future
            : auth.jsonResponse(fixture.detail()),
      );
      addTearDown(controller.dispose);
      final pending = controller.drafts.confirm(
        InitialPayment(amount: '189000', method: 'cash'),
      );
      await Future<void>.delayed(Duration.zero);
      await controller.logout();
      held.complete(fixture.confirmed());
      await pending;
      expect(controller.drafts.detail, null);
      expect(controller.drafts.confirmation, null);
      expect(fixture.envelope(store).confirmation!.state, 'acknowledged');
      expect(store.values.keys.single, '${draft.origin}|${draft.userId}');
    },
  );
  test('scope change during confirm blocks result display and retry', () async {
    final store = fixture.store();
    final held = Completer<http.Response>();
    var posts = 0;
    final controller = await fixture.ready(store, (request) {
      if (request.method == 'POST') {
        posts++;
        return held.future;
      }
      return auth.jsonResponse(fixture.detail());
    });
    addTearDown(controller.dispose);
    final pending = controller.drafts.confirm(
      InitialPayment(amount: '189000', method: 'cash'),
    );
    await Future<void>.delayed(Duration.zero);
    controller.changeScope();
    held.complete(fixture.confirmed());
    await pending;
    expect(controller.drafts.detail, null);
    expect(controller.drafts.canConfirm, false);
    await controller.chooseBranch(sales.branchId);
    await controller.drafts.restore();
    await controller.drafts.reloadDetail();
    await controller.drafts.confirm(
      InitialPayment(amount: '189000', method: 'cash'),
    );
    expect(posts, 1);
  });
  test('another account sees no pending or journal from original', () async {
    final store = fixture.store();
    await store.write(
      draft.origin,
      draft.userId,
      SaleEnvelope(
        origin: draft.origin,
        userId: draft.userId,
        active: fixture.active(),
        confirmation: ConfirmAttempt(
          id: 'c' * 32,
          orderId: sales.draftId,
          payment: InitialPayment(amount: '189000', method: 'cash'),
          createdAt: '2026-10-14T00:00:00Z',
          state: 'pending',
        ),
      ).encode(),
    );
    final profile = auth.profileJson();
    (profile['user'] as Json)['id'] = '7';
    final controller = await draft.ready(
      (_) => throw StateError('No transport'),
      store: store,
      profile: () => profile,
    );
    addTearDown(controller.dispose);
    await controller.drafts.restore();
    expect(controller.drafts.attempt, null);
    expect(controller.drafts.confirmation, null);
    expect(controller.drafts.completedCount, 0);
    expect(fixture.envelope(store).confirmation!.state, 'pending');
  });
  test(
    'restart from confirm_pending preserves ID and only GET, 404 cannot complete',
    () async {
      final store = fixture.store();
      store.values[store.values.keys.single] = SaleEnvelope(
        origin: draft.origin,
        userId: draft.userId,
        active: fixture.active(),
        confirmation: ConfirmAttempt(
          id: 'c' * 32,
          orderId: sales.draftId,
          payment: InitialPayment(amount: '189000', method: 'cash'),
          createdAt: '2026-10-14T00:00:00Z',
          state: 'pending',
        ),
      ).encode();
      var posts = 0;
      final controller = await fixture.ready(store, (request) {
        if (request.method == 'POST') posts++;
        return auth.jsonResponse({'message': 'Not found'}, 404);
      });
      addTearDown(controller.dispose);
      await controller.drafts.confirm(
        InitialPayment(amount: '189000', method: 'cash'),
      );
      await controller.drafts.complete();
      expect(posts, 0);
      expect(controller.drafts.attempt!.orderId, sales.draftId);
      expect(controller.drafts.canCreate, false);
    },
  );
  test(
    'confirmed invoice collected less than acknowledged amount retains marker',
    () async {
      final store = fixture.store(customer: true);
      var sold = false;
      final controller = await fixture.ready(store, (request) {
        if (request.method == 'POST') {
          sold = true;
          return fixture.confirmed();
        }
        return auth.jsonResponse(
          fixture.detail(confirmed: sold, customer: true, paid: '0.00'),
        );
      });
      addTearDown(controller.dispose);
      await controller.drafts.confirm(
        InitialPayment(amount: '100000', method: 'cash'),
      );
      expect(controller.drafts.canComplete, false);
      await controller.drafts.complete();
      expect(controller.drafts.canCreate, false);
      expect(fixture.envelope(store).active!.orderId, sales.draftId);
    },
  );
  test(
    'completed journal survives creating another draft and its restart',
    () async {
      final store = fixture.store();
      var newDraft = false;
      final controller = await fixture.ready(store, (request) {
        if (request.method == 'POST') {
          newDraft = true;
          return auth.jsonResponse({'id': '41', 'status': 'draft'}, 201);
        }
        final detail = fixture.detail(confirmed: !newDraft);
        if (newDraft) {
          (detail['data'] as Json)['id'] = '41';
          (detail['items'] as List).first['order_id'] = '41';
        }
        return auth.jsonResponse(detail);
      });
      addTearDown(controller.dispose);
      await controller.drafts.complete();
      await controller.drafts.submit(
        draft.payload(),
        origin: draft.origin,
        userId: draft.userId,
      );
      expect(fixture.envelope(store).journal.length, 1);
      expect(fixture.envelope(store).active!.orderId, '41');
      await controller.drafts.restore();
      expect(controller.drafts.completedCount, 1);
      expect(controller.drafts.attempt!.orderId, '41');
      expect(controller.drafts.canCreate, false);
    },
  );
  for (final mutation in [
    'origin',
    'user',
    'version',
    'lost-id',
    'corrupt-journal',
  ]) {
    test('corrupt v2 $mutation locks without deleting active', () async {
      final store = fixture.store();
      final json =
          jsonDecode(
                SaleEnvelope(
                  origin: draft.origin,
                  userId: draft.userId,
                  active: fixture.active(),
                ).encode(),
              )
              as Json;
      switch (mutation) {
        case 'origin':
          json['origin'] = 'https://other.example.test';
        case 'user':
          json['user_id'] = '7';
        case 'version':
          json['version'] = 3;
        case 'lost-id':
          (json['active'] as Json)['order_id'] = null;
        case 'corrupt-journal':
          json['journal'] = [{}];
      }
      final raw = jsonEncode(json);
      store.values[store.values.keys.single] = raw;
      final controller = await draft.ready(
        (_) => throw StateError('No HTTP'),
        store: store,
      );
      addTearDown(controller.dispose);
      await controller.drafts.restore();
      expect(controller.drafts.state, DraftState.storageBlocked);
      expect(store.values.values.single, raw);
    });
  }
  test(
    'fresh GET changed price requires review before any confirm POST',
    () async {
      var reads = 0;
      var posts = 0;
      final controller = await fixture.ready(fixture.store(customer: true), (
        request,
      ) {
        if (request.method == 'POST') posts++;
        final detail = fixture.detail(customer: true);
        if (++reads > 1) {
          (detail['items'] as List).first.addAll({
            'unit_price': '110000.00',
            'line_total': '200000.00',
            'tax_amount': '10000.00',
          });
        }
        return auth.jsonResponse(detail);
      });
      addTearDown(controller.dispose);
      await controller.drafts.confirm(
        InitialPayment(amount: '100000', method: 'cash'),
      );
      expect(posts, 0);
      expect(controller.drafts.confirmation, null);
      expect(
        controller.drafts.error!.message,
        contains('Chi tiết đã thay đổi'),
      );
      expect(controller.drafts.detail!.draftTotal!.toString(), '210000.00');
    },
  );
}
