import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:klcn186_mobile/sales/confirmation.dart';
import 'package:klcn186_mobile/sales/models.dart';

import 'auth_test.dart' as auth;
import 'cart_fixtures.dart' as cart;
import 'cart_widget_test.dart' as cart_view;
import 'confirm_fixtures.dart' as confirm;
import 'confirm_widget_test.dart' as confirm_view;
import 'draft_fixtures.dart' as draft;
import 'draft_widget_test.dart' as draft_view;
import 'sales_fixtures.dart' as sales;
import 'sales_widget_test.dart' as view;

Future<void> prepareCart(WidgetTester tester) async {
  await cart_view.addLot(tester);
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('quantity-31')),
    -150,
    scrollable: cart_view.cartScroll,
  );
  await tester.enterText(find.byKey(const ValueKey('quantity-31')), '2');
  await tester.enterText(find.byKey(const ValueKey('discount-31')), '20000');
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('review-draft')),
    200,
    scrollable: cart_view.cartScroll,
  );
  await tester.tap(find.byKey(const ValueKey('review-draft')));
  await tester.pumpAndSettle();
}

void main() {
  WidgetController.hitTestWarningShouldBeFatal = true;
  testWidgets(
    'cart to invoice to journal, restart and next draft use one POST per user action',
    (tester) async {
      view.viewport(tester);
      final previousErrorHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        debugPrintStack(
          label: details.exceptionAsString(),
          stackTrace: details.stack,
        );
        previousErrorHandler?.call(details);
      };
      addTearDown(() => FlutterError.onError = previousErrorHandler);
      final store = draft.MemoryDraftStore();
      final posts = <String>[];
      var sold = false;
      var orderId = sales.draftId;
      http.Response handler(http.Request request) {
        expect(request.headers['authorization'], startsWith('Bearer '));
        expect(request.headers.containsKey('cookie'), false);
        if (request.url.path.endsWith('/options')) {
          return auth.jsonResponse(cart.options());
        }
        if (request.method == 'POST') {
          posts.add(request.url.path);
          if (request.url.path.endsWith('/confirm')) {
            final saved = confirm.envelope(store);
            expect(saved.active!.orderId, orderId);
            expect(saved.confirmation!.state, 'pending');
            expect(jsonDecode(request.body), {
              'amount': '189000.00',
              'method': 'cash',
            });
            sold = true;
            return auth.jsonResponse({'id': orderId, 'status': 'confirmed'});
          }
          final raw = jsonDecode(store.values.values.single) as Json;
          final active = raw['version'] == 2 ? raw['active'] as Json : raw;
          expect(active['state'], 'pending');
          expect(active['order_id'], null);
          final body = jsonDecode(request.body) as Json;
          expect(body['items'], [
            {
              'lot_id': '31',
              'quantity': '2.000',
              'discount_amount': '20000.00',
            },
          ]);
          return auth.jsonResponse({'id': orderId, 'status': 'draft'}, 201);
        }
        expect(request.method, 'GET');
        expect(request.url.path, '/api/sales-orders/$orderId');
        final detail = confirm.detail(confirmed: sold);
        (detail['data'] as Json)['id'] = orderId;
        (detail['items'] as List).first['order_id'] = orderId;
        final raw = jsonDecode(store.values.values.single) as Json;
        final savedId = raw['version'] == 2
            ? (raw['active'] as Json)['order_id']
            : raw['order_id'];
        expect(savedId, orderId);
        return auth.jsonResponse(detail);
      }

      final controller = await draft.ready(handler, store: store);
      await cart_view.openCart(tester, controller);
      await prepareCart(tester);
      expect(posts, isEmpty);
      await draft_view.pressCreate(tester);
      expect(tester.takeException(), isNull, reason: 'after draft creation');
      expect(posts, ['/api/sales-orders']);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('review-confirm')),
        150,
        scrollable: draft_view.draftScroll,
      );
      await tester.tap(find.byKey(const ValueKey('review-confirm')));
      await tester.pumpAndSettle();
      expect(
        tester.takeException(),
        isNull,
        reason: 'after navigation from draft to confirm',
      );
      await confirm_view.tapKey(tester, 'confirm-sale');
      expect(find.text('Hóa đơn nội bộ'), findsOneWidget);
      expect(controller.drafts.canCreate, false);
      await confirm_view.tapKey(tester, 'complete-sale');
      expect(controller.drafts.canCreate, true);
      expect(confirm.envelope(store).journal.single['order_id'], sales.draftId);
      expect(posts, [
        '/api/sales-orders',
        '/api/sales-orders/${sales.draftId}/confirm',
      ]);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();

      orderId = '9007199254741011';
      sold = false;
      final restarted = await draft.ready(handler, store: store);
      addTearDown(restarted.dispose);
      await restarted.drafts.restore();
      expect(restarted.drafts.completedCount, 1);
      expect(restarted.drafts.canCreate, true);
      expect(posts.length, 2);
      await cart_view.openCart(tester, restarted);
      await prepareCart(tester);
      expect(posts.length, 2);
      await draft_view.pressCreate(tester);
      expect(restarted.drafts.attempt!.orderId, orderId);
      expect(restarted.drafts.canCreate, false);
      expect(confirm.envelope(store).journal.single['order_id'], sales.draftId);
      expect(posts, [
        '/api/sales-orders',
        '/api/sales-orders/${sales.draftId}/confirm',
        '/api/sales-orders',
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'new draft then lost confirm response survives restart without resubmission',
    () async {
      final store = draft.MemoryDraftStore();
      var creates = 0;
      var confirms = 0;
      var sold = false;
      var offline = false;
      http.Response handler(http.Request request) {
        if (request.method == 'POST' && request.url.path.endsWith('/confirm')) {
          confirms++;
          expect(confirm.envelope(store).confirmation!.state, 'pending');
          sold = true;
          offline = true;
          throw http.ClientException('response lost');
        }
        if (request.method == 'POST') {
          creates++;
          return draft.created();
        }
        if (offline) throw http.ClientException('offline GET');
        return auth.jsonResponse(confirm.detail(confirmed: sold));
      }

      final controller = await draft.ready(handler, store: store);
      await controller.drafts.restore();
      await controller.drafts.submit(
        draft.payload(),
        origin: draft.origin,
        userId: draft.userId,
      );
      expect(controller.drafts.canConfirm, true);
      await controller.drafts.confirm(
        InitialPayment(amount: '189000', method: 'cash'),
      );
      expect(confirm.envelope(store).active!.orderId, sales.draftId);
      expect(confirm.envelope(store).confirmation!.state, 'unknown');
      expect(controller.drafts.canCreate, false);
      controller.dispose();

      final restarted = await draft.ready(handler, store: store);
      addTearDown(restarted.dispose);
      await restarted.drafts.restore();
      await restarted.drafts.reloadDetail();
      await restarted.drafts.confirm(
        InitialPayment(amount: '189000', method: 'cash'),
      );
      await restarted.drafts.submit(
        draft.payload(),
        origin: draft.origin,
        userId: draft.userId,
      );
      expect(creates, 1);
      expect(confirms, 1);
      expect(restarted.drafts.canComplete, false);
      offline = false;
      await restarted.drafts.reloadDetail();
      expect(restarted.drafts.canComplete, true);
      expect(restarted.drafts.canCreate, false);
      await restarted.drafts.complete();
      expect(confirm.envelope(store).journal.single['order_id'], sales.draftId);
      expect(restarted.drafts.canCreate, true);
      expect(creates, 1);
      expect(confirms, 1);
    },
  );
}
