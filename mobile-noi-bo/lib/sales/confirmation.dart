import '../core/numbers.dart';
import 'models.dart';

bool sameReviewedSale(SalesOrderDetail before, SalesOrderDetail after) =>
    before.items.length == after.items.length &&
    before.items.every(
      (item) => after.items.any(
        (current) =>
            item.taxRate != null &&
            item.tax != null &&
            current.id == item.id &&
            current.lotId == item.lotId &&
            current.quantity.compareTo(item.quantity) == 0 &&
            current.price.compareTo(item.price) == 0 &&
            current.discount.compareTo(item.discount) == 0 &&
            current.net.compareTo(item.net) == 0 &&
            current.taxRate?.compareTo(item.taxRate!) == 0 &&
            current.tax?.compareTo(item.tax!) == 0,
      ),
    );

FixedDecimal verifiedSaleTotal(SalesOrderDetail detail) {
  if (detail.items.isEmpty || detail.items.length > 50) {
    throw const FormatException('Không có dòng bán hợp lệ.');
  }
  final lots = <String>{};
  var gross = FixedDecimal.zero(2);
  var discount = FixedDecimal.zero(2);
  var tax = FixedDecimal.zero(2);
  for (final item in detail.items) {
    if (!lots.add(item.lotId) || item.taxRate == null || item.tax == null) {
      throw const FormatException('Thiếu hoặc trùng dữ liệu thuế đã chụp.');
    }
    final line = (item.price * item.quantity).roundedTo(2);
    final net = line - item.discount;
    if (net.atoms.isNegative ||
        net.compareTo(item.net) != 0 ||
        net.taxAt(item.taxRate!).compareTo(item.tax!) != 0) {
      throw const FormatException('Số tiền dòng không khớp snapshot.');
    }
    gross = gross + line;
    discount = discount + item.discount;
    tax = tax + item.tax!;
    if (!detail.order.isDraft &&
        (item.unitCost == null ||
            item.costTotal == null ||
            (item.unitCost! * item.quantity)
                    .roundedTo(2)
                    .compareTo(item.costTotal!) !=
                0)) {
      throw const FormatException('Thiếu hoặc sai snapshot giá vốn.');
    }
  }
  final total = gross - discount + tax;
  FixedDecimal.parse(total.toString(), scale: 2);
  if (!detail.order.isDraft) {
    if (detail.order.invoiceId == null ||
        detail.order.invoiceNumber == null ||
        detail.order.invoiceNumber!.trim().isEmpty ||
        DateTime.tryParse(detail.issuedAt ?? '') == null ||
        DateTime.tryParse(detail.order.soldAt ?? '') == null ||
        detail.subtotal == null ||
        detail.discount == null ||
        detail.tax == null ||
        detail.paid == null ||
        detail.remaining == null ||
        gross.compareTo(detail.subtotal!) != 0 ||
        discount.compareTo(detail.discount!) != 0 ||
        tax.compareTo(detail.tax!) != 0 ||
        total.compareTo(detail.order.total) != 0 ||
        detail.paid!.atoms.isNegative ||
        detail.remaining!.atoms.isNegative ||
        (detail.paid! + detail.remaining!).compareTo(total) != 0 ||
        (detail.order.customerId == null &&
            detail.remaining!.atoms != BigInt.zero)) {
      throw const FormatException('Hóa đơn hoặc số dư chưa được xác minh.');
    }
  }
  return total;
}

class InitialPayment {
  InitialPayment({required String amount, this.method, String? note})
    : amount = FixedDecimal.parse(amount, scale: 2),
      note = note?.trim() {
    if (this.amount.atoms.isNegative ||
        (method != null && !{'cash', 'bank_transfer'}.contains(method)) ||
        (this.amount.atoms > BigInt.zero && method == null) ||
        (this.note?.runes.length ?? 0) > 200) {
      throw const FormatException('Kiểm tra số tiền, phương thức và ghi chú.');
    }
  }
  factory InitialPayment.fromJson(Json json) {
    if (json.keys.toSet().difference({
      'amount',
      'method',
      'reference_note',
    }).isNotEmpty) {
      throw const FormatException('Trường thanh toán không hợp lệ.');
    }
    return InitialPayment(
      amount: json['amount'] as String,
      method: json['method'] as String?,
      note: json['reference_note'] as String?,
    );
  }
  final FixedDecimal amount;
  final String? method, note;
  void validate(SalesOrderDetail detail) {
    final total = verifiedSaleTotal(detail);
    if (!detail.order.isDraft ||
        amount.compareTo(total) > 0 ||
        (detail.order.customerId == null && amount.compareTo(total) != 0)) {
      throw const FormatException(
        'Khách lẻ phải trả đủ; số thu không được vượt tổng.',
      );
    }
  }

  Json toJson() => {
    'amount': amount.toString(),
    if (method != null) 'method': method,
    if (note != null && note!.isNotEmpty) 'reference_note': note,
  };
}
