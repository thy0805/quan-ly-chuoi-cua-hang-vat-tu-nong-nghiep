import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'models.dart';

class ApiFailure implements Exception {
  const ApiFailure(this.message, {this.status});

  final String message;
  final int? status;
}

class ApiClient {
  ApiClient({
    required String baseUrl,
    http.Client? client,
    bool allowLocalHttp = kDebugMode,
    this.timeout = const Duration(seconds: 20),
  }) : _base = Uri.parse(baseUrl),
       _client = client ?? http.Client() {
    final localHttp =
        allowLocalHttp &&
        _base.scheme == 'http' &&
        const [
          '127.0.0.1',
          'localhost',
          '10.0.2.2',
          '[::1]',
        ].contains(_base.host);
    if ((_base.scheme != 'https' && !localHttp) ||
        _base.host.isEmpty ||
        _base.userInfo.isNotEmpty ||
        _base.hasQuery ||
        _base.hasFragment ||
        (_base.path.isNotEmpty && _base.path != '/')) {
      throw const ApiFailure(
        'API_BASE_URL phải là địa chỉ HTTPS; debug chỉ cho phép HTTP local.',
      );
    }
  }

  factory ApiClient.fromEnvironment() => ApiClient(
    baseUrl: const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://127.0.0.1:8000',
    ),
  );

  final Uri _base;
  final http.Client _client;
  final Duration timeout;
  String get storageNamespace => _base.origin;

  Future<Session> login(String username, String password) async {
    final data = await _request(
      'POST',
      '/api/mobile/login',
      body: {
        'username': username,
        'password': password,
        'device_name': 'Flutter Android',
      },
    );
    try {
      if (data['token_type'] != 'Bearer') throw const FormatException();
      final session = Session.fromJson(data);
      if (session.token.isEmpty || !session.expiresAt.isAfter(DateTime.now())) {
        throw const FormatException();
      }
      return session;
    } catch (_) {
      throw const ApiFailure('Phản hồi đăng nhập không đúng định dạng.');
    }
  }

  Future<Profile> profile(Session session) async {
    final data = await _request('GET', '/api/me', token: session.token);
    try {
      return Profile.fromJson(data);
    } catch (_) {
      throw const ApiFailure('Không đọc được thông tin phạm vi từ API.');
    }
  }

  Future<void> logout(Session session) async {
    try {
      await _request('POST', '/api/mobile/logout', token: session.token);
    } on ApiFailure catch (error) {
      if (error.status != 401) rethrow;
    }
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    String? token,
    Map<String, dynamic>? body,
  }) async {
    final request = http.Request(method, _base.resolve(path))
      ..followRedirects = false;
    request.headers.addAll({
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    });
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) request.body = jsonEncode(body);
    http.Response response;
    try {
      response = await (() async {
        final streamed = await _client.send(request);
        return http.Response.fromStream(streamed);
      })().timeout(timeout);
    } on TimeoutException {
      throw const ApiFailure(
        'Kết nối hết thời gian chờ. Yêu cầu không được tự gửi lại.',
      );
    } on Exception {
      throw const ApiFailure(
        'Không kết nối được API. Kiểm tra mạng và địa chỉ máy chủ.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = switch (response.statusCode) {
        401 => 'Phiên đăng nhập đã hết hạn hoặc bị thu hồi.',
        403 => 'Tài khoản bị khóa hoặc không còn phạm vi được cấp.',
        422 => 'Thông tin đăng nhập không hợp lệ.',
        429 => 'Đã thử quá nhiều lần. Vui lòng chờ một phút.',
        _ => 'API chưa xử lý được yêu cầu. Vui lòng thử lại có chủ đích.',
      };
      throw ApiFailure(message, status: response.statusCode);
    }
    try {
      return jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
    } catch (_) {
      throw const ApiFailure('Phản hồi API không đúng định dạng JSON.');
    }
  }

  void close() => _client.close();
}
