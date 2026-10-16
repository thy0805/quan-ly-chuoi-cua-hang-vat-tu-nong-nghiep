import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:klcn186_mobile/app.dart';
import 'package:klcn186_mobile/auth/auth_controller.dart';

import 'auth_test.dart' as auth;
import 'sales_widget_test.dart' as view;
import 'transfer_request_fixtures.dart' as f;

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.pumpAndSettle();
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      180,
      maxScrolls: 30,
      scrollable: find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> open(WidgetTester tester, AuthController controller) async {
  await tester.pumpWidget(MobileApp(controller: controller));
  await tester.pumpAndSettle();
  await tapVisible(tester, find.byKey(const Key('open-transfer-request')));
}

Future<void> fill(WidgetTester tester, {String qty = '2.125'}) async {
  await tapVisible(tester, find.byType(DropdownButtonFormField<String>).first);
  await tester.tap(
    find.text('Chi nhánh ${f.branchId} · Kho 11 vật tư nông nghiệp').last,
  );
  await tester.pumpAndSettle();
  await tapVisible(tester, find.byType(DropdownButtonFormField<String>).at(1));
  await tester.tap(find.text('Chi nhánh 2 · Kho 12 vật tư nông nghiệp').last);
  await tester.pumpAndSettle();
  await tapVisible(tester, find.byKey(const Key('add-transfer-lot')));
  await tester.enterText(
    find.widgetWithText(TextField, 'Tìm vật tư hoặc lô'),
    'NPK',
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('pick-transfer-${f.lotId}')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('transfer-qty-${f.lotId}')),
    qty,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'home → select → review → single POST → verified detail → journal; no warehouse action',
    (tester) async {
      view.viewport(tester);
      final requests = <http.Request>[];
      final controller = await f.ready((r) {
        requests.add(r);
        return auth.jsonResponse(
          r.url.path.endsWith('options')
              ? f.options()
              : r.method == 'POST'
              ? {'id': f.transferId}
              : f.detail(),
          r.method == 'POST' ? 201 : 200,
        );
      }, store: f.TransferMemoryStore());
      addTearDown(controller.dispose);
      await open(tester, controller);
      await fill(tester);
      expect(requests.where((r) => r.method == 'POST'), isEmpty);
      await tapVisible(tester, find.byKey(const Key('review-transfer')));
      expect(find.text('Xem lại trước khi gửi'), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('submit-transfer')));
      expect(find.textContaining('Đã lưu mã phiếu'), findsOneWidget);
      expect(find.text('Chờ duyệt'), findsOneWidget);
      expect(find.text('Duyệt phiếu'), findsNothing);
      expect(find.text('Xuất kho'), findsNothing);
      await tapVisible(tester, find.byKey(const Key('complete-transfer')));
      expect(find.text('Dấu vết đã lưu (1)'), findsOneWidget);
      expect(controller.transfers.canCreate, true);
      expect(requests.where((r) => r.method == 'POST').length, 1);
      expect(
        requests.every((r) => r.url.path.startsWith('/api/stock-transfers')),
        true,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'UI blocks excessive quantity, duplicate lot, remove and reload resets form',
    (tester) async {
      view.viewport(tester);
      var posts = 0;
      final controller = await f.ready((r) {
        if (r.method == 'POST') posts++;
        return auth.jsonResponse(f.options());
      }, store: f.TransferMemoryStore());
      addTearDown(controller.dispose);
      await open(tester, controller);
      await fill(tester, qty: '11');
      await tapVisible(tester, find.byKey(const Key('review-transfer')));
      expect(find.textContaining('Số lượng phải lớn hơn'), findsOneWidget);
      expect(find.byKey(const Key('submit-transfer')), findsNothing);
      await tapVisible(tester, find.byKey(const Key('add-transfer-lot')));
      expect(
        find.byKey(const ValueKey('pick-transfer-${f.lotId}')),
        findsNothing,
      );
      expect(find.text('Không còn lô phù hợp để thêm.'), findsOneWidget);
      await tester.tap(find.text('Đóng'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Bỏ lô'));
      expect(find.text('Chọn lô (0/50)'), findsOneWidget);
      await tapVisible(tester, find.text('Tải lại kho/lô và làm mới form'));
      expect(posts, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('changing source clears destination and selected lots', (
    tester,
  ) async {
    view.viewport(tester);
    final controller = await f.ready((r) {
      final json = f.options();
      (json['sources'] as List).add({
        'id': '15',
        'branch_id': f.branchId,
        'chain_id': '1',
        'name': 'Kho phụ',
        'branch_name': 'Chi nhánh hiện tại',
      });
      return auth.jsonResponse(json);
    }, store: f.TransferMemoryStore());
    addTearDown(controller.dispose);
    await open(tester, controller);
    await fill(tester);
    await tapVisible(
      tester,
      find.byType(DropdownButtonFormField<String>).first,
    );
    await tester.tap(find.text('Chi nhánh hiện tại · Kho phụ').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('transfer-qty-${f.lotId}')), findsNothing);
    expect(find.text('Chọn lô (0/50)'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'empty options reflect no request permission, not invented owner permission',
    (tester) async {
      view.viewport(tester);
      final controller = await f.ready(
        (r) =>
            auth.jsonResponse({'sources': [], 'destinations': [], 'lots': []}),
        store: f.TransferMemoryStore(),
      );
      addTearDown(controller.dispose);
      await open(tester, controller);
      expect(
        find.textContaining('Không có kho nguồn được phép'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('review-transfer')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('options offline and recovery remain GET only', (tester) async {
    view.viewport(tester);
    var offline = true;
    final controller = await f.ready((r) {
      expect(r.method, 'GET');
      if (offline) throw http.ClientException('offline');
      return auth.jsonResponse(f.options());
    }, store: f.TransferMemoryStore());
    addTearDown(controller.dispose);
    await open(tester, controller);
    expect(find.text('Chưa tải được danh sách kho và lô.'), findsOneWidget);
    offline = false;
    await tapVisible(tester, find.text('Tải lại danh sách'));
    expect(find.byKey(const Key('review-transfer')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'UNKNOWN has no resend or complete action after lost POST response',
    (tester) async {
      view.viewport(tester);
      var posts = 0;
      final controller = await f.ready((r) {
        if (r.method == 'POST') {
          posts++;
          throw http.ClientException('lost');
        }
        return auth.jsonResponse(f.options());
      }, store: f.TransferMemoryStore());
      addTearDown(controller.dispose);
      await open(tester, controller);
      await fill(tester);
      await tapVisible(tester, find.byKey(const Key('review-transfer')));
      await tapVisible(tester, find.byKey(const Key('submit-transfer')));
      expect(find.textContaining('Chưa xác định kết quả.'), findsOneWidget);
      expect(find.byKey(const Key('submit-transfer')), findsNothing);
      expect(find.byKey(const Key('complete-transfer')), findsNothing);
      await tapVisible(tester, find.text('Đọc lại dấu vết đã lưu'));
      expect(posts, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'scope change closes route and lot picker, discards old selection',
    (tester) async {
      view.viewport(tester);
      final controller = await f.ready(
        (r) => auth.jsonResponse(f.options()),
        store: f.TransferMemoryStore(),
      );
      addTearDown(controller.dispose);
      await open(tester, controller);
      await fill(tester);
      await tapVisible(tester, find.byKey(const Key('add-transfer-lot')));
      controller.changeScope();
      await tester.pumpAndSettle();
      expect(find.text('Chọn nơi làm việc'), findsOneWidget);
      expect(find.text('Tìm vật tư hoặc lô'), findsNothing);
      expect(controller.transfers.options, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    '320px text1.5 form, picker, review and detail scroll without overflow',
    (tester) async {
      view.viewport(tester, small: true);
      final controller = await f.ready(
        (r) => auth.jsonResponse(
          r.url.path.endsWith('options')
              ? f.options()
              : r.method == 'POST'
              ? {'id': f.transferId}
              : f.detail(),
          r.method == 'POST' ? 201 : 200,
        ),
        store: f.TransferMemoryStore(),
      );
      addTearDown(controller.dispose);
      await open(tester, controller);
      await fill(tester);
      await tapVisible(tester, find.byKey(const Key('review-transfer')));
      expect(tester.takeException(), isNull);
      await tapVisible(tester, find.byKey(const Key('submit-transfer')));
      expect(find.text('Chờ duyệt'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
