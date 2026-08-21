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
}
