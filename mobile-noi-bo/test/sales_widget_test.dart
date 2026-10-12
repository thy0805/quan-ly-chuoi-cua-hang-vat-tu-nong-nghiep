import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:klcn186_mobile/app.dart';
import 'package:klcn186_mobile/auth/auth_controller.dart';

import 'auth_test.dart' as support;
import 'sales_fixtures.dart' as fixture;
import 'sales_test.dart' as unit;

Future<void> openHistory(
  WidgetTester tester,
  AuthController controller, {
  bool settle = true,
}) async {
  await tester.pumpWidget(MobileApp(controller: controller));
  await tester.pumpAndSettle();
  final button = find.text('Lịch sử bán hàng');
  await tester.ensureVisible(button);
  await tester.tap(button);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }
}

void viewport(WidgetTester tester, {bool small = false}) {
  tester.view.physicalSize = small
      ? const Size(320, 568)
      : const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  if (small) {
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }
}

void main() {
  testWidgets(
    'read-only history and detail; draft never displays header zero; no business POST',
    (tester) async {
      viewport(tester);
      final requests = <http.Request>[];
      final controller = await unit.ready((request) {
        requests.add(request);
        return support.jsonResponse(
          request.url.path == '/api/sales-orders'
              ? fixture.history()
              : fixture.detail(
                  draft: request.url.path.endsWith(fixture.draftId),
                ),
        );
      });
      addTearDown(controller.dispose);
      await openHistory(tester, controller);
      expect(find.text('Chỉ xem'), findsOneWidget);
      expect(find.textContaining('50 đơn gần nhất'), findsOneWidget);
      expect(find.byKey(const ValueKey('order-2')), findsNothing);
      expect(find.text('Tổng chưa chốt'), findsOneWidget);
      expect(find.text('0 ₫'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('order-${fixture.draftId}')));
      await tester.pumpAndSettle();
      expect(find.text('Phân bón NPK 16-16-8'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Tổng theo dòng đã lưu'), 300);
      expect(find.text('257.400 ₫'), findsOneWidget);
      expect(find.text('0 ₫'), findsNothing);
      expect(find.text('Xác nhận đơn'), findsNothing);
      expect(find.text('Thanh toán'), findsNothing);
      expect(requests.every((request) => request.method == 'GET'), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'confirmed invoice shows authoritative paid and remaining values',
    (tester) async {
      viewport(tester);
      final controller = await unit.ready(
        (request) => support.jsonResponse(
          request.url.path == '/api/sales-orders'
              ? fixture.history()
              : fixture.detail(),
        ),
      );
      addTearDown(controller.dispose);
      await openHistory(tester, controller);
      await tester.tap(find.byKey(const ValueKey('order-${fixture.orderId}')));
      await tester.pumpAndSettle();
      expect(find.text('HD-20261012-001'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Còn phải thu'), 300);
      expect(find.text('100.000 ₫'), findsOneWidget);
      expect(find.text('157.400 ₫'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('missing snapshot is shown as unknown, not assumed zero', (
    tester,
  ) async {
    viewport(tester);
    final controller = await unit.ready(
      (request) => support.jsonResponse(
        request.url.path == '/api/sales-orders'
            ? {
                'data': [fixture.summary(draft: true)],
              }
            : fixture.detail(draft: true, missingTax: true),
      ),
    );
    addTearDown(controller.dispose);
    await openHistory(tester, controller);
    await tester.tap(find.byKey(const ValueKey('order-${fixture.draftId}')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Tổng theo dòng đã lưu'), 300);
    expect(find.text('Chưa có dữ liệu'), findsWidgets);
    expect(find.text('0 ₫'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('loading and empty are explicit; retry is an intentional GET', (
    tester,
  ) async {
    viewport(tester);
    final response = Completer<http.Response>();
    var count = 0;
    final controller = await unit.ready((_) {
      count++;
      return count == 1 ? response.future : support.jsonResponse({'data': []});
    });
    addTearDown(controller.dispose);
    await openHistory(tester, controller, settle: false);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    response.complete(support.jsonResponse({'data': []}));
    await tester.pumpAndSettle();
    expect(find.textContaining('Chưa có đơn hàng'), findsOneWidget);
    await tester.tap(find.byTooltip('Tải lại'));
    await tester.pumpAndSettle();
    expect(count, 2);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    '404 detail clears previous history, shows safe error and back recovers',
    (tester) async {
      viewport(tester);
      final controller = await unit.ready(
        (request) => support.jsonResponse(
          request.url.path == '/api/sales-orders'
              ? fixture.history()
              : {'message': 'SQL password hidden'},
          request.url.path == '/api/sales-orders' ? 200 : 404,
        ),
      );
      addTearDown(controller.dispose);
      await openHistory(tester, controller);
      await tester.tap(find.byKey(const ValueKey('order-${fixture.orderId}')));
      await tester.pumpAndSettle();
      expect(find.text('HTTP 404'), findsOneWidget);
      expect(find.textContaining('SQL password'), findsNothing);
      expect(
        find.byKey(const ValueKey('order-${fixture.orderId}')),
        findsNothing,
      );
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Tổng chưa chốt'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final status in [401, 403]) {
    testWidgets(
      'HTTP $status exits protected sales and discards all order data',
      (tester) async {
        viewport(tester);
        var blocked = false;
        final controller = await unit.ready(
          (_) => support.jsonResponse(
            blocked ? {} : fixture.history(),
            blocked ? status : 200,
          ),
        );
        addTearDown(controller.dispose);
        await openHistory(tester, controller);
        blocked = true;
        await tester.tap(find.byTooltip('Tải lại'));
        await tester.pumpAndSettle();
        expect(find.text('BH-20261012-001'), findsNothing);
        expect(
          find.text(status == 401 ? 'Đăng nhập' : 'Chưa thể mở nơi làm việc'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('late old-scope response is not visible after switching scope', (
    tester,
  ) async {
    viewport(tester);
    final response = Completer<http.Response>();
    final controller = await unit.ready((_) => response.future);
    addTearDown(controller.dispose);
    await openHistory(tester, controller, settle: false);
    controller.changeScope();
    await tester.pumpAndSettle();
    response.complete(support.jsonResponse(fixture.history()));
    await tester.pumpAndSettle();
    expect(find.text('Chọn nơi làm việc'), findsOneWidget);
    expect(find.text('BH-20261012-001'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'small screen enlarged text history and full detail remain scrollable without overflow',
    (tester) async {
      viewport(tester, small: true);
      final controller = await unit.ready(
        (request) => support.jsonResponse(
          request.url.path == '/api/sales-orders'
              ? fixture.history()
              : fixture.detail(),
        ),
      );
      addTearDown(controller.dispose);
      await openHistory(tester, controller);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('BH-20261012-001'));
      await tester.tap(find.text('BH-20261012-001'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Còn phải thu'), 250);
      expect(find.text('157.400 ₫'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
