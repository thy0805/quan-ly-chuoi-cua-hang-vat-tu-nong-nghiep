import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'models.dart';
import '../core/numbers.dart';
import '../transfers/dispatch_models.dart';
import '../transfers/receive_models.dart';

enum ApiFailureKind {
  unauthenticated,
  forbidden,
  notFound,
  conflict,
  validation,
  rateLimited,
  network,
  timeout,
  server,
  invalidResponse,
  unexpected,
}

class ApiFailure implements Exception {
  const ApiFailure(
    this.message, {
    this.status,
    ApiFailureKind? kind,
    this.fieldErrors = const {},
    this.definiteRejection = false,
  }) : _kind = kind;

  final String message;
  final int? status;
  final ApiFailureKind? _kind;
  final Map<String, List<String>> fieldErrors;
  final bool definiteRejection;

  ApiFailureKind get kind =>
      _kind ??
      switch (status) {
        401 => ApiFailureKind.unauthenticated,
        403 => ApiFailureKind.forbidden,
        404 => ApiFailureKind.notFound,
        409 => ApiFailureKind.conflict,
        422 => ApiFailureKind.validation,
        429 => ApiFailureKind.rateLimited,
        int value when value >= 500 && value <= 599 => ApiFailureKind.server,
        _ => ApiFailureKind.unexpected,
      };
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
      loginOperation: true,
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
      throw const ApiFailure(
        'Phản hồi đăng nhập không đúng định dạng.',
        kind: ApiFailureKind.invalidResponse,
      );
    }
  }

  Future<Profile> profile(Session session) async {
    final data = await _request('GET', '/api/me', token: session.token);
    try {
      return Profile.fromJson(data);
    } catch (_) {
      throw const ApiFailure(
        'Không đọc được thông tin phạm vi từ API.',
        kind: ApiFailureKind.invalidResponse,
      );
    }
  }

  Future<void> logout(Session session) async {
    try {
      await _request('POST', '/api/mobile/logout', token: session.token);
    } on ApiFailure catch (error) {
      if (error.status != 401) rethrow;
    }
  }

  Future<Map<String, dynamic>> readSales(Session session, String path) {
    if (path != '/api/sales-orders' && path != '/api/sales-orders/options') {
      const prefix = '/api/sales-orders/';
      if (!path.startsWith(prefix)) throw ArgumentError('Chỉ đọc đơn bán.');
      jsonId(path.substring(prefix.length));
    }
    return _request('GET', path, token: session.token);
  }

  Future<Map<String, dynamic>> readTransfers(Session session, String path) {
    final page = RegExp(
      r'^/api/stock-transfers\?page=[1-9][0-9]*&per_page=50$',
    );
    if (path != '/api/stock-transfers/options' && !page.hasMatch(path)) {
      const prefix = '/api/stock-transfers/';
      if (!path.startsWith(prefix)) {
        throw ArgumentError('Chỉ đọc phiếu điều chuyển.');
      }
      jsonId(path.substring(prefix.length));
    }
    return _request('GET', path, token: session.token);
  }

  Future<String> createSalesDraft(
    Session session,
    Map<String, dynamic> payload,
  ) async {
    final data = await _request(
      'POST',
      '/api/sales-orders',
      token: session.token,
      body: payload,
      draftOperation: true,
    );
    try {
      if (data['status'] != 'draft') throw const FormatException();
      return jsonId(data['id']);
    } catch (_) {
      throw const ApiFailure(
        'Không xác minh được ID đơn nháp từ phản hồi.',
        kind: ApiFailureKind.invalidResponse,
      );
    }
  }

  Future<String> createTransferRequest(
    Session session,
    Map<String, dynamic> payload,
  ) async {
    final data = await _request(
      'POST',
      '/api/stock-transfers',
      token: session.token,
      body: payload,
      transferOperation: true,
    );
    try {
      return jsonId(data['id']);
    } catch (_) {
      throw const ApiFailure(
        'Không xác minh được ID yêu cầu điều chuyển. Không gửi lại.',
        kind: ApiFailureKind.invalidResponse,
      );
    }
  }

  Future<void> decideTransfer(
    Session session,
    String id,
    String action, {
    String? reason,
  }) async {
    jsonId(id);
    if (!{'approve', 'reject'}.contains(action) ||
        action == 'approve' && reason != null ||
        reason != null && reason.runes.length > 1000) {
      throw ArgumentError('Thao tác điều chuyển không hợp lệ.');
    }
    final data = await _request(
      'POST',
      '/api/stock-transfers/$id/$action',
      token: session.token,
      body: action == 'reject' ? {'reason': reason} : <String, dynamic>{},
      decisionOperation: true,
    );
    if (data['status'] != (action == 'approve' ? 'approved' : 'rejected')) {
      throw const ApiFailure(
        'Chưa xác minh được kết quả xử lý. Chỉ tải lại phiếu, không gửi lại.',
        kind: ApiFailureKind.invalidResponse,
      );
    }
  }

  Future<void> dispatchTransfer(
    Session session,
    String id,
    Map<String, dynamic> payload,
  ) async {
    jsonId(id);
    if (payload.length != 1 || !payload.containsKey('items')) {
      throw const FormatException('Sai payload xuất kho.');
    }
    final items = dispatchLines(payload['items']);
    final data = await _request(
      'POST',
      '/api/stock-transfers/$id/dispatch',
      token: session.token,
      body: {
        'items': [for (final item in items) item.toJson()],
      },
      dispatchOperation: true,
    );
    if (data['status'] != 'dispatched') {
      throw const ApiFailure(
        'Chưa xác minh được kết quả xuất. Chỉ tải lại phiếu, không gửi lại.',
        kind: ApiFailureKind.invalidResponse,
      );
    }
  }

  Future<void> receiveTransfer(
    Session session,
    String id,
    Map<String, dynamic> payload,
  ) async {
    jsonId(id);
    if (payload.length != 1 || !payload.containsKey('items')) {
      throw const FormatException('Sai payload nhận hàng.');
    }
    final items = receiveLines(payload['items']);
    final data = await _request(
      'POST',
      '/api/stock-transfers/$id/receive',
      token: session.token,
      body: {
        'items': [for (final item in items) item.toJson()],
      },
      receiveOperation: true,
    );
    if (!{'received', 'discrepancy'}.contains(data['status'])) {
      throw const ApiFailure(
        'Chưa xác minh được kết quả nhận. Chỉ tải lại phiếu, không gửi lại.',
        kind: ApiFailureKind.invalidResponse,
      );
    }
  }

  Future<void> confirmSalesDraft(
    Session session,
    String id,
    Map<String, dynamic> payment,
  ) async {
    jsonId(id);
    final data = await _request(
      'POST',
      '/api/sales-orders/$id/confirm',
      token: session.token,
      body: payment,
      confirmOperation: true,
    );
    if (data['status'] != 'confirmed' || data['id'] != id) {
      throw const ApiFailure(
        'Không xác minh được kết quả xác nhận.',
        kind: ApiFailureKind.invalidResponse,
      );
    }
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    String? token,
    Map<String, dynamic>? body,
    bool loginOperation = false,
    bool draftOperation = false,
    bool confirmOperation = false,
    bool transferOperation = false,
    bool decisionOperation = false,
    bool dispatchOperation = false,
    bool receiveOperation = false,
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
        kind: ApiFailureKind.timeout,
      );
    } on Exception {
      throw const ApiFailure(
        'Không kết nối được API. Kiểm tra mạng và địa chỉ máy chủ.',
        kind: ApiFailureKind.network,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = switch (response.statusCode) {
        401 => 'Phiên đăng nhập đã hết hạn hoặc bị thu hồi.',
        403 => 'Tài khoản bị khóa hoặc không có quyền truy cập phạm vi này.',
        404 => 'Không tìm thấy đơn hàng trong phạm vi được cấp.',
        409 => 'Trạng thái chứng từ đã thay đổi. Cần tải lại chi tiết.',
        422 =>
          loginOperation
              ? 'Thông tin đăng nhập không hợp lệ.'
              : 'Dữ liệu yêu cầu không hợp lệ.',
        429 => 'Đã gửi quá nhiều yêu cầu. Vui lòng chờ trước khi tải lại.',
        >= 500 => 'Máy chủ gặp lỗi. Chưa xác định được kết quả yêu cầu.',
        _ => 'Không đọc được phản hồi từ API.',
      };
      final errors = <String, List<String>>{};
      var definiteRejection = false;
      if ((draftOperation ||
              confirmOperation ||
              transferOperation ||
              decisionOperation ||
              dispatchOperation ||
              receiveOperation) &&
          {401, 403, 422}.contains(response.statusCode) &&
          (response.headers['content-type'] ?? '')
                  .split(';')
                  .first
                  .trim()
                  .toLowerCase() ==
              'application/json') {
        try {
          final body = jsonDecode(utf8.decode(response.bodyBytes));
          definiteRejection =
              body is Map &&
              body['message'] is String &&
              (response.statusCode != 422 || body['errors'] is Map);
        } catch (_) {}
      }
      if (!loginOperation && response.statusCode == 422) {
        try {
          final body = jsonDecode(utf8.decode(response.bodyBytes));
          if (body is Map && body['errors'] is Map) {
            for (final entry in (body['errors'] as Map).entries) {
              final key = entry.key;
              if (key is String &&
                  RegExp(r'^[a-zA-Z0-9_.]+$').hasMatch(key) &&
                  entry.value is List) {
                errors[key] = List<String>.unmodifiable(
                  (entry.value as List).whereType<String>().map(
                    (value) => value
                        .replaceAll(RegExp(r'[\x00-\x1F]'), ' ')
                        .substring(0, value.length > 300 ? 300 : value.length),
                  ),
                );
              }
            }
          }
        } catch (_) {}
      }
      throw ApiFailure(
        message,
        status: response.statusCode,
        fieldErrors: Map.unmodifiable(errors),
        definiteRejection: definiteRejection,
      );
    }
    if (draftOperation && response.statusCode != 201) {
      throw const ApiFailure(
        'Phản hồi tạo nháp không đúng contract.',
        kind: ApiFailureKind.invalidResponse,
      );
    }
    if (transferOperation &&
        (response.statusCode != 201 ||
            (response.headers['content-type'] ?? '')
                    .split(';')
                    .first
                    .trim()
                    .toLowerCase() !=
                'application/json')) {
      throw const ApiFailure(
        'Phản hồi tạo điều chuyển không đúng contract. Không gửi lại.',
        kind: ApiFailureKind.invalidResponse,
      );
    }
    if ((confirmOperation ||
            decisionOperation ||
            dispatchOperation ||
            receiveOperation) &&
        (response.statusCode != 200 ||
            (response.headers['content-type'] ?? '')
                    .split(';')
                    .first
                    .trim()
                    .toLowerCase() !=
                'application/json')) {
      throw const ApiFailure(
        'Phản hồi xác nhận không đúng contract.',
        kind: ApiFailureKind.invalidResponse,
      );
    }
    try {
      return jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
    } catch (_) {
      throw const ApiFailure(
        'Phản hồi API không đúng định dạng JSON.',
        kind: ApiFailureKind.invalidResponse,
      );
    }
  }

  void close() => _client.close();
}
