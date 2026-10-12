import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'models.dart';

abstract interface class SessionStore {
  Future<Session?> read(String namespace);
  Future<void> write(String namespace, Session session);
  Future<void> clear(String namespace);
}

class SecureSessionStore implements SessionStore {
  SecureSessionStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );

  final FlutterSecureStorage _storage;
  String _key(String namespace) =>
      'mobile.session.${base64Url.encode(utf8.encode(namespace))}';

  @override
  Future<Session?> read(String namespace) async {
    final value = await _storage.read(key: _key(namespace));
    if (value == null) return null;
    try {
      return Session.fromJson(jsonDecode(value) as Map<String, dynamic>);
    } catch (_) {
      await clear(namespace);
      return null;
    }
  }

  @override
  Future<void> write(String namespace, Session session) =>
      _storage.write(key: _key(namespace), value: jsonEncode(session.toJson()));

  @override
  Future<void> clear(String namespace) => _storage.delete(key: _key(namespace));
}
