import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/packages/utils/fiat_amount.dart';

void main() {
  group('chargedFiatAmount', () {
    // The quote is always requested with this rounded integer, so the SEPA
    // transfer / QR the API builds encodes it.
    test('rounds a dot decimal to the charged integer (300.75 → 301)', () {
      expect(chargedFiatAmount('300.75'), 301);
    });

    test('normalises a comma decimal (300,75 → 301)', () {
      expect(chargedFiatAmount('300,75'), 301);
    });

    test('leaves a whole amount unchanged (300 → 300)', () {
      expect(chargedFiatAmount('300'), 300);
    });

    test('treats an empty string as zero', () {
      expect(chargedFiatAmount(''), 0);
    });

    test('rounds half away from zero and down below the half (0.5 → 1, 1.49 → 1)', () {
      expect(chargedFiatAmount('0.5'), 1);
      expect(chargedFiatAmount('1.49'), 1);
    });

    test('throws on structurally invalid input instead of guessing', () {
      expect(() => chargedFiatAmount('1.300,75'), throwsFormatException);
      expect(() => chargedFiatAmount('3,5,7'), throwsFormatException);
    });

    test('throws on grouping-ambiguous input instead of charging 1/1000th', () {
      // `10,000` typed as ten thousand would otherwise parse as 10.0 and
      // silently request a quote for ten francs.
      expect(() => chargedFiatAmount('1,000'), throwsFormatException);
      expect(() => chargedFiatAmount('10,000'), throwsFormatException);
      expect(() => chargedFiatAmount('1.000'), throwsFormatException);
    });
  });

  group('tryParseFiatAmount', () {
    test('accepts a comma decimal', () {
      expect(tryParseFiatAmount('300,75'), 300.75);
    });

    test('returns null on multi-separator input', () {
      expect(tryParseFiatAmount('1.300,75'), isNull);
    });

    test('returns null on grouping-ambiguous input (separator + 3 digits)', () {
      expect(tryParseFiatAmount('1,000'), isNull);
      expect(tryParseFiatAmount('1.000'), isNull);
    });

    test('still accepts unambiguous decimals', () {
      expect(tryParseFiatAmount('0,5'), 0.5);
      expect(tryParseFiatAmount('1,50'), 1.5);
    });
  });

  group('normalizeFiatInput', () {
    test('strips a lone thousands group', () {
      expect(normalizeFiatInput('1.000'), '1000');
      expect(normalizeFiatInput('1,000'), '1000');
      expect(normalizeFiatInput('10.000'), '10000');
      expect(normalizeFiatInput('10,000'), '10000');
    });

    test('leaves every other input unchanged', () {
      expect(normalizeFiatInput('300'), '300');
      expect(normalizeFiatInput('300,75'), '300,75');
      expect(normalizeFiatInput('0,5'), '0,5');
      expect(normalizeFiatInput('1.300,75'), '1.300,75');
      expect(normalizeFiatInput('3,5,7'), '3,5,7');
    });

    test('leaves partial thousands-group input unchanged', () {
      expect(normalizeFiatInput('1.'), '1.');
      expect(normalizeFiatInput('1.0'), '1.0');
      expect(normalizeFiatInput('1.00'), '1.00');
    });
  });
}
