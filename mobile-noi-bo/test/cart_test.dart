import 'package:flutter_test/flutter_test.dart';
import 'package:klcn186_mobile/sales/cart.dart';
import 'package:klcn186_mobile/sales/models.dart';

import 'cart_fixtures.dart' as fixture;
import 'sales_fixtures.dart' as sales;

SalesCart cart({bool twoWarehouses = false}) => SalesCart(
  SalesOptions.fromJson(fixture.options(twoWarehouses: twoWarehouses)),
  sales.branchId,
  '1',
)..selectWarehouse('11');

void main() {
  final now = DateTime.utc(2026, 10, 12);
  test(
    'scope rejects warehouses and customers outside selected branch/chain',
    () {
      final value = cart();
      expect(value.options.warehouses.single.id, '11');
      expect(value.options.customers.single.id, '21');
      expect(() => value.selectWarehouse('12'), throwsFormatException);
      expect(() => value.selectCustomer('22'), throwsFormatException);
      expect(
        () =>
            value.add(SalesStock.fromJson(fixture.stock(warehouse: '12')), now),
        throwsFormatException,
      );
      value.selectCustomer('21');
      value.selectCustomer(null);
      expect(value.customerId, isNull);
    },
  );
  test('same warehouse retains lines; changing warehouse clears lines', () {
    final value = cart(twoWarehouses: true);
    value.add(value.stock.first, now);
    value.selectWarehouse('11');
    expect(value.lines, hasLength(1));
    value.selectWarehouse('13');
    expect(value.lines, isEmpty);
    expect(value.stock.single.warehouseId, '13');
  });
  test(
    'duplicate, missing tax, expired, invalid date and zero stock cannot enter cart',
    () {
      final value = cart();
      value.add(value.stock.first, now);
      for (final item in value.stock) {
        expect(() => value.add(item, now), throwsFormatException);
      }
      for (final json in [
        fixture.stock(quantity: '0'),
        fixture.stock(expiry: '2026-02-30'),
        fixture.stock(expiry: 'bad'),
      ]) {
        expect(stockUnavailable(SalesStock.fromJson(json), now), isNotNull);
      }
    },
  );
  test(
    'expires today is allowed until midnight Vietnam; null expiry allowed',
    () {
      final item = SalesStock.fromJson(fixture.stock(expiry: '2026-10-12'));
      expect(
        stockUnavailable(item, DateTime.utc(2026, 10, 12, 16, 59, 59)),
        isNull,
      );
      expect(
        stockUnavailable(item, DateTime.utc(2026, 10, 12, 17)),
        contains('hết hạn'),
      );
      expect(
        stockUnavailable(SalesStock.fromJson(fixture.stock()), now),
        isNull,
      );
    },
  );
  test(
    'fractional stock uses default quantity within stock and exact decimal input',
    () {
      final line = CartLine(
        SalesStock.fromJson(fixture.stock(quantity: '0.125')),
      );
      expect(line.quantityText, '0.125');
      expect(line.quantityError, isNull);
      expect(cartNumber('1,250', quantity: true).toString(), '1.250');
      expect(
        cartNumber('9007199254740993.01', quantity: false).toString(),
        '9007199254740993.01',
      );
      for (final text in [
        '0',
        '-1',
        '1.0001',
        '1000000000000000',
        '1e3',
        '1.000,5',
        '',
      ]) {
        expect(() => cartNumber(text, quantity: true), throwsFormatException);
      }
      for (final text in ['-1', '0.001', '10000000000000000', 'NaN', '']) {
        expect(() => cartNumber(text, quantity: false), throwsFormatException);
      }
    },
  );
  test(
    'quantity above snapshot and discount above gross block totals without fallback zero',
    () {
      final value = cart();
      value.add(value.stock.first, now);
      final line = value.lines.single;
      line.quantityText = '100.126';
      expect(line.quantityError, contains('Vượt tồn'));
      expect(() => value.totals(now), throwsFormatException);
      line.quantityText = '2';
      line.discountText = '200000.01';
      expect(line.discountError, contains('vượt'));
      line.discountText = '200000.00';
      expect(value.totals(now).total.toString(), '0.00');
    },
  );
  test(
    'approved formula gross200000 discount20000 net180000 tax9000 total189000',
    () {
      final value = cart();
      value.add(value.stock.first, now);
      value.lines.single.quantityText = '2';
      value.lines.single.discountText = '20000';
      final total = value.totals(now);
      expect(total.gross.toString(), '200000.00');
      expect(total.discount.toString(), '20000.00');
      expect(total.net.toString(), '180000.00');
      expect(total.tax.toString(), '9000.00');
      expect(total.total.toString(), '189000.00');
    },
  );
  test('round half-up each line tax, not tax on combined net', () {
    final lines = [
      for (var i = 0; i < 2; i++)
        CartLine(
          SalesStock.fromJson(fixture.stock(price: '0.10', tax: '5.00')),
        ),
    ];
    final total = CartTotals(lines, now);
    expect(total.tax.toString(), '0.02');
    expect(total.total.toString(), '0.22');
    final fractional = CartLine(
      SalesStock.fromJson(fixture.stock(price: '1.00', tax: '0.00')),
    )..quantityText = '0.005';
    expect(fractional.amounts(now).gross.toString(), '0.01');
  });
  test(
    'money product, tax-inclusive total and sum cannot exceed numeric limit',
    () {
      final line = CartLine(
        SalesStock.fromJson(
          fixture.stock(price: '9999999999999999.99', tax: '0.00'),
        ),
      )..quantityText = '2';
      expect(line.quantityError, contains('giới hạn'));
      line.quantityText = '1';
      expect(line.amounts(now).total.toString(), '9999999999999999.99');
      expect(() => CartTotals([line, line], now), throwsFormatException);
      final taxed = CartLine(
        SalesStock.fromJson(fixture.stock(price: '9999999999999999.99')),
      );
      expect(() => taxed.amounts(now), throwsFormatException);
    },
  );
  test('cart caps at 50 lots and removal permits adding again', () {
    final json = fixture.options()
      ..['stock'] = [for (var i = 1; i <= 51; i++) fixture.stock(lot: '$i')];
    final value = SalesCart(SalesOptions.fromJson(json), sales.branchId, '1')
      ..selectWarehouse('11');
    for (final item in value.stock.take(50)) {
      value.add(item, now);
    }
    expect(() => value.add(value.stock.last, now), throwsFormatException);
    value.remove(value.lines.first);
    value.add(value.stock.last, now);
    expect(value.lines, hasLength(50));
    value.clear();
    expect(value.totals(now).total.toString(), '0.00');
  });
}
