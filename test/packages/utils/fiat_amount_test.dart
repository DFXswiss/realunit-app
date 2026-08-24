import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/packages/utils/fiat_amount.dart';

void main() {
  group('chargedFiatAmount', () {
    // Quote requests snap to Rappen, never to whole francs.
    test('keeps a dot decimal at Rappen precision (300.75 → 300.75)', () {
      expect(chargedFiatAmount('300.75'), 300.75);
    });

    test('normalises a comma decimal (300,75 → 300.75)', () {
      expect(chargedFiatAmount('300,75'), 300.75);
    });

    test('leaves a whole amount unchanged (300 → 300)', () {
      expect(chargedFiatAmount('300'), 300);
    });

    test('treats an empty string as zero', () {
      expect(chargedFiatAmount(''), 0);
    });

    test('keeps half-franc and sub-franc amounts (0.5 → 0.5, 1.49 → 1.49)', () {
      expect(chargedFiatAmount('0.5'), 0.5);
      expect(chargedFiatAmount('1.49'), 1.49);
    });

    test('does not round leftover Rappen up to the next franc (9999.63 → 9999.63)', () {
      expect(chargedFiatAmount('9999.63'), 9999.63);
    });

    test('throws on structurally invalid input instead of guessing', () {
      expect(() => chargedFiatAmount('1.300,75'), throwsFormatException);
      expect(() => chargedFiatAmount('3,5,7'), throwsFormatException);
    });

    test('reads a thousands group as thousands, not as a 3-decimal fraction', () {
      // CHF/EUR have at most two decimal places, so `10,000` / `105.000`
      // cannot be a Rappen amount — they are ten thousand / one hundred five
      // thousand. Parsing them as 10.0 would quote 1/1000th of the buy.
      expect(chargedFiatAmount('1,000'), 1000);
      expect(chargedFiatAmount('10,000'), 10000);
      expect(chargedFiatAmount('1.000'), 1000);
      expect(chargedFiatAmount('90.000'), 90000);
      expect(chargedFiatAmount('105.000'), 105000);
      expect(chargedFiatAmount("105'000"), 105000);
    });
  });

  group('tryParseFiatAmount', () {
    test('accepts a comma decimal', () {
      expect(tryParseFiatAmount('300,75'), 300.75);
    });

    test('returns null on mixed decimal+grouping input', () {
      expect(tryParseFiatAmount('1.300,75'), isNull);
    });

    test('treats separator + 3 digits as a thousands group', () {
      expect(tryParseFiatAmount('1,000'), 1000);
      expect(tryParseFiatAmount('1.000'), 1000);
      expect(tryParseFiatAmount('105.000'), 105000);
      expect(tryParseFiatAmount('105,000'), 105000);
      expect(tryParseFiatAmount("90'000"), 90000);
    });

    test('still accepts unambiguous decimals', () {
      expect(tryParseFiatAmount('0,5'), 0.5);
      expect(tryParseFiatAmount('1,50'), 1.5);
    });

    test('plain six-digit amounts stay themselves', () {
      expect(tryParseFiatAmount('105000'), 105000);
    });

    test('optional leading minus is still parsed (sell cubit contract)', () {
      expect(tryParseFiatAmount('-100'), -100);
      expect(tryParseFiatAmount('-1.5'), -1.5);
      expect(tryParseFiatAmount('-1,50'), -1.5);
      expect(chargedFiatAmount('-100'), -100);
    });

    test('three fractional digits after a leading zero are not a thousands group', () {
      expect(tryParseFiatAmount('0.105'), isNull);
      expect(tryParseFiatAmount('0,001'), isNull);
      expect(tryParseFiatAmount('0.010'), isNull);
    });

    test('malformed apostrophe or mixed grouping is rejected, not stripped to digits', () {
      expect(tryParseFiatAmount("0'105"), isNull);
      expect(tryParseFiatAmount("1'23"), isNull);
      expect(tryParseFiatAmount('1.000,000'), isNull);
    });
  });
}
