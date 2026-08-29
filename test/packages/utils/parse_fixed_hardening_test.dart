import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/packages/utils/parse_fixed.dart';

/// Audit #657 P10 B12: parseFixed had no input validation — '' crashed with a
/// RangeError, and a lone '-', non-numeric or leading-dot input escaped as a
/// raw FormatException from BigInt.parse. Invalid input must throw a
/// deliberate [Exception] (not an [Error], not an accidental
/// [FormatException]). Leading-dot input stays rejected — the existing
/// parse_fixed_test.dart pins that spec ('.1' must fail).
void main() {
  group('parseFixed input validation (audit #657 P10 B12)', () {
    test('empty string throws a deliberate Exception, not a RangeError', () {
      expect(
        () => parseFixed('', 2),
        throwsA(allOf(isA<Exception>(), isNot(isA<FormatException>()))),
      );
    });

    test('lone minus throws a deliberate Exception, not a FormatException', () {
      expect(
        () => parseFixed('-', 2),
        throwsA(allOf(isA<Exception>(), isNot(isA<FormatException>()))),
      );
    });

    test('non-numeric input throws a deliberate Exception', () {
      expect(
        () => parseFixed('abc', 2),
        throwsA(allOf(isA<Exception>(), isNot(isA<FormatException>()))),
      );
      expect(
        () => parseFixed('1x2', 2),
        throwsA(allOf(isA<Exception>(), isNot(isA<FormatException>()))),
      );
    });

    test(
      'leading-dot input stays rejected (existing spec), but with a '
      'deliberate Exception instead of an accidental FormatException',
      () {
        expect(
          () => parseFixed('.5', 1),
          throwsA(allOf(isA<Exception>(), isNot(isA<FormatException>()))),
        );
        expect(
          () => parseFixed('-.5', 2),
          throwsA(allOf(isA<Exception>(), isNot(isA<FormatException>()))),
        );
      },
    );

    test('trailing-dot decimal parses as x.0', () {
      expect(parseFixed('2.', 2), BigInt.from(200));
    });

    test('existing behaviour is preserved', () {
      expect(parseFixed('1.5', 2), BigInt.from(150));
      expect(parseFixed('-2', 2), BigInt.from(-200));
      expect(parseFixed('0', 2), BigInt.zero);
      expect(parseFixed('1', 0), BigInt.one);
      expect(() => parseFixed('.', 2), throwsException);
      expect(() => parseFixed('1.2.3', 2), throwsException);
      expect(
        () => parseFixed('1.234', 2),
        throwsException, // fractional component exceeds decimals
      );
      expect(
        () => parseFixed('1.5', 0),
        throwsException, // any fraction exceeds zero decimals
      );
    });
  });
}
