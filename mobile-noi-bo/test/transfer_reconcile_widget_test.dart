import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:klcn186_mobile/app.dart';
import 'package:klcn186_mobile/auth/auth_controller.dart';
import 'package:klcn186_mobile/transfers/reconcile_workspace.dart';
import 'package:klcn186_mobile/transfers/transfer_workspace.dart';

import 'auth_test.dart' as auth;
import 'transfer_fixtures.dart' as lookup;
import 'transfer_request_widget_test.dart' as view;
import 'sales_widget_test.dart' as layout;
import 'transfer_reconcile_fixtures.dart' as f;

Future<void> tap(WidgetTester tester, String key) =>
    view.tapVisible(tester, find.byKey(Key(key)));
Finder field(String prefix) => find.byWidgetPredicate(
  (w) =>
      w is TextFormField &&
      w.key is ValueKey<String> &&
      (w.key as ValueKey<String>).value.startsWith(prefix),
);
Future<void> fill(
  WidgetTester tester, {
  List<String> amounts = const ['0.125', '0.250', '0.625'],
  String reason = f.reason,
}) async {
  for (var i = 0; i < 3; i++) {
    final finder = field('reconcile-quantity-${f.lotId}-$i-');
    await view.tapVisible(tester, finder);
    await tester.enterText(finder, amounts[i]);
  }
  final finder = field('reconcile-reason-');
  await view.tapVisible(tester, finder);
  await tester.enterText(finder, reason);
  await tester.pumpAndSettle();
}

