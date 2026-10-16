import '../core/numbers.dart';

typedef TransferJson = Map<String, dynamic>;

const transferStatuses = {
  'requested': 'Chờ duyệt',
  'approved': 'Đã duyệt',
  'rejected': 'Từ chối',
  'dispatched': 'Đã xuất kho',
  'received': 'Đã nhận đủ',
  'discrepancy': 'Chênh lệch',
  'reconciled': 'Đã đối soát',
};

String _text(TransferJson json, String key) => json[key] as String;

DateTime _time(Object? value) {
  final date = DateTime.parse(value as String);
  if (!date.isUtc) throw const FormatException('Thiếu múi giờ chứng từ.');
  return date;
}

class TransferSummary {
  TransferSummary.fromJson(TransferJson json)
    : id = jsonId(json['id']),
      number = _text(json, 'transfer_no'),
      status = _text(json, 'status'),
      requestedAt = _time(json['requested_at']),
      fromWarehouseId = jsonId(json['from_warehouse_id']),
      toWarehouseId = jsonId(json['to_warehouse_id']),
      fromBranchId = jsonId(json['from_branch_id']),
      toBranchId = jsonId(json['to_branch_id']),
      fromWarehouseName = _text(json, 'from_warehouse_name'),
      toWarehouseName = _text(json, 'to_warehouse_name'),
      fromBranchName = _text(json, 'from_branch_name'),
      toBranchName = _text(json, 'to_branch_name'),
      requesterName = _text(json, 'requester_name') {
    if (!transferStatuses.containsKey(status)) {
      throw const FormatException('Trạng thái điều chuyển không hỗ trợ.');
    }
  }

  final String id, number, status;
  final DateTime requestedAt;
  final String fromWarehouseId, toWarehouseId, fromBranchId, toBranchId;
  final String fromWarehouseName, toWarehouseName, fromBranchName, toBranchName;
  final String requesterName;

  bool belongsTo(String branchId) =>
      fromBranchId == branchId || toBranchId == branchId;
  String get statusLabel => transferStatuses[status]!;
}

class TransferPage {
  TransferPage._(this.rows, this.current, this.last);
  TransferPage.fromJson(TransferJson json)
    : rows = List.unmodifiable(
        (json['data'] as List).map(
          (row) => TransferSummary.fromJson(row as TransferJson),
        ),
      ),
      current = (json['pagination'] as TransferJson)['current_page'] as int,
      last = (json['pagination'] as TransferJson)['last_page'] as int {
    if (current < 1 || last < current || rows.length > 50) {
      throw const FormatException('Phân trang không hợp lệ.');
    }
    if (rows.map((row) => row.id).toSet().length != rows.length) {
      throw const FormatException('Trùng phiếu trong trang.');
    }
  }

  final List<TransferSummary> rows;
  final int current, last;
  bool get hasNext => current < last;

  TransferPage forBranch(String branchId) => TransferPage._(
    List.unmodifiable(rows.where((row) => row.belongsTo(branchId))),
    current,
    last,
  );
}

FixedDecimal _quantity(TransferJson json, String key) {
  final quantity = FixedDecimal.parse(
    _text(json, key),
    scale: 3,
    wholeDigits: 15,
  );
  if (quantity.atoms.isNegative) {
    throw const FormatException('Số lượng không hợp lệ.');
  }
  return quantity;
}

class TransferLine {
  TransferLine.fromJson(TransferJson json)
    : id = jsonId(json['id']),
      lotId = jsonId(json['lot_id']),
      productName = _text(json, 'product_name'),
      productCode = _text(json, 'product_code'),
      lotNumber = _text(json, 'lot_no'),
      unitName = _text(json, 'unit_name'),
      requested = _quantity(json, 'requested_quantity'),
      dispatched = _quantity(json, 'dispatched_quantity'),
      received = _quantity(json, 'received_quantity'),
      supplemental = _quantity(json, 'supplemental_received_quantity'),
      returned = _quantity(json, 'returned_quantity'),
      lost = _quantity(json, 'lost_quantity');

  final String id, lotId, productName, productCode, lotNumber, unitName;
  final FixedDecimal requested,
      dispatched,
      received,
      supplemental,
      returned,
      lost;
}

class TransferDetail {
  TransferDetail.fromJson(TransferJson json)
    : transfer = TransferSummary.fromJson(json['data'] as TransferJson),
      items = List.unmodifiable(
        (json['items'] as List).map(
          (row) => TransferLine.fromJson(row as TransferJson),
        ),
      ),
      times = Map.unmodifiable({
        for (final key in [
          'approved_at',
          'rejected_at',
          'dispatched_at',
          'received_at',
          'reconciled_at',
        ])
          if ((json['data'] as TransferJson)[key] != null)
            key: _time((json['data'] as TransferJson)[key]),
      }),
      rejectionReason =
          (json['data'] as TransferJson)['rejection_reason'] as String?,
      reconciliationReason =
          (json['data'] as TransferJson)['reconciliation_reason'] as String? {
    if (items.map((line) => line.id).toSet().length != items.length ||
        items.map((line) => line.lotId).toSet().length != items.length) {
      throw const FormatException('Trùng dòng vật tư.');
    }
  }

  final TransferSummary transfer;
  final List<TransferLine> items;
  final Map<String, DateTime> times;
  final String? rejectionReason, reconciliationReason;
}

String transferDate(DateTime date) {
  final vn = date.toUtc().add(const Duration(hours: 7));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(vn.day)}/${two(vn.month)}/${vn.year} ${two(vn.hour)}:${two(vn.minute)}';
}
