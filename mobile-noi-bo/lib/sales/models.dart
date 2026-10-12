import '../core/numbers.dart';

typedef Json = Map<String, dynamic>;

String _text(Json json, String key) => json[key] as String;
String? _optionalText(Json json, String key) => json[key] as String?;
String _id(Json json, String key) => jsonId(json[key]);
String? _optionalId(Json json, String key) =>
    json[key] == null ? null : _id(json, key);
FixedDecimal _number(Json json, String key, int scale, int wholeDigits) {
  final value = FixedDecimal.parse(
    _text(json, key),
    scale: scale,
    wholeDigits: wholeDigits,
  );
  if (value.atoms.isNegative) throw const FormatException('Giá trị âm.');
  return value;
}

FixedDecimal _money(Json json, String key) => _number(json, key, 2, 16);
FixedDecimal? _optionalMoney(Json json, String key) =>
    json[key] == null ? null : _money(json, key);
FixedDecimal? _rate(Json json, String key) {
  if (json[key] == null) return null;
  final value = _number(json, key, 2, 3);
  if (value.compareTo(FixedDecimal.parse('100', scale: 2)) > 0) {
    throw const FormatException('Thuế suất không hợp lệ.');
  }
  return value;
}

List<T> _rows<T>(Json json, String key, T Function(Json) parse) =>
    List.unmodifiable((json[key] as List).map((item) => parse(item as Json)));
String _status(Json json) {
  final status = _text(json, 'status');
  if (status != 'draft' && status != 'confirmed') {
    throw const FormatException('Trạng thái không hỗ trợ.');
  }
  return status;
}

class SalesWarehouse {
  SalesWarehouse.fromJson(Json json)
    : id = _id(json, 'id'),
      name = _text(json, 'name'),
      branchId = _id(json, 'branch_id'),
      chainId = _id(json, 'chain_id'),
      branchName = _text(json, 'branch_name');
  final String id, name, branchId, chainId, branchName;
}

class SalesCustomer {
  SalesCustomer.fromJson(Json json)
    : id = _id(json, 'id'),
      chainId = _id(json, 'chain_id'),
      name = _text(json, 'name'),
      customerType = _text(json, 'customer_type');
  final String id, chainId, name, customerType;
}

class SalesStock {
  SalesStock.fromJson(Json json)
    : warehouseId = _id(json, 'warehouse_id'),
      lotId = _id(json, 'lot_id'),
      productId = _id(json, 'product_id'),
      quantity = _number(json, 'quantity', 3, 15),
      code = _text(json, 'code'),
      name = _text(json, 'name'),
      price = _money(json, 'sale_price'),
      taxRate = _rate(json, 'tax_rate'),
      lotNo = _text(json, 'lot_no'),
      expiresOn = _optionalText(json, 'expires_on'),
      unitName = _text(json, 'unit_name');
  final String warehouseId, lotId, productId, code, name, lotNo, unitName;
  final String? expiresOn;
  final FixedDecimal quantity, price;
  final FixedDecimal? taxRate;
}

class SalesOptions {
  SalesOptions._(this.warehouses, this.customers, this.stock);
  factory SalesOptions.fromJson(Json json) => SalesOptions._(
    _rows(json, 'warehouses', SalesWarehouse.fromJson),
    _rows(json, 'customers', SalesCustomer.fromJson),
    _rows(json, 'stock', SalesStock.fromJson),
  );
  final List<SalesWarehouse> warehouses;
  final List<SalesCustomer> customers;
  final List<SalesStock> stock;
  SalesOptions forBranch(String branchId, String chainId) {
    final selected = warehouses
        .where((item) => item.branchId == branchId && item.chainId == chainId)
        .toList();
    final warehouseIds = selected.map((item) => item.id).toSet();
    return SalesOptions._(
      List.unmodifiable(selected),
      List.unmodifiable(customers.where((item) => item.chainId == chainId)),
      List.unmodifiable(
        stock.where((item) => warehouseIds.contains(item.warehouseId)),
      ),
    );
  }
}