Future<void> open(WidgetTester tester, AuthController controller) async {
  await tester.pumpWidget(
    MaterialApp(
      home: TransferReconcileWorkspace(
        controller: controller,
        id: f.transferId,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'mixed allocation explicit review → GET proof → journal; one POST',
    (tester) async {
      layout.viewport(tester);
      var posts = 0;
      Map<String, dynamic>? payload;
      final controller = await f.ready((r) {
        if (r.method == 'POST') {
          posts++;
          payload = jsonDecode(r.body);
          return auth.jsonResponse({'status': 'reconciled'});
        }
        return auth.jsonResponse(
          payload == null ? f.detail() : f.outcome(payload!),
        );
      });
      addTearDown(controller.dispose);
      await open(tester, controller);
      await fill(tester);
      await tap(tester, 'reconcile-transfer');
      expect(posts, 0);
      expect(find.text('Đối soát chênh lệch?'), findsOneWidget);
      expect(find.byKey(const Key('reconcile-reason-preview')), findsOneWidget);
      await tap(tester, 'confirm-transfer-reconcile');
      expect(posts, 1);
      expect(controller.transferReconciliations.state.name, 'verified');
      await tap(tester, 'complete-transfer-reconcile');
      expect(controller.transferReconciliations.journal, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'lookup → reconcile route with shared notifier has no build exception',
    (tester) async {
      layout.viewport(tester);
      Map<String, dynamic>? payload;
      final controller = await f.ready((r) {
        if (r.method == 'POST') {
          payload = jsonDecode(r.body);
          return auth.jsonResponse({'status': 'reconciled'});
        }
        if (r.url.hasQuery) {
          return auth.jsonResponse(
            lookup.page(rows: [lookup.summary(status: 'discrepancy')]),
          );
        }
        return auth.jsonResponse(
          payload == null ? f.detail() : f.outcome(payload!),
        );
      });
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(home: TransferWorkspace(controller: controller)),
      );
      await tester.pumpAndSettle();
      await tap(tester, 'transfer-${f.transferId}');
      await tap(tester, 'review-transfer-reconcile');
      await fill(tester, amounts: ['0', '0', '1']);
      await tap(tester, 'reconcile-transfer');
      await tap(tester, 'confirm-transfer-reconcile');
      expect(controller.transferReconciliations.state.name, 'verified');
      expect(tester.takeException(), isNull);
    },
  );

  for (final mode in ['permission', 'status']) {
    testWidgets('no action for stale $mode', (tester) async {
      layout.viewport(tester);
      var posts = 0;
      final controller = await f.ready((r) {
        if (r.method == 'POST') posts++;
        return auth.jsonResponse(
          f.detail(
            permission: mode != 'permission',
            status: mode == 'status' ? 'reconciled' : 'discrepancy',
          ),
        );
      });
      addTearDown(controller.dispose);
      await open(tester, controller);
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reconcile-transfer')), findsNothing);
      expect(posts, 0);
    });
  }

  testWidgets(
    'reason and conservation validation; valid review cancel is read-only',
    (tester) async {
      layout.viewport(tester);
      var posts = 0;
      final controller = await f.ready((r) {
        if (r.method == 'POST') posts++;
        return auth.jsonResponse(f.detail());
      });
      addTearDown(controller.dispose);
      await open(tester, controller);
      for (final amounts in [
        ['0', '0', '0'],
        ['-1', '0', '2'],
        ['1.0001', '0', '0'],
        ['1.001', '0', '0'],
      ]) {
        await fill(tester, amounts: amounts);
        await tap(tester, 'reconcile-transfer');
        expect(find.byKey(const Key('reconcile-validation')), findsOneWidget);
        expect(posts, 0);
      }
      await fill(tester, reason: ' x ');
      await tap(tester, 'reconcile-transfer');
      expect(find.byKey(const Key('reconcile-validation')), findsOneWidget);
      await fill(tester);
      await tap(tester, 'reconcile-transfer');
      await view.tapVisible(tester, find.text('Quay lại'));
      expect(posts, 0);
      expect(controller.transferReconciliations.attempt, isNull);
    },
  );

  testWidgets('unknown has reload only, never presents resend', (tester) async {
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
    await open(tester, controller);
    await fill(tester);
    await tap(tester, 'reconcile-transfer');
    await tap(tester, 'confirm-transfer-reconcile');
    expect(controller.transferReconciliations.state.name, 'unknown');
    expect(find.byKey(const Key('reconcile-transfer')), findsNothing);
    await tap(tester, 'reload-transfer-reconcile');
    expect(posts, 1);
  });

  testWidgets('home storage recovery stays locked', (tester) async {
    layout.viewport(tester);
    final store = f.ReconcileMemoryStore()..alwaysFail = true;
    final controller = await f.ready(
      (r) => auth.jsonResponse(f.detail()),
      store: store,
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(MobileApp(controller: controller));
    await tester.pumpAndSettle();
    await tap(tester, 'open-transfer-reconcile');
    expect(controller.transferReconciliations.state.name, 'storageBlocked');
    expect(find.byKey(const Key('reconcile-transfer')), findsNothing);
    await tap(tester, 'reload-transfer-reconcile');
    expect(tester.takeException(), isNull);
  });

  testWidgets('offline detail reload recovers without POST', (tester) async {
    layout.viewport(tester);
    var offline = true, posts = 0;
    final controller = await f.ready((r) {
      if (r.method == 'POST') posts++;
      if (offline) throw http.ClientException('offline');
      return auth.jsonResponse(f.detail());
    });
    addTearDown(controller.dispose);
    await open(tester, controller);
    expect(find.byKey(const Key('transfer-reconcile-error')), findsOneWidget);
    offline = false;
    await tap(tester, 'reload-transfer-reconcile');
    expect(controller.transferReconciliations.canReconcile, isTrue);
    expect(posts, 0);
  });

  testWidgets(
    'session change in confirmation hides details and blocks submit',
    (tester) async {
      layout.viewport(tester);
      var posts = 0;
      final controller = await f.ready((r) {
        if (r.method == 'POST') posts++;
        return auth.jsonResponse(f.detail());
      });
      addTearDown(controller.dispose);
      await open(tester, controller);
      await fill(tester);
      await tap(tester, 'reconcile-transfer');
      controller.changeScope();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('confirm-transfer-reconcile')), findsNothing);
      expect(find.textContaining('Lý do: ${f.reason}'), findsNothing);
      expect(posts, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '320px/text1.5/keyboard three allocations, reason and dialog scroll',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      Map<String, dynamic>? payload;
      var posts = 0;
      final controller = await f.ready((r) {
        if (r.method == 'POST') {
          posts++;
          payload = jsonDecode(r.body);
          return auth.jsonResponse({'status': 'reconciled'});
        }
        return auth.jsonResponse(
          payload == null ? f.detail() : f.outcome(payload!),
        );
      });
      addTearDown(controller.dispose);
      await open(tester, controller);
      await fill(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      await tester.pumpAndSettle();
      await tap(tester, 'reconcile-transfer');
      final scroll = find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.byKey(const Key('reconcile-reason-preview')),
        100,
        scrollable: scroll,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tap(tester, 'confirm-transfer-reconcile');
      expect(posts, 1);
      tester.view.viewInsets = const FakeViewPadding();
      await tester.pumpAndSettle();
      await tap(tester, 'complete-transfer-reconcile');
      expect(controller.transferReconciliations.journal, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
}
