import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class DraftAttemptStore {
  Future<String?> read(String origin, String userId);
  Future<void> write(String origin, String userId, String value);
}

class SecureDraftAttemptStore implements DraftAttemptStore {
  SecureDraftAttemptStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );

  final FlutterSecureStorage _storage;
  String _key(String origin, String userId) =>
      'mobile.draft.v1.${base64Url.encode(utf8.encode(origin))}.$userId';

  @override
  Future<String?> read(String origin, String userId) =>
      _storage.read(key: _key(origin, userId));

  @override
  Future<void> write(String origin, String userId, String value) =>
      _storage.write(key: _key(origin, userId), value: value);
}
