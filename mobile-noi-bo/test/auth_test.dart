import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:klcn186_mobile/auth/api_client.dart';
import 'package:klcn186_mobile/auth/auth_controller.dart';
import 'package:klcn186_mobile/auth/models.dart';
import 'package:klcn186_mobile/auth/session_store.dart';

class MemoryStore implements SessionStore {
  Session? session;
  bool failWrite = false;
  bool failClear = false;
  String? lastNamespace;

  @override
  Future<Session?> read(String namespace) async => session;

  @override
  Future<void> write(String namespace, Session value) async {
    if (failWrite) throw StateError('storage unavailable');
    lastNamespace = namespace;
    session = value;
  }

  @override
  Future<void> clear(String namespace) async {
    if (failClear) throw StateError('storage unavailable');
    session = null;
  }
}

Session validSession({String? branchId}) => Session(
  token: 'test-token',
  expiresAt: DateTime.now().add(const Duration(days: 1)),
  branchId: branchId,
);

Map<String, dynamic> profileJson({bool withBranch = true}) => {
  'user': {'id': '9007199254740993', 'username': 'nhanvien'},
  'branches': [
    if (withBranch)
      {
        'id': '9007199254740995',
        'chain_id': '1',
        'code': 'CN01',
        'name': 'Chi nhánh Thủ Đức',
      },
  ],
  'chains': [
    {'id': '1', 'name': 'Vật tư nông nghiệp'},
  ],
};

