import 'package:klcn186_mobile/sales/models.dart';

const branchId = '9007199254740995';
const orderId = '9007199254740997';
const draftId = '9007199254740999';

Json summary({bool draft = false, String branch = branchId}) => {
  'id': draft ? draftId : orderId,
  'order_no': draft ? 'BH-20261012-002' : 'BH-20261012-001',
  'status': draft ? 'draft' : 'confirmed',
  'total_amount': draft ? '0.00' : '257400.00',
  'branch_id': branch,
  'branch_name': 'Chi nhánh Thủ Đức',
  'customer_id': draft ? null : '9007199254741001',
  'customer_name': draft ? null : 'Nguyễn Văn Bình',
  'sold_at': '2026-10-12T03:30:00Z',
  'invoice_id': draft ? null : '9007199254741003',
  'invoice_no': draft ? null : 'HD-20261012-001',
};

Json item({bool draft = false, bool missingTax = false}) => {
  'id': '9007199254741005',
  'order_id': draft ? draftId : orderId,
  'lot_id': '9007199254741007',
  'product_name': 'Phân bón NPK 16-16-8',
  'product_code': 'NPK-168',
  'lot_no': 'LO-2026-08',
  'quantity': '2.000',
  'unit_price': '125000.00',
  'discount_amount': '2500.00',
  'line_total': '247500.00',
  'tax_rate_snapshot': missingTax ? null : '4.00',
  'tax_amount': missingTax ? null : '9900.00',
  'unit_cost_snapshot': draft ? null : '80000.123456',
  'cost_total': draft ? null : '160000.25',
};

Json detail({bool draft = false, bool missingTax = false}) => {
  'data': {
    ...summary(draft: draft),
    'created_by': '9007199254740993',
    'warehouse_id': '11',
    'customer_phone': draft ? null : '0900000000',
    'customer_address': null,
    'branch_address': 'Thủ Đức',
    'season_label': null,
    'issued_at': draft ? null : '2026-10-12T03:30:00Z',
    'subtotal': draft ? null : '250000.00',
    'invoice_discount_amount': draft ? null : '2500.00',
    'invoice_tax_amount': draft ? null : '9900.00',
    'paid_amount': draft ? null : '100000.00',
    'remaining_amount': draft ? null : '157400.00',
  },
  'items': [item(draft: draft, missingTax: missingTax)],
};

Json history() => {
  'data': [summary(), summary(draft: true), summary(branch: '2')],
};

Json options() => {
  'warehouses': [
    {
      'id': '11',
      'branch_id': branchId,
      'chain_id': '1',
      'name': 'Kho bán',
      'branch_name': 'Thủ Đức',
    },
    {
      'id': '12',
      'branch_id': '2',
      'chain_id': '2',
      'name': 'Kho khác',
      'branch_name': 'Khác',
    },
  ],
  'customers': [
    {
      'id': '21',
      'chain_id': '1',
      'name': 'Khách cùng chuỗi',
      'customer_type': 'individual',
    },
    {
      'id': '22',
      'chain_id': '2',
      'name': 'Khách chuỗi khác',
      'customer_type': 'individual',
    },
  ],
  'stock': [
    for (final warehouse in ['11', '12'])
      {
        'warehouse_id': warehouse,
        'lot_id': '31',
        'quantity': '100.125',
        'product_id': '41',
        'code': 'NPK',
        'name': 'Phân bón',
        'sale_price': '125000.00',
        'tax_rate': null,
        'lot_no': 'LO01',
        'expires_on': null,
        'unit_name': 'Bao',
      },
  ],
};
