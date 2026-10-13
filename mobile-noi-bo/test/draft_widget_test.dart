import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:klcn186_mobile/app.dart';
import 'package:klcn186_mobile/auth/auth_controller.dart';
import 'package:klcn186_mobile/sales/draft_workspace.dart';

import 'auth_test.dart' as support;
import 'cart_fixtures.dart' as cart;
import 'cart_widget_test.dart' as cart_view;
import 'draft_fixtures.dart' as fixture;
import 'sales_widget_test.dart' as view;

Finder get draftScroll => find
    .descendant(
      of: find.byKey(const ValueKey('draft-scroll')),
      matching: find.byType(Scrollable),
    )
    .first;

Future<void> review(WidgetTester tester, AuthController controller) async {
  await tester.pumpWidget(
    MaterialApp(
      home: DraftWorkspace(
        controller: controller,
        review: DraftReview.fromCart(controller, fixture.salesCart()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> pressCreate(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey('create-draft')),
    150,
    scrollable: draftScroll,
  );
  await tester.tap(find.byKey(const ValueKey('create-draft')));
  await tester.pumpAndSettle();
}

void main() {
  WidgetController.hitTestWarningShouldBeFatal = true;
  testWidgets(
    'cart review requires user action, frozen review, 201 detail server total no payment',
    (tester) async {
      view.viewport(tester);
      final requests = <http.Request>[];
      final controller = await fixture.ready((request) {
        requests.add(request);
        if (request.url.path.endsWith('/options')) {
          return support.jsonResponse(cart.options());
        }
        if (request.method == 'POST') return fixture.created();
        return support.jsonResponse(fixture.detail());
      }, store: fixture.MemoryDraftStore());
      addTearDown(controller.dispose);
      await cart_view.openCart(tester, controller);
      await cart_view.addLot(tester);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('quantity-31')),
        -150,
        scrollable: cart_view.cartScroll,
      );
      await tester.enterText(find.byKey(const ValueKey('quantity-31')), '2');
      await tester.enterText(
        find.byKey(const ValueKey('discount-31')),
        '20000',
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('review-draft')),
        200,
        scrollable: cart_view.cartScroll,
      );
      await tester.tap(find.byKey(const ValueKey('review-draft')));
      await tester.pumpAndSettle();
      expect(requests.where((request) => request.method == 'POST'), isEmpty);
      await pressCreate(tester);
      await tester.scrollUntilVisible(
        find.text('Tổng theo máy chủ: 189.000 ₫'),
        150,
        scrollable: draftScroll,
      );
      expect(find.text('Tổng theo máy chủ: 189.000 ₫'), findsOneWidget);
      expect(find.byKey(const ValueKey('create-draft')), findsNothing);
      expect(requests.where((request) => request.method == 'POST').length, 1);
      expect(
        requests.any((request) => request.url.path.endsWith('/confirm')),
        false,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'UNKNOWN has no create/retry/clear; home recovery retains marker after reopen',
    (tester) async {
      view.viewport(tester);
      var posts = 0;
      final store = fixture.MemoryDraftStore();
      final controller = await fixture.ready((_) {
        posts++;
        return support.jsonResponse({'message': 'server'}, 500);
      }, store: store);
      addTearDown(controller.dispose);
      await review(tester, controller);
      await pressCreate(tester);
      expect(find.text('Chưa xác định kết quả tạo đơn'), findsOneWidget);
      expect(find.byKey(const ValueKey('create-draft')), findsNothing);
      expect(find.text('Tải lại chi tiết'), findsNothing);
      await tester.pumpWidget(MobileApp(controller: controller));
      await tester.pumpAndSettle();
      final button = find.text('Kiểm tra đơn nháp đang xử lý');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('Chưa xác định kết quả tạo đơn'), findsOneWidget);
      expect(posts, 1);
      expect(store.values.length, 1);
    },
  );

  testWidgets(
    'KNOWN_ID failed GET exposes GET-only retry; detail price from server may differ',
    (tester) async {
      view.viewport(tester);
      var healthy = false;
      var posts = 0;
      final controller = await fixture.ready((request) {
        if (request.method == 'POST') {
          posts++;
          return fixture.created();
        }
        if (!healthy) return support.jsonResponse({'message': 'test'}, 500);
        final json = fixture.detail();
        (json['items'] as List).first.addAll({
          'unit_price': '110000.00',
          'line_total': '200000.00',
          'tax_amount': '10000.00',
        });
        return support.jsonResponse(json);
      }, store: fixture.MemoryDraftStore());
      addTearDown(controller.dispose);
      await review(tester, controller);
      await pressCreate(tester);
      expect(find.text('Đã tạo đơn nháp'), findsOneWidget);
      healthy = true;
      await tester.ensureVisible(find.text('Tải lại chi tiết'));
      await tester.tap(find.text('Tải lại chi tiết'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Tổng theo máy chủ: 210.000 ₫'),
        150,
        scrollable: draftScroll,
      );
      expect(find.text('Tổng theo máy chủ: 210.000 ₫'), findsOneWidget);
      expect(posts, 1);
    },
  );

  testWidgets(
    'validation rejected maps line error, new send must be intentional',
    (tester) async {
      view.viewport(tester);
      var posts = 0;
      final controller = await fixture.ready((_) {
        posts++;
        return support.jsonResponse({
          'message': 'rejected',
          'errors': {
            'items.0.quantity': ['Kiểm tra số lượng.'],
          },
        }, 422);
      }, store: fixture.MemoryDraftStore());
      addTearDown(controller.dispose);
      await review(tester, controller);
      await pressCreate(tester);
      expect(find.text('Yêu cầu đã bị từ chối'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Dòng 1 · Số lượng: Kiểm tra số lượng.'),
        150,
        scrollable: draftScroll,
      );
      expect(
        find.text('Dòng 1 · Số lượng: Kiểm tra số lượng.'),
        findsOneWidget,
      );
      expect(posts, 1);
    },
  );

  testWidgets('storage read error has no create, only manual storage recheck', (
    tester,
  ) async {
    view.viewport(tester);
    final store = fixture.MemoryDraftStore()..failRead = true;
    final controller = await fixture.ready(
      (_) => throw StateError('No HTTP'),
      store: store,
    );
    addTearDown(controller.dispose);
    await review(tester, controller);
    expect(find.text('Tạm khóa tạo nháp'), findsOneWidget);
    expect(find.byKey(const ValueKey('create-draft')), findsNothing);
    store.failRead = false;
    await tester.ensureVisible(find.text('Đọc lại trạng thái đã lưu'));
    await tester.tap(find.text('Đọc lại trạng thái đã lưu'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('create-draft')), findsOneWidget);
  });

  testWidgets(
    'closing review during POST preserves coordinator and 201; reopening only GET',
    (tester) async {
      view.viewport(tester);
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
      await review(tester, controller);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('create-draft')),
        150,
        scrollable: draftScroll,
      );
      await tester.tap(find.byKey(const ValueKey('create-draft')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(const MaterialApp(home: Text('Màn khác')));
      response.complete(fixture.created());
      await tester.pumpAndSettle();
      await review(tester, controller);
      expect(find.text('Đã tạo đơn nháp'), findsOneWidget);
      expect(posts, 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final state in [
    'review',
    'unknown',
    'storage',
    'known',
    'missing-tax',
  ]) {
    testWidgets('320x568 text1.5 keyboard scroll $state no overflow', (
      tester,
    ) async {
      view.viewport(tester, small: true);
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      addTearDown(tester.view.resetViewInsets);
      final store = fixture.MemoryDraftStore()..failRead = state == 'storage';
      if (state == 'unknown' || state == 'known' || state == 'missing-tax') {
        store.values[store.key(fixture.origin, fixture.userId)] = fixture
            .attempt(state: state == 'unknown' ? 'unknown_outcome' : 'known_id')
            .encode();
      }
      final controller = await fixture.ready(
        (_) => support.jsonResponse(
          fixture.detail(missingTax: state == 'missing-tax'),
        ),
        store: store,
      );
      addTearDown(controller.dispose);
      await review(tester, controller);
      if (state == 'known' || state == 'missing-tax') {
        await tester.scrollUntilVisible(
          find.text('Tải lại chi tiết'),
          100,
          scrollable: draftScroll,
        );
        await tester.tap(find.text('Tải lại chi tiết'));
        await tester.pumpAndSettle();
      }
      await tester.drag(
        find.byKey(const ValueKey('draft-scroll')),
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