http.Response jsonResponse(Map<String, dynamic> data, [int status = 200]) =>
    http.Response(
      jsonEncode(data),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

ApiClient testApi(
  FutureOr<http.Response> Function(http.Request) handler, {
  Duration? timeout,
}) => ApiClient(
  baseUrl: 'https://api.example.test',
  client: MockClient((request) async => handler(request)),
  timeout: timeout ?? const Duration(seconds: 20),
);

void main() {
  test(
    'login, current profile, string IDs, scope persistence and remote logout',
    () async {
      final requests = <http.Request>[];
      final store = MemoryStore();
      final controller = AuthController(
        testApi((request) {
          requests.add(request);
          if (request.url.path == '/api/mobile/login') {
            expect(request.method, 'POST');
            expect(request.headers['Authorization'], isNull);
            expect(jsonDecode(request.body)['username'], 'nhanvien');
            return jsonResponse({
              ...validSession().toJson(),
              'token_type': 'Bearer',
            });
          }
          expect(request.headers['Authorization'], 'Bearer test-token');
          return jsonResponse(
            request.url.path == '/api/me' ? profileJson() : {'message': 'ok'},
          );
        }),
        store,
      );
      addTearDown(controller.dispose);
      await controller.restore();
      expect(controller.stage, AuthStage.signedOut);
      await controller.login(' nhanvien ', 'password');
      expect(controller.stage, AuthStage.chooseScope);
      await controller.chooseBranch('9007199254740995');
      expect(controller.stage, AuthStage.ready);
      expect(controller.branch!.id, '9007199254740995');
      expect(store.session!.branchId, '9007199254740995');
      expect(store.lastNamespace, 'https://api.example.test');
      expect(store.session!.toJson().containsKey('password'), isFalse);
      await controller.logout();
      expect(controller.stage, AuthStage.signedOut);
      expect(store.session, isNull);
      expect(
        requests.where((r) => r.url.path == '/api/mobile/login').length,
        1,
      );
      expect(
        requests.where((r) => r.url.path == '/api/mobile/logout').length,
        1,
      );
    },
  );

  test(
    'restore checks remote permissions and removes revoked token on 401',
    () async {
      final store = MemoryStore()
        ..session = validSession(branchId: '9007199254740995');
      var status = 200;
      final controller = AuthController(
        testApi((_) => jsonResponse(profileJson(), status)),
        store,
      );
      addTearDown(controller.dispose);
      await controller.restore();
      expect(controller.stage, AuthStage.ready);
      status = 401;
      await controller.refresh();
      expect(controller.stage, AuthStage.signedOut);
      expect(store.session, isNull);
      expect(controller.profile, isNull);
    },
  );

  test(
    'expired local session clears without requesting protected API',
    () async {
      final store = MemoryStore()
        ..session = Session(
          token: 'expired',
          expiresAt: DateTime.now().subtract(const Duration(days: 1)),
        );
      var calls = 0;
      final controller = AuthController(
        testApi((_) {
          calls++;
          return jsonResponse(profileJson());
        }),
        store,
      );
      addTearDown(controller.dispose);
      await controller.restore();
      expect(controller.stage, AuthStage.signedOut);
      expect(store.session, isNull);
      expect(calls, 0);
    },
  );

  test(
    '403 hides workspace, permits logout, does not trust saved scope',
    () async {
      final store = MemoryStore()
        ..session = validSession(branchId: '9007199254740995');
      final controller = AuthController(
        testApi(
          (request) =>
              jsonResponse({}, request.url.path == '/api/me' ? 403 : 200),
        ),
        store,
      );
      addTearDown(controller.dispose);
      await controller.restore();
      expect(controller.stage, AuthStage.unavailable);
      expect(store.session, isNotNull);
      await controller.logout();
      expect(controller.stage, AuthStage.signedOut);
    },
  );

  test(
    'network failure does not silently logout or auto retry a POST',
    () async {
      var calls = 0;
      final store = MemoryStore()..session = validSession();
      final controller = AuthController(
        testApi((_) {
          calls++;
          throw http.ClientException('offline');
        }),
        store,
      );
      addTearDown(controller.dispose);
      await controller.restore();
      expect(controller.stage, AuthStage.unavailable);
      await controller.logout();
      expect(controller.stage, AuthStage.unavailable);
      expect(controller.message, contains('Chưa đăng xuất'));
      expect(store.session, isNotNull);
      expect(calls, 2);
    },
  );

  test('empty or removed scope never opens previous branch', () async {
    final store = MemoryStore()..session = validSession(branchId: 'old-branch');
    var empty = false;
    final controller = AuthController(
      testApi((_) => jsonResponse(profileJson(withBranch: !empty))),
      store,
    );
    addTearDown(controller.dispose);
    await controller.restore();
    expect(controller.stage, AuthStage.chooseScope);
    expect(controller.branch, isNull);
    await controller.chooseBranch('not-permitted');
    expect(controller.stage, AuthStage.unavailable);
    empty = true;
    await controller.refresh();
    expect(controller.stage, AuthStage.unavailable);
  });

  test('secure storage write failure revokes newly issued token', () async {
    var logoutCalls = 0;
    final store = MemoryStore()..failWrite = true;
    final controller = AuthController(
      testApi((request) {
        if (request.url.path == '/api/mobile/logout') {
          logoutCalls++;
          return jsonResponse({});
        }
        return jsonResponse({
          ...validSession().toJson(),
          'token_type': 'Bearer',
        });
      }),
      store,
    );
    addTearDown(controller.dispose);
    await controller.restore();
    await controller.login('staff', 'password');
    expect(controller.stage, AuthStage.signedOut);
    expect(store.session, isNull);
    expect(logoutCalls, 1);
  });

  test(
    'logout storage failure is reported, not called a successful logout',
    () async {
      final store = MemoryStore()
        ..session = validSession()
        ..failClear = true;
      final controller = AuthController(
        testApi(
          (request) =>
              jsonResponse(request.url.path == '/api/me' ? profileJson() : {}),
        ),
        store,
      );
      addTearDown(controller.dispose);
      await controller.restore();
      await controller.logout();
      expect(controller.stage, AuthStage.unavailable);
      expect(controller.message, contains('bộ nhớ bảo mật'));
    },
  );

  test('rapid login taps cannot send duplicate login POST', () async {
    final pending = Completer<http.Response>();
    var calls = 0;
    final controller = AuthController(
      testApi((request) {
        if (request.method == 'POST') {
          calls++;
          return pending.future;
        }
        return jsonResponse(profileJson());
      }),
      MemoryStore(),
    );
    addTearDown(controller.dispose);
    await controller.restore();
    final first = controller.login('staff', 'password');
    await controller.login('staff', 'password');
    pending.complete(
      jsonResponse({...validSession().toJson(), 'token_type': 'Bearer'}),
    );
    await first;
    expect(calls, 1);
  });

  test('timeout sends once and requires intentional retry', () async {
    var calls = 0;
    final api = testApi((_) {
      calls++;
      return Completer<http.Response>().future;
    }, timeout: const Duration(milliseconds: 1));
    addTearDown(api.close);
    await expectLater(
      api.login('staff', 'password'),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.message,
          'message',
          contains('không được tự gửi lại'),
        ),
      ),
    );
    expect(calls, 1);
  });

  test(
    'redirect cannot forward credential; errors and malformed JSON are safe',
    () async {
      for (final status in [302, 401, 403, 422, 429, 500]) {
        final api = testApi((request) {
          expect(request.followRedirects, isFalse);
          return http.Response('sensitive server body', status);
        });
        await expectLater(
          api.login('staff', 'password'),
          throwsA(
            isA<ApiFailure>().having(
              (e) => e.message,
              'message',
              isNot(contains('sensitive')),
            ),
          ),
        );
        api.close();
      }
      final api = testApi((_) => http.Response('not json', 200));
      addTearDown(api.close);
      await expectLater(
        api.login('staff', 'password'),
        throwsA(isA<ApiFailure>()),
      );
    },
  );

  test(
    'API configuration rejects insecure non-local or release HTTP and credentials',
    () {
      for (final url in [
        'http://example.test',
        'https://user:pass@example.test',
        'https://example.test/api',
        'https://example.test?token=secret',
      ]) {
        expect(() => ApiClient(baseUrl: url), throwsA(isA<ApiFailure>()));
      }
      expect(
        () =>
            ApiClient(baseUrl: 'http://127.0.0.1:8000', allowLocalHttp: false),
        throwsA(isA<ApiFailure>()),
      );
      final api = ApiClient(
        baseUrl: 'http://127.0.0.1:8000',
        allowLocalHttp: true,
      );
      api.close();
    },
  );
}
