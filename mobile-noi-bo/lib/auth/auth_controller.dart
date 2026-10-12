import 'package:flutter/foundation.dart';

import 'api_client.dart';
import 'models.dart';
import 'session_store.dart';

enum AuthStage { restoring, signedOut, chooseScope, ready, unavailable }

class AuthController extends ChangeNotifier {
  AuthController(this.api, this.store);

  final ApiClient api;
  final SessionStore store;
  AuthStage stage = AuthStage.restoring;
  Profile? profile;
  Session? _session;
  String? message;
  bool busy = false;

  Branch? get branch {
    for (final item in profile?.branches ?? <Branch>[]) {
      if (item.id == _session?.branchId) return item;
    }
    return null;
  }

  Future<void> restore() => _perform(() async {
    _session = await store.read(api.storageNamespace);
    if (_session == null) {
      stage = AuthStage.signedOut;
    } else if (!_session!.expiresAt.isAfter(DateTime.now())) {
      await _clear();
      message = 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.';
    } else {
      await _loadProfile();
    }
  });

  Future<void> login(String username, String password) => _perform(() async {
    final session = await api.login(username.trim(), password);
    try {
      await store.write(api.storageNamespace, session);
    } catch (_) {
      try {
        await api.logout(session);
      } catch (_) {}
      throw const ApiFailure(
        'Không lưu được phiên vào bộ nhớ bảo mật. Vui lòng kiểm tra thiết bị.',
      );
    }
    _session = session;
    await _loadProfile();
  });

  Future<void> refresh() => _perform(_loadProfile);

  Future<void> chooseBranch(String id) => _perform(() async {
    await _loadProfile();
    if (stage == AuthStage.unavailable || _session == null) return;
    if (!profile!.branches.any((item) => item.id == id)) {
      throw const ApiFailure('Chi nhánh không còn thuộc phạm vi được cấp.');
    }
    final updated = _session!.inBranch(id);
    await store.write(api.storageNamespace, updated);
    _session = updated;
    stage = AuthStage.ready;
  });

  void changeScope() {
    if (busy || _session == null) return;
    message = null;
    stage = AuthStage.chooseScope;
    notifyListeners();
  }

  Future<void> logout() => _perform(() async {
    if (_session != null) await api.logout(_session!);
    await _clear();
  }, logoutOperation: true);

  Future<void> _loadProfile() async {
    if (_session == null) return;
    if (!_session!.expiresAt.isAfter(DateTime.now())) {
      throw const ApiFailure('Phiên đăng nhập đã hết hạn.', status: 401);
    }
    profile = await api.profile(_session!);
    if (profile!.branches.isEmpty) {
      throw const ApiFailure(
        'Tài khoản chưa có phạm vi làm việc có hiệu lực.',
        status: 403,
      );
    }
    stage = branch == null ? AuthStage.chooseScope : AuthStage.ready;
  }

  Future<void> _clear() async {
    await store.clear(api.storageNamespace);
    _session = null;
    profile = null;
    stage = AuthStage.signedOut;
  }

  Future<void> _perform(
    Future<void> Function() action, {
    bool logoutOperation = false,
  }) async {
    if (busy) return;
    busy = true;
    message = null;
    notifyListeners();
    try {
      await action();
    } on ApiFailure catch (error) {
      message = logoutOperation
          ? 'Chưa đăng xuất: ${error.message}'
          : error.message;
      if (error.status == 401 && !logoutOperation) {
        try {
          await _clear();
        } catch (_) {
          stage = AuthStage.unavailable;
        }
      } else if (_session != null && !logoutOperation) {
        stage = AuthStage.unavailable;
      } else if (stage == AuthStage.restoring) {
        stage = AuthStage.signedOut;
      }
    } catch (_) {
      message =
          'Không truy cập được bộ nhớ bảo mật. Vui lòng thử lại trên thiết bị.';
      stage = _session == null ? AuthStage.signedOut : AuthStage.unavailable;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    api.close();
    super.dispose();
  }
}
