/// Integer-only EGP amounts. Floating-point amounts are confined to legacy import.
final class Money {
  static final BigInt _minMinor = -(BigInt.one << 63);
  static final BigInt _maxMinor = (BigInt.one << 63) - BigInt.one;

  final int amountMinor;
  final String currency;

  Money.fromMinor(this.amountMinor, {this.currency = 'EGP'}) {
    _validateCurrency(currency);
    _checked(BigInt.from(amountMinor));
  }

  /// Accepts Arabic/Persian digits, Arabic decimal/group separators and ASCII
  /// decimal notation. Sub-cent input is rejected instead of rounded silently.
  factory Money.parse(String text, {String currency = 'EGP'}) {
    _validateCurrency(currency);
    final normalized = _normalizeUserInput(text);
    final parsed = _Decimal.parse(normalized, allowScientific: false);
    final rounded = parsed.toMinor();
    if (rounded.residualCoefficient != BigInt.zero) {
      throw const FormatException('المبلغ يجب ألا يتجاوز منزلتين عشريتين.');
    }
    return Money.fromMinor(_checked(rounded.minor), currency: currency);
  }

  Money operator +(Money other) {
    _requireSameCurrency(other);
    return Money.fromMinor(
      _checked(BigInt.from(amountMinor) + BigInt.from(other.amountMinor)),
      currency: currency,
    );
  }

  Money operator -(Money other) {
    _requireSameCurrency(other);
    return Money.fromMinor(
      _checked(BigInt.from(amountMinor) - BigInt.from(other.amountMinor)),
      currency: currency,
    );
  }

  String toDecimalString() =>
      _formatDecimal(BigInt.from(amountMinor), 2, trimTrailingZeros: false);

  void _requireSameCurrency(Money other) {
    if (currency != other.currency) {
      throw ArgumentError('لا يمكن دمج عملتين مختلفتين.');
    }
  }

  static void _validateCurrency(String currency) {
    if (currency != 'EGP') {
      throw ArgumentError.value(currency, 'currency', 'Only EGP is enabled.');
    }
  }

  static int _checked(BigInt value) {
    if (value < _minMinor || value > _maxMinor) {
      throw RangeError('المبلغ خارج النطاق المسموح.');
    }
    return value.toInt();
  }

  @override
  bool operator ==(Object other) =>
      other is Money &&
      amountMinor == other.amountMinor &&
      currency == other.currency;

  @override
  int get hashCode => Object.hash(amountMinor, currency);
}

/// A proposal for review, never an instruction to post a ledger entry.
/// Retain the source SQLite row and pre-migration database in addition to this
/// canonical decimal representation: a binary double cannot recover user intent.
final class LegacyMoneyConversion {
  final String sourceText;
  final int? amountMinor;
  final String? roundingResidual;
  final bool hasSubcentPrecision;
  final bool isNegative;
  final String? errorCode;

  const LegacyMoneyConversion._({
    required this.sourceText,
    required this.amountMinor,
    required this.roundingResidual,
    required this.hasSubcentPrecision,
    required this.isNegative,
    required this.errorCode,
  });

  factory LegacyMoneyConversion.fromDouble(double value) {
    if (!value.isFinite) {
      return LegacyMoneyConversion._invalid(value.toString(), 'NON_FINITE');
    }
    return LegacyMoneyConversion.fromDecimal(value.toString());
  }

  factory LegacyMoneyConversion.fromDecimal(String sourceText) {
    try {
      final parsed = _Decimal.parse(sourceText, allowScientific: true);
      final rounded = parsed.toMinor();
      final minor = Money._checked(rounded.minor);
      return LegacyMoneyConversion._(
        sourceText: sourceText,
        amountMinor: minor,
        roundingResidual: _formatDecimal(
          rounded.residualCoefficient,
          rounded.residualScale,
        ),
        hasSubcentPrecision: rounded.residualCoefficient != BigInt.zero,
        isNegative: parsed.coefficient.isNegative,
        errorCode: null,
      );
    } on RangeError {
      return LegacyMoneyConversion._invalid(sourceText, 'OUT_OF_RANGE');
    } on FormatException {
      return LegacyMoneyConversion._invalid(sourceText, 'INVALID_DECIMAL');
    }
  }