class SalesOrderSummary {
  SalesOrderSummary.fromJson(Json json)
    : id = _id(json, 'id'),
      number = _text(json, 'order_no'),
      status = _status(json),
      total = _money(json, 'total_amount'),
      branchId = _id(json, 'branch_id'),
      branchName = _text(json, 'branch_name'),
      customerId = _optionalId(json, 'customer_id'),
      customerName = _optionalText(json, 'customer_name'),
      soldAt = _optionalText(json, 'sold_at'),
      invoiceId = _optionalId(json, 'invoice_id'),
      invoiceNumber = _optionalText(json, 'invoice_no');
  final String id, number, status, branchId, branchName;
  final String? customerId, customerName, soldAt, invoiceId, invoiceNumber;
  final FixedDecimal total;
  bool get isDraft => status == 'draft';
  static List<SalesOrderSummary> list(Json json) =>
      _rows(json, 'data', SalesOrderSummary.fromJson);
}

class SalesItem {
  SalesItem.fromJson(Json json)
    : id = _id(json, 'id'),
      orderId = _id(json, 'order_id'),
      lotId = _id(json, 'lot_id'),
      name = _text(json, 'product_name'),
      code = _text(json, 'product_code'),
      lotNo = _text(json, 'lot_no'),
      quantity = _number(json, 'quantity', 3, 15),
      price = _money(json, 'unit_price'),
      discount = _money(json, 'discount_amount'),
      net = _money(json, 'line_total'),
      taxRate = _rate(json, 'tax_rate_snapshot'),
      tax = _optionalMoney(json, 'tax_amount'),
      unitCost = json['unit_cost_snapshot'] == null
          ? null
          : _number(json, 'unit_cost_snapshot', 6, 12),
      costTotal = _optionalMoney(json, 'cost_total') {
    if (quantity.atoms <= BigInt.zero) {
      throw const FormatException('Số lượng phải dương.');
    }
  }
  final String id, orderId, lotId, name, code, lotNo;
  final FixedDecimal quantity, price, discount, net;
  final FixedDecimal? taxRate, tax, unitCost, costTotal;
}

class SalesOrderDetail {
  SalesOrderDetail._(Json json, this.items)
    : order = SalesOrderSummary.fromJson(json),
      createdBy = _id(json, 'created_by'),
      warehouseId = _id(json, 'warehouse_id'),
      customerPhone = _optionalText(json, 'customer_phone'),
      customerAddress = _optionalText(json, 'customer_address'),
      branchAddress = _optionalText(json, 'branch_address'),
      seasonLabel = _optionalText(json, 'season_label'),
      issuedAt = _optionalText(json, 'issued_at'),
      subtotal = _optionalMoney(json, 'subtotal'),
      discount = _optionalMoney(json, 'invoice_discount_amount'),
      tax = _optionalMoney(json, 'invoice_tax_amount'),
      paid = _optionalMoney(json, 'paid_amount'),
      remaining = _optionalMoney(json, 'remaining_amount') {
    if (items.any((item) => item.orderId != order.id)) {
      throw const FormatException('Dòng không thuộc đơn.');
    }
  }
  factory SalesOrderDetail.fromJson(Json json) => SalesOrderDetail._(
    json['data'] as Json,
    _rows(json, 'items', SalesItem.fromJson),
  );
  final SalesOrderSummary order;
  final List<SalesItem> items;
  final String createdBy, warehouseId;
  final String? customerPhone,
      customerAddress,
      branchAddress,
      seasonLabel,
      issuedAt;
  final FixedDecimal? subtotal, discount, tax, paid, remaining;
  FixedDecimal? get draftTotal {
    if (items.isEmpty || items.any((item) => item.tax == null)) return null;
    return items.fold<FixedDecimal>(
      FixedDecimal.zero(2),
      (sum, item) => sum + item.net + item.tax!,
    );
  }

  FixedDecimal? get displayedTotal => order.isDraft ? draftTotal : order.total;
}

String saleDate(String? value) {
  final parsed = value == null ? null : DateTime.tryParse(value);
  if (parsed == null) return 'Chưa có thời điểm xác nhận';
  final local = parsed.toUtc().add(const Duration(hours: 7));
  String pad(int number) => number.toString().padLeft(2, '0');
  return '${pad(local.day)}/${pad(local.month)}/${local.year} • ${pad(local.hour)}:${pad(local.minute)}';
}
