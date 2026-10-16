import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:klcn186_mobile/app.dart';
import 'package:klcn186_mobile/transfers/decision_models.dart';
import 'package:klcn186_mobile/transfers/decision_workspace.dart';
import 'package:klcn186_mobile/transfers/transfer_workspace.dart';

import 'auth_test.dart' as auth;
import 'transfer_fixtures.dart' as lookup;
import 'transfer_request_widget_test.dart' as view;
import 'sales_widget_test.dart' as layout;
import 'transfer_decision_fixtures.dart' as f;

Future<void> tap(WidgetTester tester, String key) async {
  await view.tapVisible(tester, find.byKey(Key(key)));
}

void main() {
  for (final action in TransferAction.values) {
    testWidgets(
      'lookup → ${action.name} review → GET permission → POST once → GET proof → journal, no build notification',
      (tester) async {
        layout.viewport(tester);
        var status = 'requested', posts = 0;
        final controller = await f.ready((r) {
          if (r.method == 'POST') {
            posts++;
            status = action == TransferAction.approve ? 'approved' : 'rejected';
            return auth.jsonResponse({'status': status});
          }
          if (r.url.hasQuery) {
            return auth.jsonResponse(
              lookup.page(rows: [lookup.summary(status: 'requested')]),
            );
          }
          return auth.jsonResponse(
            f.detail(
              status: status,
              reason: status == 'rejected' ? 'Thiếu kế hoạch nhận' : null,
            ),
          );
        });
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          MaterialApp(home: TransferWorkspace(controller: controller)),
        );
        await tester.pumpAndSettle();
        await tap(tester, 'transfer-${f.transferId}');
        await tap(tester, 'review-transfer-decision');
        expect(find.text('Kiểm tra phiếu trước khi xử lý'), findsOneWidget);
        if (action == TransferAction.reject) {
          await tester.enterText(
            find.byKey(const Key('transfer-rejection-reason')),
            'Thiếu kế hoạch nhận',
          );
        }
        await tap(tester, '${action.name}-transfer');
        expect(posts, 0);
        expect(find.text('Xác nhận'), findsOneWidget);
        await tap(tester, 'confirm-transfer-decision');
        expect(posts, 1);
        expect(
          find.text('Đã xác minh trạng thái và người thực hiện từ phiếu.'),
          findsOneWidget,
        );
        expect(find.byKey(const Key('approve-transfer')), findsNothing);
        expect(find.byKey(const Key('reject-transfer')), findsNothing);
        await tap(tester, 'complete-transfer-decision');
        expect(find.text('Dấu vết đã lưu (1)'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final state in ['self', 'denied', 'approved']) {
    testWidgets('$state cannot show approval/rejection actions', (
      tester,
    ) async {
      layout.viewport(tester);
      final controller = await f.ready(
        (r) => auth.jsonResponse(
          f.detail(
            creator: state == 'self' ? f.userId : '7',
            permission: state != 'denied',
            status: state == 'approved' ? 'approved' : 'requested',
          ),
        ),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: TransferDecisionWorkspace(
            controller: controller,
            id: f.transferId,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('approve-transfer')), findsNothing);
      expect(find.byKey(const Key('reject-transfer')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'cancel dialog makes no POST; loss of response only GET recovery',
    (tester) async {
      layout.viewport(tester);
      var posts = 0;
      final controller = await f.ready((r) {
        if (r.method == 'POST') {
          posts++;
          throw http.ClientException('fixture loss');
        }
        return auth.jsonResponse(f.detail());
      });
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: TransferDecisionWorkspace(
            controller: controller,
            id: f.transferId,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, 'approve-transfer');
      await tester.tap(find.text('Quay lại'));
      await tester.pumpAndSettle();
      expect(posts, 0);
      await tap(tester, 'approve-transfer');
      await tap(tester, 'confirm-transfer-decision');
      expect(find.textContaining('Chưa xác định kết quả.'), findsOneWidget);
      await tap(tester, 'reload-transfer-decision');
      expect(find.byKey(const Key('approve-transfer')), findsNothing);
      expect(find.byKey(const Key('complete-transfer-decision')), findsNothing);
      expect(posts, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'storage blocked recovery and empty journal on home route, no API mutation',
    (tester) async {
      layout.viewport(tester);
      final store = f.DecisionMemoryStore()..failReadAt = 1;
      var requests = 0;
      final controller = await f.ready((r) {
        requests++;
        return auth.jsonResponse(f.detail());
      }, store: store);
      addTearDown(controller.dispose);
      await tester.pumpWidget(MobileApp(controller: controller));
      await tester.pumpAndSettle();
      await tap(tester, 'open-transfer-decision');
      expect(find.textContaining('Bộ nhớ chưa được xác minh.'), findsOneWidget);
      expect(find.byKey(const Key('approve-transfer')), findsNothing);
      store.failReadAt = null;
      await tap(tester, 'reload-transfer-decision');
      expect(find.textContaining('Chưa có thao tác đang chờ.'), findsOneWidget);
      expect(requests, 0);
    },
  );

  testWidgets(
    'GET offline/recovery and session change hides detail and actions',
    (tester) async {
      layout.viewport(tester);
      var offline = true;
      final controller = await f.ready((r) {
        if (offline) throw http.ClientException('offline fixture');
        return auth.jsonResponse(f.detail());
      });
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: TransferDecisionWorkspace(
            controller: controller,
            id: f.transferId,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('transfer-decision-error')), findsOneWidget);
      offline = false;
      await tap(tester, 'reload-transfer-decision');
      expect(find.byKey(const Key('approve-transfer')), findsOneWidget);
      controller.changeScope();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('approve-transfer')), findsNothing);
      expect(
        find.textContaining('Phiên hoặc chi nhánh đã đổi.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'scope change while review dialog open hides previous transfer and disables confirmation',
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
          home: TransferDecisionWorkspace(
            controller: controller,
            id: f.transferId,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, 'approve-transfer');
      controller.changeScope();
      await tester.pumpAndSettle();
      expect(find.text('Phiên hoặc quyền đã đổi'), findsOneWidget);
      expect(find.byKey(const Key('confirm-transfer-decision')), findsNothing);
      await tester.tap(find.text('Đóng'));
      await tester.pumpAndSettle();
      expect(posts, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '320px text1.5 keyboard, reject review and journal scroll without overflow',
    (tester) async {
      layout.viewport(tester, small: true);
      var status = 'requested';
      final controller = await f.ready((r) {
        if (r.method == 'POST') {
          status = 'rejected';
          return auth.jsonResponse({'status': status});
        }
        return auth.jsonResponse(
          f.detail(
            status: status,
            reason: status == 'rejected' ? 'Không đủ chỗ nhận' : null,
          ),
        );
      });
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: TransferDecisionWorkspace(
            controller: controller,
            id: f.transferId,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tap(tester, 'transfer-rejection-reason');
      tester.view.viewInsets = const FakeViewPadding(bottom: 200);
      await tester.enterText(
        find.byKey(const Key('transfer-rejection-reason')),
        'Không đủ chỗ nhận',
      );
      await tap(tester, 'reject-transfer');
      expect(tester.takeException(), isNull);
      await tap(tester, 'confirm-transfer-decision');
      expect(tester.takeException(), isNull);
      await tap(tester, 'complete-transfer-decision');
      expect(controller.transferDecisions.journal, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );
}
