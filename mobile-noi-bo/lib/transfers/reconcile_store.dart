import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class TransferReconcileStore {
  Future<String?> read(String origin, String userId);
  Future<void> write(String origin, String userId, String value);
}

class SecureTransferReconcileStore implements TransferReconcileStore {
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  String _key(String origin, String user) =>
      'mobile.transfer.reconcile.v1.${base64Url.encode(utf8.encode(origin))}.$user';

  @override
  Future<String?> read(String origin, String userId) =>
      _storage.read(key: _key(origin, userId));

  @override
  Future<void> write(String origin, String userId, String value) =>
      _storage.write(key: _key(origin, userId), value: value);
}
