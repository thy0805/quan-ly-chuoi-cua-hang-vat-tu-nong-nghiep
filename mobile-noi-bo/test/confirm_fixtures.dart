import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:klcn186_mobile/auth/auth_controller.dart';
import 'package:klcn186_mobile/sales/draft_submission.dart';
import 'package:klcn186_mobile/sales/sale_envelope.dart';
import 'package:klcn186_mobile/sales/models.dart';
import 'auth_test.dart' as auth;
import 'draft_fixtures.dart' as draft;
import 'sales_fixtures.dart' as sales;

const customerId = '21';
DraftPayload payload({bool customer = false}) => DraftPayload.fromJson({
  ...draft.payload().toJson(),
  'customer_id': customer ? customerId : null,
});
DraftAttempt active({bool customer = false}) => DraftAttempt(
  attemptId: 'b' * 32,
  origin: draft.origin,
  userId: draft.userId,
  payload: payload(customer: customer),
  createdAt: '2026-10-14T00:00:00Z',
  state: 'known_id',
  orderId: sales.draftId,
);
Json detail({
  bool confirmed = false,
  bool customer = false,
  String paid = '189000.00',
}) {
  final value = draft.detail();
  final data = value['data'] as Json;
  data['customer_id'] = customer ? customerId : null;
  data['customer_name'] = customer ? 'Khách cùng chuỗi' : null;
  if (confirmed) {
    data.addAll({
      'status': 'confirmed',
      'total_amount': '189000.00',
      'invoice_id': '9007199254741003',
      'invoice_no': 'HD-QA-FAKE',
      'sold_at': '2026-10-14T03:30:00Z',
      'issued_at': '2026-10-14T03:30:00Z',
      'subtotal': '200000.00',
      'invoice_discount_amount': '20000.00',
      'invoice_tax_amount': '9000.00',
      'paid_amount': paid,
      'remaining_amount': (18900000 - _cents(paid)).toString(),
    });
    final remaining = 18900000 - _cents(paid);
    data['remaining_amount'] =
        '${remaining ~/ 100}.${(remaining % 100).toString().padLeft(2, '0')}';
    (value['items'] as List).first.addAll({
      'unit_cost_snapshot': '60000.000000',
      'cost_total': '120000.00',
    });
  }
  return value;
}

int _cents(String value) {
  final parts = value.split('.');
  return int.parse(parts.first) * 100 + int.parse(parts[1]);
}

draft.MemoryDraftStore store({bool customer = false}) =>
    draft.MemoryDraftStore()
      ..values['${draft.origin}|${draft.userId}'] = active(
        customer: customer,
      ).encode();
SaleEnvelope envelope(draft.MemoryDraftStore store) => SaleEnvelope.decode(
  store.values['${draft.origin}|${draft.userId}']!,
  draft.origin,
  draft.userId,
);
Future<AuthController> ready(
  draft.MemoryDraftStore store,
  FutureOr<http.Response> Function(http.Request) handler, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final controller = await draft.ready(handler, store: store, timeout: timeout);
  await controller.drafts.restore();
  await controller.drafts.reloadDetail();
  return controller;
}

http.Response confirmed() =>
    auth.jsonResponse({'id': sales.draftId, 'status': 'confirmed'});
String encoded(Json value) => jsonEncode(value);
