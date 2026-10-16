const branchId = '9007199254740995';
const transferId = '9007199254741011';

Map<String, dynamic> summary({
  String id = transferId,
  String status = 'requested',
  String from = branchId,
  String to = '2',
}) => {
  'id': id,
  'transfer_no': 'DC-20261016-$id',
  'status': status,
  'requested_at': '2026-10-15 18:30:00+00',
  'requested_by': '9007199254740993',
  'approved_by': null,
  'from_warehouse_id': '11',
  'to_warehouse_id': '12',
  'from_branch_id': from,
  'to_branch_id': to,
  'from_branch_name': 'Chi nhánh Thủ Đức',
  'to_branch_name': 'Chi nhánh Bình Tân',
  'from_warehouse_name': 'Kho nguồn vật tư',
  'to_warehouse_name': 'Kho đích vật tư',
  'requester_name': 'nhanvien',
};

Map<String, dynamic> line() => {
  'id': '9007199254741013',
  'lot_id': '9007199254741015',
  'product_name': 'Phân bón NPK 16-16-8',
  'product_code': 'NPK-168',
  'lot_no': 'LO-2026-10',
  'unit_name': 'bao',
  'requested_quantity': '2.125',
  'dispatched_quantity': '2.000',
  'received_quantity': '1.000',
  'supplemental_received_quantity': '0.500',
  'returned_quantity': '0.250',
  'lost_quantity': '0.250',
};

Map<String, dynamic> detail({
  String id = transferId,
  String status = 'reconciled',
  String from = branchId,
  String to = '2',
}) => {
  'data': {
    ...summary(id: id, status: status, from: from, to: to),
    'chain_id': '1',
    'approved_at': '2026-10-16T02:00:00Z',
    'dispatched_at': '2026-10-16T03:00:00Z',
    'received_at': '2026-10-16T04:00:00Z',
    'rejected_at': null,
    'reconciled_at': '2026-10-16T05:00:00Z',
    'rejection_reason': null,
    'reconciliation_reason': 'Đã nhận bổ sung, hoàn kho và ghi nhận hao hụt.',
    'can_approve': true,
    'can_reject': true,
    'can_dispatch': true,
    'can_receive': true,
    'can_reconcile': true,
  },
  'items': [line()],
};

Map<String, dynamic> page({
  List<Map<String, dynamic>>? rows,
  int current = 1,
  int last = 1,
}) => {
  'data': rows ?? [summary()],
  'pagination': {'current_page': current, 'last_page': last, 'total': 100},
};
