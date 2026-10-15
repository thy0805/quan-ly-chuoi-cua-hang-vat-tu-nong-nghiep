import 'dart:convert';
import '../core/numbers.dart';
import 'confirmation.dart';
import 'draft_submission.dart';
import 'models.dart';

class ConfirmAttempt {
  ConfirmAttempt({
    required this.id,
    required this.orderId,
    required this.payment,
    required this.createdAt,
    required this.state,
  });
  factory ConfirmAttempt.fromJson(Json json) {
    final result = ConfirmAttempt(
      id: json['id'] as String,
      orderId: jsonId(json['order_id']),
      payment: InitialPayment.fromJson(json['payment'] as Json),
      createdAt: json['created_at'] as String,
      state: json['state'] as String,
    );
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(result.id) ||
        DateTime.tryParse(result.createdAt) == null ||
        !{
          'pending',
          'unknown',
          'acknowledged',
          'rejected',
        }.contains(result.state)) {
      throw const FormatException('Dấu vết xác nhận không hợp lệ.');
    }
    return result;
  }
  final String id, orderId, createdAt, state;
  final InitialPayment payment;
  ConfirmAttempt withState(String value) => ConfirmAttempt(
    id: id,
    orderId: orderId,
    payment: payment,
    createdAt: createdAt,
    state: value,
  );
  Json toJson() => {
    'id': id,
    'order_id': orderId,
    'payment': payment.toJson(),
    'created_at': createdAt,
    'state': state,
  };
}

class SaleEnvelope {
  SaleEnvelope({
    required this.origin,
    required this.userId,
    this.active,
    this.confirmation,
    this.confirmHistory = const [],
    this.journal = const [],
  });
  factory SaleEnvelope.decode(String raw, String origin, String userId) {
    final json = jsonDecode(raw) as Json;
    if (json['version'] != 2 ||
        json['origin'] != origin ||
        jsonId(json['user_id']) != userId) {
      throw const FormatException('Bộ nhớ bán hàng không đúng tài khoản.');
    }
    final active = json['active'] == null
        ? null
        : DraftAttempt.decode(jsonEncode(json['active']), origin, userId);
    final confirmation = json['confirmation'] == null
        ? null
        : ConfirmAttempt.fromJson(json['confirmation'] as Json);
    final history = List<Json>.unmodifiable(
      (json['confirm_history'] as List).map((row) {
        final item = ConfirmAttempt.fromJson(row as Json);
        if (item.state != 'rejected' || active?.orderId != item.orderId) {
          throw const FormatException('Lịch sử xác nhận không hợp lệ.');
        }
        return item.toJson();
      }),
    );
    if (confirmation != null &&
        (active?.state != 'known_id' ||
            active?.orderId != confirmation.orderId)) {
      throw const FormatException('Mất ID của lần xác nhận.');
    }
    final ids = <String>{};
    final journal = List<Json>.unmodifiable(
      (json['journal'] as List).map((row) {
        final item = Map<String, dynamic>.from(row as Json);
        final attempt = DraftAttempt.decode(
          jsonEncode(item['attempt']),
          origin,
          userId,
        );
        if (attempt.state != 'known_id' ||
            !ids.add(attempt.attemptId) ||
            item['order_id'] != attempt.orderId ||
            item['status'] != 'confirmed' ||
            DateTime.tryParse(item['completed_at'] as String) == null) {
          throw const FormatException('Nhật ký hoàn tất không hợp lệ.');
        }
        jsonId(item['invoice_id']);
        FixedDecimal.parse(item['total'] as String, scale: 2);
        if (item['confirmation'] != null) {
          final confirm = ConfirmAttempt.fromJson(item['confirmation'] as Json);
          if (confirm.orderId != attempt.orderId) {
            throw const FormatException('Sai ID nhật ký.');
          }
        }
        for (final previous in item['confirm_history'] as List) {
          final confirm = ConfirmAttempt.fromJson(previous as Json);
          if (confirm.state != 'rejected' ||
              confirm.orderId != attempt.orderId) {
            throw const FormatException('Sai lịch sử nhật ký.');
          }
        }
        return Map<String, dynamic>.unmodifiable(item);
      }),
    );
    if ((active == null && (confirmation != null || history.isNotEmpty)) ||
        (active != null && ids.contains(active.attemptId))) {
      throw const FormatException('Trạng thái active và nhật ký mâu thuẫn.');
    }
    return SaleEnvelope(
      origin: origin,
      userId: userId,
      active: active,
      confirmation: confirmation,
      confirmHistory: history,
      journal: journal,
    );
  }
  final String origin, userId;
  final DraftAttempt? active;
  final ConfirmAttempt? confirmation;
  final List<Json> confirmHistory, journal;
  String encode() => jsonEncode({
    'version': 2,
    'origin': origin,
    'user_id': userId,
    'active': active == null ? null : jsonDecode(active!.encode()),
    'confirmation': confirmation?.toJson(),
    'confirm_history': confirmHistory,
    'journal': journal,
  });
}
