import 'package:flutter_test/flutter_test.dart';
import 'package:seneb_law/core/money/money.dart';

void main() {
  group('Money integer parsing and arithmetic', () {
    test('accepts Arabic/Persian digits and validated grouping', () {
      expect(Money.parse(' ١٬٢٣٤٫٥٠ ').amountMinor, 123450);
      expect(Money.parse('۱۲۳۴.۵۰').amountMinor, 123450);
      expect(Money.parse('1,234.50').amountMinor, 123450);
      expect(Money.parse('-0.50').amountMinor, -50);
      expect(Money.parse('1.0000').amountMinor, 100);
    });

    test('rejects malformed grouping and fractional cents', () {
      for (final text in [
        '',
        'Infinity',
        'NaN',
        '1,23',
        '1٬234,567',
        '1 234',
        '1.005',
        '1e2',
        '1.0.0',
        '.5',
      ]) {
        expect(() => Money.parse(text), throwsFormatException, reason: text);
      }
    });

    test(
      'keeps cents exact and formats minimum signed64 without abs overflow',
      () {
        expect((Money.parse('0.10') + Money.parse('0.20')).amountMinor, 30);
        expect(
          (Money.parse('1.00') - Money.parse('1.50')).toDecimalString(),
          '-0.50',
        );
        expect(
          Money.parse('92233720368547758.07').amountMinor,
          9223372036854775807,
        );
        expect(
          Money.parse('-92233720368547758.08').toDecimalString(),
          '-92233720368547758.08',
        );
        expect(() => Money.parse('92233720368547758.08'), throwsRangeError);
        expect(() => Money.parse('-92233720368547758.09'), throwsRangeError);
        expect(
          () => Money.fromMinor(9223372036854775807) + Money.fromMinor(1),
          throwsRangeError,
        );
        expect(
          () => Money.fromMinor(-9223372036854775808) - Money.fromMinor(1),
          throwsRangeError,
        );
      },
    );

    test('only EGP is enabled', () {
      expect(() => Money.parse('1', currency: 'USD'), throwsArgumentError);
      expect(() => Money.fromMinor(100, currency: 'usd'), throwsArgumentError);
    });
  });

  group('Legacy conversion proposals', () {
    test(
      'rounds decimal halves away from zero and retains signed residual',
      () {
        final one = LegacyMoneyConversion.fromDouble(1.005);
        expect(one.sourceText, '1.005');
        expect(one.amountMinor, 101);
        expect(one.roundingResidual, '-0.005');
        expect(one.hasSubcentPrecision, isTrue);
        expect(LegacyMoneyConversion.fromDouble(2.675).amountMinor, 268);
        final negative = LegacyMoneyConversion.fromDouble(-1.005);
        expect(negative.amountMinor, -101);
        expect(negative.roundingResidual, '0.005');
        expect(negative.isNegative, isTrue);
        expect(LegacyMoneyConversion.fromDecimal('1.004').amountMinor, 100);
        expect(
          LegacyMoneyConversion.fromDecimal('1.004').roundingResidual,
          '0.004',
        );
      },
    );

    test('handles exact cents and scientific source notation', () {
      expect(LegacyMoneyConversion.fromDouble(0.1).amountMinor, 10);
      expect(
        LegacyMoneyConversion.fromDouble(100).hasSubcentPrecision,
        isFalse,
      );
      expect(LegacyMoneyConversion.fromDouble(100).roundingResidual, '0');
      expect(LegacyMoneyConversion.fromDecimal('1.005e2').amountMinor, 10050);
      expect(
        LegacyMoneyConversion.fromDecimal('1e-7').roundingResidual,
        '0.0000001',
      );
      expect(
        LegacyMoneyConversion.fromDouble(double.minPositive).amountMinor,
        0,
      );
    });

    test('invalid or oversized sources have no proposed posting value', () {
      for (final value in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        final result = LegacyMoneyConversion.fromDouble(value);
        expect(result.amountMinor, isNull);
        expect(result.errorCode, 'NON_FINITE');
      }
      final huge = LegacyMoneyConversion.fromDouble(double.maxFinite);
      expect(huge.amountMinor, isNull);
      expect(huge.errorCode, 'OUT_OF_RANGE');
      expect(
        LegacyMoneyConversion.fromDecimal('bad').errorCode,
        'INVALID_DECIMAL',
      );
      expect(
        LegacyMoneyConversion.fromDecimal('1e999999').errorCode,
        'OUT_OF_RANGE',
      );
      expect(
        LegacyMoneyConversion.fromDecimal('-92233720368547758.08').amountMinor,
        -9223372036854775808,
      );
    });
  });
}
