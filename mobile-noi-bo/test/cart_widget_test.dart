import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:klcn186_mobile/app.dart';
import 'package:klcn186_mobile/auth/auth_controller.dart';

import 'auth_test.dart' as support;
import 'cart_fixtures.dart' as fixture;
import 'sales_test.dart' as unit;
import 'sales_widget_test.dart' as view;

Future<void> openCart(
  WidgetTester tester,
  AuthController controller, {
  bool settle = true,
}) async {
  await tester.pumpWidget(MobileApp(controller: controller));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Chuẩn bị bán hàng'));
  await tester.tap(find.text('Chuẩn bị bán hàng'));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }
}

Finder get cartScroll => find
    .descendant(
      of: find.byKey(const ValueKey('cart-scroll')),
      matching: find.byType(Scrollable),
    )
    .first;

Future<void> addLot(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('Thêm vật tư / lô'),
    200,
    scrollable: cartScroll,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Thêm vật tư / lô'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Phân bón NPK'));
  await tester.pumpAndSettle();
}

void main() {
  WidgetController.hitTestWarningShouldBeFatal = true;
  testWidgets(
    'saved customer selection and guest remain scoped; remove line and back discard',
    (tester) async {
      view.viewport(tester);
      final controller = await unit.ready(
        (_) => support.jsonResponse(fixture.options()),
      );
      addTearDown(controller.dispose);
      await openCart(tester, controller);
      await tester.tap(find.byType(DropdownButtonFormField<String>).last);
      await tester.pumpAndSettle();
      expect(find.text('Khách chuỗi khác'), findsNothing);
      await tester.tap(find.text('Khách cùng chuỗi').last);
      await tester.pumpAndSettle();
      expect(find.text('Khách cùng chuỗi'), findsOneWidget);
      await addLot(tester);
      await tester.scrollUntilVisible(
        find.byTooltip('Bỏ lô LO31'),
        -150,
        scrollable: cartScroll,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Bỏ lô LO31'));
      await tester.pumpAndSettle();
      expect(find.text('Giỏ hàng · 0/50 lô'), findsOneWidget);
      await addLot(tester);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Rời giỏ hàng?'), findsOneWidget);
      await tester.tap(find.text('Giữ giỏ'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bỏ giỏ'));
      await tester.pumpAndSettle();
      expect(find.text('Giỏ hàng · 1/50 lô'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'refresh cancellation preserves inputs; confirmed refresh discards stale cart',
    (tester) async {
      view.viewport(tester);
      var calls = 0;
      final controller = await unit.ready((_) {
        calls++;
        return support.jsonResponse(fixture.options());
      });
      addTearDown(controller.dispose);
      await openCart(tester, controller);
      await addLot(tester);
      await tester.tap(find.byTooltip('Tải lại dữ liệu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Giữ giỏ'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('Giỏ hàng · 1/50 lô'), findsOneWidget);
      await tester.tap(find.byTooltip('Tải lại dữ liệu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bỏ giỏ'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('Giỏ hàng · 0/50 lô'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('small picker remains usable with keyboard inset', (
    tester,
  ) async {
    view.viewport(tester, small: true);
    final controller = await unit.ready(
      (_) => support.jsonResponse(fixture.options()),
    );
    addTearDown(controller.dispose);
    await openCart(tester, controller);
    await tester.scrollUntilVisible(
      find.text('Thêm vật tư / lô'),
      200,
      scrollable: cartScroll,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thêm vật tư / lô'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'GET options uses Bearer and branch/chain; no POST; exact cart total and validation',
    (tester) async {
      view.viewport(tester);
      final requests = <http.Request>[];
      final controller = await unit.ready((request) {
        requests.add(request);
        return support.jsonResponse(fixture.options());
      });
      addTearDown(controller.dispose);
      await openCart(tester, controller);
      expect(find.text('Kho bán'), findsOneWidget);
      expect(find.text('Khách lẻ'), findsOneWidget);
      await addLot(tester);
      await tester.enterText(find.byKey(const ValueKey('quantity-31')), '2');
      await tester.enterText(
        find.byKey(const ValueKey('discount-31')),
        '20000',
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Tổng dự kiến'),
        200,
        scrollable: cartScroll,
      );
      await tester.pumpAndSettle();
      expect(find.text('189.000 ₫'), findsWidgets);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('quantity-31')),
        -150,
        scrollable: cartScroll,
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('quantity-31')), '101');
      await tester.pumpAndSettle();
      expect(find.textContaining('Vượt tồn'), findsWidgets);
      expect(find.text('Tổng dự kiến'), findsNothing);
      expect(requests, hasLength(1));
      expect(requests.single.url.path, '/api/sales-orders/options');
      expect(requests.single.method, 'GET');
      expect(requests.single.headers['Authorization'], 'Bearer test-token');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'picker disables duplicate, expired and missing tax; search does not show other scope',
    (tester) async {
      view.viewport(tester);
      final controller = await unit.ready(
        (_) => support.jsonResponse(fixture.options()),
      );
      addTearDown(controller.dispose);
      await openCart(tester, controller);
      await addLot(tester);
      await tester.scrollUntilVisible(
        find.text('Thêm vật tư / lô'),
        200,
        scrollable: cartScroll,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Thêm vật tư / lô'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Lô đã có'), findsOneWidget);
      expect(find.textContaining('chưa được cấu hình thuế'), findsOneWidget);
      expect(find.textContaining('Lô đã hết hạn'), findsOneWidget);
      expect(find.text('Vật tư ngoài phạm vi'), findsNothing);
      final tile = tester.widget<ListTile>(
        find.widgetWithText(ListTile, 'Phân bón NPK'),
      );
      expect(tile.onTap, isNull);
      await tester.enterText(find.byType(TextField).last, 'không tồn tại');
      await tester.pumpAndSettle();
      expect(find.text('Không có lô phù hợp trong kho này.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'changing warehouse requires discard; cancelling restores selection and cart',
    (tester) async {
      view.viewport(tester);
      final controller = await unit.ready(
        (_) => support.jsonResponse(fixture.options(twoWarehouses: true)),
      );
      addTearDown(controller.dispose);
      await openCart(tester, controller);
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kho bán').last);
      await tester.pumpAndSettle();
      await addLot(tester);
      Future<void> selectOther() async {
        await tester.scrollUntilVisible(
          find.text('Kho bán'),
          -200,
          scrollable: cartScroll,
        );
        await tester.tap(find.byType(DropdownButtonFormField<String>).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Kho phụ').last);
        await tester.pumpAndSettle();
      }

      await selectOther();
      await tester.tap(find.text('Giữ giỏ'));
      await tester.pumpAndSettle();
      expect(find.text('Kho bán'), findsOneWidget);
      expect(find.text('Giỏ hàng · 1/50 lô'), findsOneWidget);
      await selectOther();
      await tester.tap(find.text('Bỏ giỏ'));
      await tester.pumpAndSettle();
      expect(find.text('Kho phụ'), findsOneWidget);
      expect(find.text('Giỏ hàng · 0/50 lô'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final empty in [true, false]) {
    testWidgets(empty ? 'empty warehouse scope' : 'empty stock picker', (
      tester,
    ) async {
      view.viewport(tester);
      final controller = await unit.ready(
        (_) => support.jsonResponse(
          fixture.options()..[empty ? 'warehouses' : 'stock'] = [],
        ),
      );
      addTearDown(controller.dispose);
      await openCart(tester, controller);
      if (empty) {
        expect(find.textContaining('Chưa có kho được phép'), findsOneWidget);
      } else {
        await tester.tap(find.text('Thêm vật tư / lô'));
        await tester.pumpAndSettle();
        expect(find.text('Không có lô phù hợp trong kho này.'), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('loading/network/manual recovery do not retry automatically', (
    tester,
  ) async {
    view.viewport(tester);
    final pending = Completer<http.Response>();
    var calls = 0;
    final controller = await unit.ready((_) {
      calls++;
      return calls == 1
          ? pending.future
          : support.jsonResponse(fixture.options());
    });
    addTearDown(controller.dispose);
    await openCart(tester, controller, settle: false);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.completeError(http.ClientException('offline'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Không kết nối được API'), findsOneWidget);
    expect(calls, 1);
    await tester.tap(find.text('Tải lại'));
    await tester.pumpAndSettle();
    expect(find.text('Kho bán'), findsOneWidget);
    expect(calls, 2);
    await tester.pumpWidget(const SizedBox());
  });
  for (final status in [401, 403]) {
    testWidgets('HTTP$status closes cart and removes options', (tester) async {
      view.viewport(tester);
      final controller = await unit.ready(
        (_) => support.jsonResponse({}, status),
      );
      addTearDown(controller.dispose);
      await openCart(tester, controller);
      expect(find.text('Chuẩn bị bán hàng'), findsNothing);
      expect(
        find.text(status == 401 ? 'Đăng nhập' : 'Chưa thể mở nơi làm việc'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('scope change discards cart and closes open stock picker', (
    tester,
  ) async {
    view.viewport(tester);
    final controller = await unit.ready(
      (_) => support.jsonResponse(fixture.options()),
    );
    addTearDown(controller.dispose);
    await openCart(tester, controller);
    await addLot(tester);
    await tester.scrollUntilVisible(
      find.text('Thêm vật tư / lô'),
      200,
      scrollable: cartScroll,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Thêm vật tư / lô'));
    await tester.pumpAndSettle();
    controller.changeScope();
    await tester.pumpAndSettle();
    expect(find.text('Chọn nơi làm việc'), findsOneWidget);
    expect(find.text('Phân bón NPK'), findsNothing);
    expect(find.text('Chọn vật tư / lô'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('late old-scope options are discarded', (tester) async {
    view.viewport(tester);
    final pending = Completer<http.Response>();
    final controller = await unit.ready((_) => pending.future);
    addTearDown(controller.dispose);
    await openCart(tester, controller, settle: false);
    controller.changeScope();
    await tester.pumpAndSettle();
    pending.complete(support.jsonResponse(fixture.options()));
    await tester.pumpAndSettle();
    expect(find.text('Kho bán'), findsNothing);
    expect(find.text('Chọn nơi làm việc'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    '320x568 text1.5 cart, picker, validation and totals scroll without overflow',
    (tester) async {
      view.viewport(tester, small: true);
      final controller = await unit.ready(
        (_) => support.jsonResponse(fixture.options()),
      );
      addTearDown(controller.dispose);
      await openCart(tester, controller);
      await addLot(tester);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('quantity-31')),
        -150,
        scrollable: cartScroll,
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('quantity-31')),
        '1.0001',
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.enterText(
        find.byKey(const ValueKey('quantity-31')),
        '0,125',
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Tổng dự kiến'),
        200,
        scrollable: cartScroll,
      );
      await tester.pumpAndSettle();
      expect(find.text('13.125 ₫'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
