import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:klcn186_mobile/app.dart';
import 'package:klcn186_mobile/auth/auth_controller.dart';

import 'auth_test.dart' as auth;
import 'sales_test.dart' as sales;
import 'sales_widget_test.dart' as view;
import 'transfer_fixtures.dart' as fixture;

Future<void> open(
  WidgetTester tester,
  AuthController controller, {
  bool settle = true,
}) async {
  await tester.pumpWidget(MobileApp(controller: controller));
  await tester.pumpAndSettle();
  final button = find.byKey(const Key('open-transfers'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }
}

void main() {
  testWidgets(
    'home to transfer list/detail/back; GET only even when API grants actions',
    (tester) async {
      view.viewport(tester);
      final requests = <http.Request>[];
      final controller = await sales.ready((request) {
        requests.add(request);
        return auth.jsonResponse(
          request.url.path == '/api/stock-transfers'
              ? fixture.page(
                  rows: [
                    fixture.summary(),
                    fixture.summary(id: '2', from: '8', to: '9'),
                  ],
                )
              : fixture.detail(),
        );
      });
      addTearDown(controller.dispose);
      await open(tester, controller);
      expect(find.text('Chỉ xem'), findsOneWidget);
      expect(find.byKey(const ValueKey('transfer-2')), findsNothing);
      await tester.tap(
        find.byKey(const ValueKey('transfer-${fixture.transferId}')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Đã đối soát'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Phân bón NPK 16-16-8'), 250);
      await tester.scrollUntilVisible(find.text('2,125 bao'), 150);
      expect(find.text('2,125 bao'), findsOneWidget);
      expect(find.text('Duyệt phiếu'), findsNothing);
      expect(find.text('Xuất kho'), findsNothing);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Trang 1 / 1'), findsOneWidget);
      expect(requests.every((r) => r.method == 'GET'), true);
      expect(
        requests.any((r) => r.url.path.endsWith(fixture.transferId)),
        true,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'scoped empty page still exposes pagination and preserves requested page',
    (tester) async {
      view.viewport(tester);
      final pages = <String>[];
      final controller = await sales.ready((request) {
        final page = request.url.queryParameters['page']!;
        pages.add(page);
        return auth.jsonResponse(
          fixture.page(
            current: int.parse(page),
            last: 2,
            rows: page == '1'
                ? [fixture.summary(from: '2', to: '3')]
                : [fixture.summary()],
          ),
        );
      });
      addTearDown(controller.dispose);
      await open(tester, controller);
      expect(
        find.text('Chưa có phiếu phù hợp trên trang này.'),
        findsOneWidget,
      );
      final next = find.byKey(const Key('next-transfers'));
      await tester.ensureVisible(next);
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('transfer-${fixture.transferId}')),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Trang 2 / 2'));
      expect(find.text('Trang 2 / 2'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(next).onPressed, isNull);
      expect(pages, ['1', '2']);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'loading then empty, reload and offline recovery use explicit GET',
    (tester) async {
      view.viewport(tester);
      final pending = Completer<http.Response>();
      var call = 0;
      final controller = await sales.ready((request) {
        call++;
        if (call == 1) return pending.future;
        if (call == 2) throw http.ClientException('offline');
        return auth.jsonResponse(fixture.page(rows: []));
      });
      addTearDown(controller.dispose);
      await open(tester, controller, settle: false);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      pending.complete(auth.jsonResponse(fixture.page(rows: [])));
      await tester.pumpAndSettle();
      expect(
        find.text('Chưa có phiếu phù hợp trên trang này.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('reload-transfers')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('transfer-error')), findsOneWidget);
      await tester.tap(find.byKey(const Key('retry-transfers')));
      await tester.pumpAndSettle();
      expect(
        find.text('Chưa có phiếu phù hợp trên trang này.'),
        findsOneWidget,
      );
      expect(call, 3);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('detail404 hides previous content and allows returning to list', (
    tester,
  ) async {
    view.viewport(tester);
    final controller = await sales.ready(
      (request) => request.url.path == '/api/stock-transfers'
          ? auth.jsonResponse(fixture.page())
          : auth.jsonResponse({'message': 'SQL secret hidden'}, 404),
    );
    addTearDown(controller.dispose);
    await open(tester, controller);
    await tester.tap(
      find.byKey(const ValueKey('transfer-${fixture.transferId}')),
    );
    await tester.pumpAndSettle();
    expect(find.text('HTTP 404'), findsOneWidget);
    expect(find.textContaining('SQL secret'), findsNothing);
    expect(
      find.byKey(const ValueKey('transfer-${fixture.transferId}')),
      findsNothing,
    );
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('transfer-${fixture.transferId}')),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  for (final status in [401, 403]) {
    testWidgets(
      'revoked or forbidden $status closes route and removes transfer data',
      (tester) async {
        view.viewport(tester);
        var reject = false;
        final controller = await sales.ready(
          (_) => auth.jsonResponse(
            reject ? {'message': 'hidden'} : fixture.page(),
            reject ? status : 200,
          ),
        );
        addTearDown(controller.dispose);
        await open(tester, controller);
        reject = true;
        await tester.tap(find.byKey(const Key('reload-transfers')));
        await tester.pumpAndSettle();
        expect(find.text('Điều chuyển kho'), findsNothing);
        expect(
          find.byKey(const ValueKey('transfer-${fixture.transferId}')),
          findsNothing,
        );
        expect(
          controller.stage,
          status == 401 ? AuthStage.signedOut : AuthStage.unavailable,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('changing scope discards delayed list and leaves route', (
    tester,
  ) async {
    view.viewport(tester);
    final response = Completer<http.Response>();
    final controller = await sales.ready((_) => response.future);
    addTearDown(controller.dispose);
    await open(tester, controller, settle: false);
    controller.changeScope();
    response.complete(auth.jsonResponse(fixture.page()));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('transfer-${fixture.transferId}')),
      findsNothing,
    );
    expect(find.text('Chọn nơi làm việc'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'small320 text1.5, long warehouse names and reconciliation scroll without overflow',
    (tester) async {
      view.viewport(tester, small: true);
      final controller = await sales.ready((request) {
        final data = request.url.path == '/api/stock-transfers'
            ? fixture.page()
            : fixture.detail();
        if (request.url.path != '/api/stock-transfers') {
          (data['data'] as Map)['from_warehouse_name'] =
              'Kho vật tư nông nghiệp với tên dài tại chi nhánh Thủ Đức';
        }
        return auth.jsonResponse(data);
      });
      addTearDown(controller.dispose);
      await open(tester, controller);
      final title = find.text('DC-20261016-${fixture.transferId}');
      await tester.drag(find.byType(ListView).last, const Offset(0, -350));
      await tester.pumpAndSettle();
      expect(title.hitTestable(), findsOneWidget);
      await tester.tap(title);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Hao hụt đã xác nhận'), 180);
      expect(find.text('Hao hụt đã xác nhận'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('next-transfers')),
        150,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
