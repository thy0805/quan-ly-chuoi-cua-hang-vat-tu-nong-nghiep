import '../core/numbers.dart';
import 'models.dart';

String vietnamDay(DateTime now) {
  final day = now.toUtc().add(const Duration(hours: 7));
  return '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
}

String? stockUnavailable(SalesStock stock, DateTime now) {
  if (stock.quantity.atoms <= BigInt.zero) return 'Lô không còn tồn khả dụng.';
  final expiry = stock.expiresOn;
  if (expiry != null) {
    final parsed = DateTime.tryParse(expiry);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(expiry) ||
        parsed == null ||
        parsed.toIso8601String().substring(0, 10) != expiry) {
      return 'Ngày hết hạn không hợp lệ. Cần tải lại dữ liệu.';
    }
    if (expiry.compareTo(vietnamDay(now)) < 0) return 'Lô đã hết hạn.';
  }
  if (stock.taxRate == null) return 'Vật tư chưa được cấu hình thuế suất.';
  return null;
}

FixedDecimal cartNumber(String text, {required bool quantity}) {
  try {
    final value = FixedDecimal.parse(
      text.trim().replaceAll(',', '.'),
      scale: quantity ? 3 : 2,
      wholeDigits: quantity ? 15 : 16,
    );
    if (quantity ? value.atoms <= BigInt.zero : value.atoms.isNegative) {
      throw const FormatException();
    }
    return value;
  } on FormatException {
    throw FormatException(
      quantity
          ? 'Số lượng phải dương, tối đa 15 số nguyên và 3 số lẻ.'
          : 'Chiết khấu không âm, tối đa 16 số nguyên và 2 số lẻ.',
    );
  }
}

void _fitsMoney(FixedDecimal value) {
  if (value.compareTo(FixedDecimal.parse('9999999999999999.99', scale: 2)) >
      0) {
    throw const FormatException(
      'Số tiền vượt giới hạn lưu trữ. Giảm số lượng hoặc số dòng.',
    );
  }
}

class CartLine {
  CartLine(this.stock)
    : quantityText =
          stock.quantity.compareTo(FixedDecimal.parse('1', scale: 3)) < 0
          ? stock.quantity.toString()
          : '1';

  final SalesStock stock;
  String quantityText;
  String discountText = '0';

  String? get quantityError {
    try {
      final value = cartNumber(quantityText, quantity: true);
      if (value.compareTo(stock.quantity) > 0) {
        return 'Vượt tồn tại lúc tải: ${stock.quantity.vietnamese} ${stock.unitName}.';
      }
      _fitsMoney((stock.price * value).roundedTo(2));
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }

  String? get discountError {
    try {
      final discount = cartNumber(discountText, quantity: false);
      if (quantityError == null &&
          discount.compareTo(
                (stock.price * cartNumber(quantityText, quantity: true))
                    .roundedTo(2),
              ) >
              0) {
        return 'Chiết khấu vượt tiền dòng.';
      }
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }

  LineAmounts amounts(DateTime now) {
    final error =
        stockUnavailable(stock, now) ?? quantityError ?? discountError;
    if (error != null) throw FormatException(error);
    final amounts = LineAmounts(
      price: stock.price,
      quantity: cartNumber(quantityText, quantity: true),
      discount: cartNumber(discountText, quantity: false),
      taxRate: stock.taxRate!,
    );
    for (final value in [
      amounts.gross,
      amounts.net,
      amounts.tax,
      amounts.total,
    ]) {
      _fitsMoney(value);
    }
    return amounts;
  }
}

class CartTotals {
  CartTotals(List<CartLine> lines, DateTime now) {
    for (final line in lines) {
      final value = line.amounts(now);
      gross += value.gross;
      discount += cartNumber(line.discountText, quantity: false);
      net += value.net;
      tax += value.tax;
      total += value.total;
    }
    for (final value in [gross, discount, net, tax, total]) {
      _fitsMoney(value);
    }
  }
  FixedDecimal gross = FixedDecimal.zero(2);
  FixedDecimal discount = FixedDecimal.zero(2);
  FixedDecimal net = FixedDecimal.zero(2);
  FixedDecimal tax = FixedDecimal.zero(2);
  FixedDecimal total = FixedDecimal.zero(2);
}

class SalesCart {
  SalesCart(SalesOptions options, String branchId, String chainId)
    : options = options.forBranch(branchId, chainId);

  final SalesOptions options;
  String? warehouseId;
  String? customerId;
  final List<CartLine> _lines = [];
  List<CartLine> get lines => List.unmodifiable(_lines);

  void selectWarehouse(String id) {
    if (!options.warehouses.any((item) => item.id == id)) {
      throw const FormatException('Kho không thuộc chi nhánh đang chọn.');
    }
    if (id != warehouseId) _lines.clear();
    warehouseId = id;
  }

  void selectCustomer(String? id) {
    if (id != null && !options.customers.any((item) => item.id == id)) {
      throw const FormatException('Khách hàng không thuộc chuỗi đang chọn.');
    }
    customerId = id;
  }

  List<SalesStock> get stock => List.unmodifiable(
    options.stock.where((item) => item.warehouseId == warehouseId),
  );

  String? unavailable(SalesStock item, DateTime now) {
    if (!stock.contains(item)) return 'Lô không thuộc kho đang chọn.';
    if (_lines.any((line) => line.stock.lotId == item.lotId)) {
      return 'Lô đã có trong giỏ.';
    }
    if (_lines.length >= 50) return 'Giỏ tối đa 50 lô.';
    return stockUnavailable(item, now);
  }

  void add(SalesStock item, DateTime now) {
    final error = unavailable(item, now);
    if (error != null) throw FormatException(error);
    _lines.add(CartLine(item));
  }

  void remove(CartLine line) => _lines.remove(line);
  void clear() => _lines.clear();
  CartTotals totals(DateTime now) => CartTotals(_lines, now);
}
