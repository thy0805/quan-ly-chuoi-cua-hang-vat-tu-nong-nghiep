String jsonId(Object? value) {
  if (value is! String ||
      !RegExp(r'^[1-9][0-9]{0,18}$').hasMatch(value) ||
      (value.length == 19 && value.compareTo('9223372036854775807') > 0)) {
    throw const FormatException('ID không hợp lệ.');
  }
  return value;
}

class FixedDecimal implements Comparable<FixedDecimal> {
  const FixedDecimal._(this.atoms, this.scale);

  final BigInt atoms;
  final int scale;

  factory FixedDecimal.zero(int scale) => FixedDecimal._(BigInt.zero, scale);

  factory FixedDecimal.parse(
    String value, {
    required int scale,
    int wholeDigits = 16,
  }) {
    if (scale < 0 || scale > 12 || wholeDigits < 1 || wholeDigits > 32) {
      throw ArgumentError('Độ chính xác không hợp lệ.');
    }
    final match = RegExp(r'^(-?)([0-9]+)(?:\.([0-9]+))?$').firstMatch(value);
    if (match == null ||
        match.group(2)!.length > wholeDigits ||
        (match.group(3)?.length ?? 0) > scale) {
      throw const FormatException('Số thập phân không hợp lệ.');
    }
    final digits =
        '${match.group(2)}${(match.group(3) ?? '').padRight(scale, '0')}';
    final atoms = BigInt.parse(digits);
    return FixedDecimal._(match.group(1) == '-' ? -atoms : atoms, scale);
  }

  FixedDecimal operator +(FixedDecimal other) {
    final target = scale > other.scale ? scale : other.scale;
    return FixedDecimal._(_at(target) + other._at(target), target);
  }

  FixedDecimal operator -(FixedDecimal other) {
    final target = scale > other.scale ? scale : other.scale;
    return FixedDecimal._(_at(target) - other._at(target), target);
  }

  FixedDecimal operator *(FixedDecimal other) =>
      FixedDecimal._(atoms * other.atoms, scale + other.scale);

  FixedDecimal roundedTo(int target) {
    if (target < 0 || target > 12) throw ArgumentError('Sai độ chính xác.');
    if (target >= scale) return FixedDecimal._(_at(target), target);
    final divisor = BigInt.from(10).pow(scale - target);
    var rounded = atoms.abs() ~/ divisor;
    if ((atoms.abs() % divisor) * BigInt.two >= divisor) {
      rounded += BigInt.one;
    }
    return FixedDecimal._(atoms.isNegative ? -rounded : rounded, target);
  }

  FixedDecimal taxAt(FixedDecimal rate) =>
      FixedDecimal._(atoms * rate.atoms, scale + rate.scale + 2).roundedTo(2);

  BigInt _at(int target) => atoms * BigInt.from(10).pow(target - scale);

  @override
  int compareTo(FixedDecimal other) {
    final target = scale > other.scale ? scale : other.scale;
    return _at(target).compareTo(other._at(target));
  }

  @override
  String toString() {
    final digits = atoms.abs().toString().padLeft(scale + 1, '0');
    final sign = atoms.isNegative ? '-' : '';
    if (scale == 0) return '$sign$digits';
    return '$sign${digits.substring(0, digits.length - scale)}.${digits.substring(digits.length - scale)}';
  }

  String get vietnamese {
    final text = toString();
    final parts = text.replaceFirst('-', '').split('.');
    final whole = parts.first.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => '.',
    );
    final fraction = parts.length == 2
        ? parts[1].replaceFirst(RegExp(r'0+$'), '')
        : '';
    return '${atoms.isNegative ? '-' : ''}$whole${fraction.isEmpty ? '' : ',$fraction'}';
  }

  String get vnd => '$vietnamese ₫';
}

class LineAmounts {
  LineAmounts({
    required FixedDecimal price,
    required FixedDecimal quantity,
    required FixedDecimal discount,
    required FixedDecimal taxRate,
  }) {
    if (price.atoms.isNegative ||
        quantity.atoms <= BigInt.zero ||
        discount.atoms.isNegative ||
        taxRate.atoms.isNegative ||
        taxRate.compareTo(FixedDecimal.parse('100', scale: 2)) > 0) {
      throw const FormatException('Dòng tiền không hợp lệ.');
    }
    gross = (price * quantity).roundedTo(2);
    if (discount.compareTo(gross) > 0) {
      throw const FormatException('Chiết khấu vượt tiền dòng.');
    }
    net = gross - discount;
    tax = net.taxAt(taxRate);
    total = net + tax;
  }

  late final FixedDecimal gross;
  late final FixedDecimal net;
  late final FixedDecimal tax;
  late final FixedDecimal total;
}
