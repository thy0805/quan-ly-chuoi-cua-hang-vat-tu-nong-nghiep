import 'package:flutter_test/flutter_test.dart';
import 'package:klcn186_mobile/core/numbers.dart';

void main() {
  test(
    'BIGINT stays String including above JS precision and max signed ID',
    () {
      expect(jsonId('9007199254740993'), '9007199254740993');
      expect(jsonId('9223372036854775807'), '9223372036854775807');
      for (final value in [
        null,
        1,
        9007199254740993.0,
        '0',
        '-1',
        '01',
        '1.0',
        '1e3',
        '9223372036854775808',
        '1/confirm',
        '1\n',
      ]) {
        expect(() => jsonId(value), throwsFormatException);
      }
    },
  );
  test('decimal exact maximum, scale alignment and Vietnamese display', () {
    final value = FixedDecimal.parse('9999999999999999.99', scale: 2);
    expect(
      (value + FixedDecimal.parse('0.01', scale: 2)).toString(),
      '10000000000000000.00',
    );
    expect(value.vnd, '9.999.999.999.999.999,99 ₫');
    expect(FixedDecimal.parse('2.125', scale: 3).vietnamese, '2,125');
    expect(
      (FixedDecimal.parse('1.2', scale: 2) +
              FixedDecimal.parse('0.001', scale: 3))
          .toString(),
      '1.201',
    );
    expect(FixedDecimal.parse('0', scale: 2).vnd, '0 ₫');
  });
  test(
    'decimal refuses exponent, whitespace, excess precision and overflow',
    () {
      for (final text in [
        '1e2',
        ' 1',
        '1 ',
        '1\n',
        'NaN',
        '.5',
        '1.001',
        '10000000000000000.00',
      ]) {
        expect(() => FixedDecimal.parse(text, scale: 2), throwsFormatException);
      }
    },
  );
  test('half up rounding including negative ties uses exact atoms', () {
    expect(
      FixedDecimal.parse('1.005', scale: 3).roundedTo(2).toString(),
      '1.01',
    );
    expect(
      FixedDecimal.parse('-1.005', scale: 3).roundedTo(2).toString(),
      '-1.01',
    );
    expect(
      FixedDecimal.parse('1.004', scale: 3).roundedTo(2).toString(),
      '1.00',
    );
  });
  test('line money rounds gross then tax and supports fractional quantity', () {
    final line = LineAmounts(
      price: FixedDecimal.parse('10.05', scale: 2),
      quantity: FixedDecimal.parse('0.333', scale: 3),
      discount: FixedDecimal.parse('0.05', scale: 2),
      taxRate: FixedDecimal.parse('8', scale: 2),
    );
    expect(line.gross.toString(), '3.35');
    expect(line.net.toString(), '3.30');
    expect(line.tax.toString(), '0.26');
    expect(line.total.toString(), '3.56');
  });
  test(
    'line refuses negative price, zero quantity, excess discount or tax',
    () {
      for (final values in [
        ['-1', '1', '0', '0'],
        ['1', '0', '0', '0'],
        ['1', '1', '2', '0'],
        ['1', '1', '0', '100.01'],
      ]) {
        expect(
          () => LineAmounts(
            price: FixedDecimal.parse(values[0], scale: 2),
            quantity: FixedDecimal.parse(values[1], scale: 3),
            discount: FixedDecimal.parse(values[2], scale: 2),
            taxRate: FixedDecimal.parse(values[3], scale: 2),
          ),
          throwsFormatException,
        );
      }
    },
  );
}
