import 'package:klcn186_mobile/sales/models.dart';

import 'sales_fixtures.dart' as sales;

Json stock({
  String lot = '31',
  String warehouse = '11',
  String price = '100000.00',
  String quantity = '100.125',
  String? tax = '5.00',
  String? expiry,
}) => {
  'warehouse_id': warehouse,
  'lot_id': lot,
  'product_id': '41',
  'quantity': quantity,
  'code': 'NPK',
  'name': 'Phân bón NPK',
  'sale_price': price,
  'tax_rate': tax,
  'lot_no': 'LO$lot',
  'expires_on': expiry,
  'unit_name': 'Bao',
};

Json options({bool twoWarehouses = false}) => {
  ...sales.options(),
  'warehouses': [
    ...(sales.options()['warehouses'] as List),
    if (twoWarehouses)
      {
        'id': '13',
        'branch_id': sales.branchId,
        'chain_id': '1',
        'name': 'Kho phụ',
        'branch_name': 'Thủ Đức',
      },
  ],
  'stock': [
    stock(),
    {...stock(lot: '32', tax: null), 'name': 'Vật tư thiếu thuế'},
    {...stock(lot: '33', expiry: '2000-01-01'), 'name': 'Vật tư hết hạn'},
    {...stock(warehouse: '12'), 'name': 'Vật tư ngoài phạm vi'},
    if (twoWarehouses) stock(warehouse: '13'),
  ],
};
