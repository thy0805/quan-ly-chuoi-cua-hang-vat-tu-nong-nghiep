import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';
import 'package:klcn186_mobile/auth/auth_controller.dart';
import 'package:klcn186_mobile/sales/confirm_workspace.dart';
import 'package:klcn186_mobile/sales/confirmation.dart';
import 'auth_test.dart' as auth;
import 'confirm_fixtures.dart' as fixture;
import 'sales_widget_test.dart' as view;

Finder get scroll => find
    .descendant(
      of: find.byKey(const ValueKey('confirm-scroll')),
      matching: find.byType(Scrollable),
    )
    .first;
Future<void> mount(WidgetTester tester, AuthController controller) async {
  await tester.pumpWidget(
    MaterialApp(home: ConfirmWorkspace(controller: controller)),
  );
  await tester.pumpAndSettle();
}

Future<void> tapKey(WidgetTester tester, String key) async {
  await tester.scrollUntilVisible(
    find.byKey(ValueKey(key)),
    180,
    scrollable: scroll,
  );
  await tester.ensureVisible(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}

void main() {
  WidgetController.hitTestWarningShouldBeFatal = true;
  testWidgets('pending confirm shows loading and disables shared actions', (
    tester,
  ) async {
    view.viewport(tester);
    final held = Completer<http.Response>();
    var posts = 0;
    final controller = await fixture.ready(fixture.store(), (request) {
      if (request.method == 'POST') {
        posts++;
        return held.future;
      }
      return auth.jsonResponse(fixture.detail());
    });
    addTearDown(controller.dispose);
    await mount(tester, controller);
    final operation = controller.drafts.confirm(
      InitialPayment(amount: '189000', method: 'cash'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(posts, 1);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const ValueKey('reload-confirm')))
          .onPressed,
      null,
    );
    expect(controller.drafts.canCreate, false);
    expect(controller.drafts.canConfirm, false);
    expect(controller.drafts.canComplete, false);
    held.complete(fixture.confirmed());
    await operation;
    await tester.pumpAndSettle();
    expect(posts, 1);
    expect(tester.takeException(), null);
  });
  for (final amount in ['189000', '100000', '0']) {
    testWidgets(
      'customer $amount review and internal invoice, deliberate complete',
      (tester) async {
        view.viewport(tester);
        var sold = false;
        var posts = 0;
        final controller = await fixture.ready(fixture.store(customer: true), (
          request,
        ) {
          if (request.method == 'POST') {
            posts++;
            sold = true;
            return fixture.confirmed();
          }
          return auth.jsonResponse(
            fixture.detail(confirmed: sold, customer: true, paid: '$amount.00'),
          );
        });
        addTearDown(controller.dispose);
        await mount(tester, controller);
        expect(posts, 0);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('initial-amount')),
          180,
          scrollable: scroll,
        );
        await tester.enterText(
          find.byKey(const ValueKey('initial-amount')),
          amount,
        );
        await tapKey(tester, 'confirm-sale');
        expect(posts, 1);
        expect(find.text('Hóa đơn nội bộ'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('complete-sale')),
          180,
          scrollable: scroll,
        );
        expect(controller.drafts.canCreate, false);
        await tapKey(tester, 'complete-sale');
        expect(controller.drafts.canCreate, true);
        expect(find.text('Đã lưu nhật ký hoàn tất'), findsOneWidget);
        expect(tester.takeException(), null);
      },
    );
  }
  testWidgets('guest underpayment and invalid decimal blocked in form', (
    tester,
  ) async {
    view.viewport(tester);
    var posts = 0;
    final controller = await fixture.ready(fixture.store(), (request) {
      if (request.method == 'POST') posts++;
      return auth.jsonResponse(fixture.detail());
    });
    addTearDown(controller.dispose);
    await mount(tester, controller);
    for (final amount in ['0', '1.001']) {
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('initial-amount')),
        -150,
        scrollable: scroll,
      );
      await tester.enterText(
        find.byKey(const ValueKey('initial-amount')),
        amount,
      );
      await tapKey(tester, 'confirm-sale');
      expect(posts, 0);
    }
    expect(tester.takeException(), null);
  });
  testWidgets('bank transfer requires manual checked confirmation', (
    tester,
  ) async {
    view.viewport(tester);
    var posts = 0;
    final controller = await fixture.ready(fixture.store(), (request) {
      if (request.method == 'POST') {
        posts++;
        return fixture.confirmed();
      }
      return auth.jsonResponse(fixture.detail());
    });
    addTearDown(controller.dispose);
    await mount(tester, controller);
    await tester.scrollUntilVisible(
      find.byType(DropdownButtonFormField<String>),
      150,
      scrollable: scroll,
    );
    await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chuyển khoản thủ công').last);
    await tester.pumpAndSettle();
    await tapKey(tester, 'confirm-sale');
    expect(posts, 0);
    await tester.scrollUntilVisible(
      find.byType(CheckboxListTile),
      -150,
      scrollable: scroll,
    );
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tapKey(tester, 'confirm-sale');
    expect(posts, 1);
  });
  testWidgets(
    'ambiguous response shows GET recovery, no confirm or complete action',
    (tester) async {
      view.viewport(tester);
      var posts = 0;
      final controller = await fixture.ready(fixture.store(), (request) {
        if (request.method == 'POST') {
          posts++;
          return auth.jsonResponse({'message': 'server'}, 500);
        }
        return auth.jsonResponse(fixture.detail());
      });
      addTearDown(controller.dispose);
      await mount(tester, controller);
      await tapKey(tester, 'confirm-sale');
      expect(find.text('Chưa xác minh kết quả xác nhận'), findsOneWidget);
      expect(find.byKey(const ValueKey('confirm-sale')), findsNothing);
      expect(find.byKey(const ValueKey('complete-sale')), findsNothing);
      tester.state<ScrollableState>(scroll).position.jumpTo(0);
      await tester.pumpAndSettle();
      await tapKey(tester, 'reload-confirm');
      expect(posts, 1);
    },
  );
  testWidgets('missing snapshot shows error without confirm', (tester) async {
    view.viewport(tester);
    final detail = fixture.detail();
    (detail['items'] as List).first['tax_rate_snapshot'] = null;
    final controller = await fixture.ready(
      fixture.store(),
      (_) => auth.jsonResponse(detail),
    );
    addTearDown(controller.dispose);
    await mount(tester, controller);
    expect(find.byKey(const ValueKey('confirm-sale')), findsNothing);
    expect(find.text('Thiếu hoặc trùng dữ liệu thuế đã chụp.'), findsOneWidget);
  });
  testWidgets(
    'invoice with less collection than sent keeps marker and explains',
    (tester) async {
      view.viewport(tester);
      var sold = false;
      final controller = await fixture.ready(fixture.store(customer: true), (
        request,
      ) {
        if (request.method == 'POST') {
          sold = true;
          return fixture.confirmed();
        }
        return auth.jsonResponse(
          fixture.detail(confirmed: sold, customer: true, paid: '0.00'),
        );
      });
      addTearDown(controller.dispose);
      await mount(tester, controller);
      await tapKey(tester, 'confirm-sale');
      tester.state<ScrollableState>(scroll).position.jumpTo(0);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Tiền đã thu chưa khớp lần xác nhận. Giữ dấu vết để đối chiếu.',
        ),
        findsOneWidget,
      );
      expect(controller.drafts.canComplete, false);
      expect(controller.drafts.canCreate, false);
      expect(find.byKey(const ValueKey('complete-sale')), findsNothing);
    },
  );
  testWidgets(
    'small screen text1.5 keyboard and invoice scroll without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final controller = await fixture.ready(
        fixture.store(customer: true),
        (_) => auth.jsonResponse(fixture.detail(customer: true)),
      );
      addTearDown(controller.dispose);
      await mount(tester, controller);
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('payment-note')),
        120,
        scrollable: scroll,
      );
      await tester.enterText(
        find.byKey(const ValueKey('payment-note')),
        'Ghi chú',
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), null);
    },
  );
}
