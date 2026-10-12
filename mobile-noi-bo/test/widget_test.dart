import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klcn186_mobile/app.dart';
import 'package:klcn186_mobile/auth/auth_controller.dart';

import 'auth_test.dart' as support;

void main() {
  testWidgets('login validation, scope selection, workspace and logout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = AuthController(
      support.testApi((request) {
        if (request.url.path == '/api/mobile/login') {
          return support.jsonResponse({
            ...support.validSession().toJson(),
            'token_type': 'Bearer',
          });
        }
        return support.jsonResponse(
          request.url.path == '/api/me' ? support.profileJson() : {},
        );
      }),
      support.MemoryStore(),
    );
    addTearDown(controller.dispose);
    await controller.restore();
    await tester.pumpWidget(MobileApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Đăng nhập'));
    await tester.pumpAndSettle();
    expect(find.text('Nhập tên đăng nhập.'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('username')), 'nhanvien');
    await tester.enterText(find.byKey(const Key('password')), 'password');
    await tester.ensureVisible(find.text('Đăng nhập'));
    await tester.tap(find.text('Đăng nhập'));
    await tester.pumpAndSettle();
    expect(find.text('Chọn nơi làm việc'), findsOneWidget);
    await tester.tap(find.text('Chi nhánh Thủ Đức'));
    await tester.pumpAndSettle();
    expect(find.text('Không gian làm việc'), findsOneWidget);
    expect(find.textContaining('chưa được mở'), findsOneWidget);
    await tester.tap(find.byTooltip('Đăng xuất'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('password')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('small viewport and enlarged text do not overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = AuthController(
      support.testApi((_) => support.jsonResponse(support.profileJson())),
      support.MemoryStore(),
    );
    addTearDown(controller.dispose);
    await controller.restore();
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(MobileApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Đăng nhập'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
