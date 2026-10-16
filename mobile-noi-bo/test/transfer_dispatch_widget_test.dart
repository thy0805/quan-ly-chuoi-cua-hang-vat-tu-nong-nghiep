import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:klcn186_mobile/app.dart';
import 'package:klcn186_mobile/transfers/dispatch_workspace.dart';
import 'package:klcn186_mobile/transfers/transfer_workspace.dart';

import 'auth_test.dart' as auth;
import 'transfer_fixtures.dart' as lookup;
import 'transfer_request_widget_test.dart' as view;
import 'sales_widget_test.dart' as layout;
import 'transfer_dispatch_fixtures.dart' as f;

Future<void> tap(WidgetTester tester, String key) async {
  await view.tapVisible(tester, find.byKey(Key(key)));
}

Finder quantity() => find.byType(TextFormField);

void main() {
  testWidgets(
    'lookup → dispatch review → explicit confirm → GET proof → journal; no build notify',
    (tester) async {
      layout.viewport(tester);
      var status = 'approved', posts = 0;
      final controller = await f.ready((r) {
        if (r.method == 'POST') {
          posts++;
          status = 'dispatched';
          return auth.jsonResponse({'status': status});
        }
        if (r.url.hasQuery) {
          return auth.jsonResponse(
            lookup.page(rows: [lookup.summary(status: 'approved')]),
          );
        }
        return auth.jsonResponse(f.detail(status: status, quantity: '1.250'));
      });
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(home: TransferWorkspace(controller: controller)),
      );
      await tester.pumpAndSettle();
      await tap(tester, 'transfer-${f.transferId}');
      await tap(tester, 'review-transfer-dispatch');
      await tester.scrollUntilVisible(
        quantity(),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(quantity(), '1.250');
      await tap(tester, 'dispatch-transfer');
      expect(find.text('Xuất hàng và giảm tồn nguồn?'), findsOneWidget);
      expect(posts, 0);
      await tap(tester, 'confirm-transfer-dispatch');
      expect(posts, 1);
      expect(
        find.textContaining('Đã đối chiếu xuất kho từ phiếu:'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('dispatch-transfer')), findsNothing);
      await tap(tester, 'complete-transfer-dispatch');
      await tester.scrollUntilVisible(
        find.text('Dấu vết xuất kho đã lưu (1)'),
        140,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Dấu vết xuất kho đã lưu (1)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final scenario in ['requested', 'denied', 'destination']) {
    testWidgets('$scenario has no dispatch action or input', (tester) async {
      layout.viewport(tester);
      final controller = await f.ready((r) {
        final data = f.detail(
          status: scenario == 'requested' ? 'requested' : 'approved',
          permission: scenario != 'denied',
        );
        if (scenario == 'destination') {
          data['data']['from_branch_id'] = '2';
          data['data']['to_branch_id'] = f.branchId;
        }
        return auth.jsonResponse(data);
      });
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: TransferDispatchWorkspace(
            controller: controller,
            id: f.transferId,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('dispatch-transfer')), findsNothing);
      expect(quantity(), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'bad quantities are visible errors; cancel sends no POST; unknown only reloads',
    (tester) async {
      layout.viewport(tester);
      var posts = 0;
      final controller = await f.ready((r) {
        if (r.method == 'POST') {
          posts++;
          throw http.ClientException('lost');
        }
        return auth.jsonResponse(f.detail());
      });
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: TransferDispatchWorkspace(
            controller: controller,
            id: f.transferId,
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final value in ['0', '1.0001', '3']) {
        await tester.scrollUntilVisible(
          quantity(),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.enterText(quantity(), value);
        await tap(tester, 'dispatch-transfer');
        expect(find.byKey(const Key('dispatch-validation')), findsOneWidget);
        expect(posts, 0);
      }
      await tester.scrollUntilVisible(
        quantity(),
        -160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(quantity(), '1');
      await tap(tester, 'dispatch-transfer');
      await tester.tap(find.text('Quay lại'));
      await tester.pumpAndSettle();
      expect(posts, 0);
      await tap(tester, 'dispatch-transfer');
      await tap(tester, 'confirm-transfer-dispatch');
      expect(
        find.textContaining('Chưa xác định kết quả xuất.'),
        findsOneWidget,
      );
      await tap(tester, 'reload-transfer-dispatch');
      expect(posts, 1);
      expect(find.byKey(const Key('dispatch-transfer')), findsNothing);
      expect(find.byKey(const Key('complete-transfer-dispatch')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'home recovery route shows storage blocked then safe empty state',
    (tester) async {
      layout.viewport(tester);
      final store = f.DispatchMemoryStore()..alwaysFail = true;
      var reads = 0;
      final controller = await f.ready((r) {
        reads++;
        return auth.jsonResponse(f.detail());
      }, store: store);
      addTearDown(controller.dispose);
      await tester.pumpWidget(MobileApp(controller: controller));
      await tester.pumpAndSettle();
      await tap(tester, 'open-transfer-dispatch');
      expect(find.textContaining('Bộ nhớ chưa được xác minh.'), findsOneWidget);
      store.alwaysFail = false;
      await tap(tester, 'reload-transfer-dispatch');
      expect(
        find.textContaining('Chưa có thao tác xuất đang chờ.'),
        findsOneWidget,
      );
      expect(reads, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('offline and reload recover detail without any POST', (
    tester,
  ) async {
    layout.viewport(tester);
    var offline = true, posts = 0;
    final controller = await f.ready((r) {
      if (r.method == 'POST') posts++;
      if (offline) throw http.ClientException('offline');
      return auth.jsonResponse(f.detail());
    });
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: TransferDispatchWorkspace(
          controller: controller,
          id: f.transferId,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('transfer-dispatch-error')), findsOneWidget);
    offline = false;
    await tap(tester, 'reload-transfer-dispatch');
    await tester.scrollUntilVisible(
      quantity(),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(quantity(), findsOneWidget);
    expect(posts, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'scope change while confirmation open hides old data and button',
    (tester) async {
      layout.viewport(tester);
      var posts = 0;
      final controller = await f.ready((r) {
        if (r.method == 'POST') posts++;
        return auth.jsonResponse(f.detail());
      });
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: TransferDispatchWorkspace(
            controller: controller,
            id: f.transferId,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, 'dispatch-transfer');
      controller.changeScope();
      await tester.pumpAndSettle();
      expect(find.text('Phiên hoặc quyền đã đổi'), findsOneWidget);
      expect(find.byKey(const Key('confirm-transfer-dispatch')), findsNothing);
      await tester.tap(find.text('Đóng'));
      await tester.pumpAndSettle();
      expect(posts, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '320px text1.5 keyboard; confirmation scroll and journal without overflow',
    (tester) async {
      layout.viewport(tester, small: true);
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      var status = 'approved';
      final controller = await f.ready((r) {
        if (r.method == 'POST') {
          status = 'dispatched';
          return auth.jsonResponse({'status': status});
        }
        return auth.jsonResponse(f.detail(status: status));
      });
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: TransferDispatchWorkspace(
            controller: controller,
            id: f.transferId,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        quantity(),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(quantity(), '2.125');
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await tap(tester, 'dispatch-transfer');
      expect(tester.takeException(), isNull);
      await tap(tester, 'confirm-transfer-dispatch');
      expect(tester.takeException(), isNull);
      tester.view.viewInsets = const FakeViewPadding();
      await tester.pumpAndSettle();
      await tap(tester, 'complete-transfer-dispatch');
      await tester.scrollUntilVisible(
        find.text('Dấu vết xuất kho đã lưu (1)'),
        140,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Dấu vết xuất kho đã lưu (1)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