  factory LegacyMoneyConversion._invalid(String text, String error) =>
      LegacyMoneyConversion._(
        sourceText: text,
        amountMinor: null,
        roundingResidual: null,
        hasSubcentPrecision: false,
        isNegative: text.startsWith('-'),
        errorCode: error,
      );
}

String _normalizeUserInput(String input) {
  final buffer = StringBuffer();
  for (final rune in input.trim().runes) {
    if (rune >= 0x660 && rune <= 0x669) {
      buffer.writeCharCode(0x30 + rune - 0x660);
    } else if (rune >= 0x6f0 && rune <= 0x6f9) {
      buffer.writeCharCode(0x30 + rune - 0x6f0);
    } else {
      buffer.writeCharCode(rune == 0x66b ? 0x2e : rune);
    }
  }
  final value = buffer.toString();
  if (!value.contains(',') && !value.contains('\u066c')) return value;
  if (value.contains(',') && value.contains('\u066c')) {
    throw const FormatException('استخدم فاصل آلاف واحدًا.');
  }
  final separator = value.contains(',') ? ',' : '\u066c';
  final grouped = RegExp(
    '^[+-]?[0-9]{1,3}(?:$separator[0-9]{3})+(?:\\.[0-9]+)?\$',
  );
  if (!grouped.hasMatch(value)) {
    throw const FormatException('راجع تنسيق فواصل الآلاف.');
  }
  return value.replaceAll(separator, '');
}

final class _Decimal {
  final BigInt coefficient;
  final int scale;

  const _Decimal(this.coefficient, this.scale);

  factory _Decimal.parse(String text, {required bool allowScientific}) {
    if (text.length > 1024) throw RangeError('Decimal input is too long.');
    final pattern = allowScientific
        ? r'^([+-]?)([0-9]+)(?:\.([0-9]+))?(?:[eE]([+-]?[0-9]+))?$'
        : r'^([+-]?)([0-9]+)(?:\.([0-9]+))?$';
    final match = RegExp(pattern).firstMatch(text);
    if (match == null) throw const FormatException('أدخل مبلغًا صحيحًا.');
    final fraction = match.group(3) ?? '';
    final exponentText = allowScientific ? match.group(4) : null;
    final exponent = exponentText == null ? 0 : int.tryParse(exponentText);
    // All finite source doubles fit comfortably inside these bounds.
    if (exponent == null || exponent.abs() > 400) {
      throw RangeError('Decimal exponent is out of range.');
    }
    final sign = match.group(1) == '-' ? '-' : '';
    return _Decimal(
      BigInt.parse('$sign${match.group(2)}$fraction'),
      fraction.length - exponent,
    );
  }

  _MinorResult toMinor() {
    if (scale <= 2) {
      return _MinorResult(
        coefficient * BigInt.from(10).pow(2 - scale),
        BigInt.zero,
        0,
      );
    }
    final divisor = BigInt.from(10).pow(scale - 2);
    final absolute = coefficient.abs();
    var rounded = absolute ~/ divisor;
    if (absolute.remainder(divisor) * BigInt.two >= divisor) {
      rounded += BigInt.one;
    }
    if (coefficient.isNegative) rounded = -rounded;
    return _MinorResult(rounded, coefficient - rounded * divisor, scale);
  }
}

final class _MinorResult {
  final BigInt minor;
  final BigInt residualCoefficient;
  final int residualScale;

  const _MinorResult(this.minor, this.residualCoefficient, this.residualScale);
}

String _formatDecimal(
  BigInt coefficient,
  int scale, {
  bool trimTrailingZeros = true,
}) {
  if (coefficient == BigInt.zero && trimTrailingZeros) return '0';
  final sign = coefficient.isNegative ? '-' : '';
  final digits = coefficient.abs().toString();
  if (scale == 0) return '$sign$digits';
  final padded = digits.padLeft(scale + 1, '0');
  final whole = padded.substring(0, padded.length - scale);
  var fraction = padded.substring(padded.length - scale);
  if (trimTrailingZeros) fraction = fraction.replaceFirst(RegExp(r'0+$'), '');
  return fraction.isEmpty ? '$sign$whole' : '$sign$whole.$fraction';
}
