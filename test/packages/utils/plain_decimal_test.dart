import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/packages/utils/plain_decimal.dart';

void main() {
  group('comparePlainDecimalStrings', () {
    test('orders plain decimals exactly (no double conversion)', () {
      expect(comparePlainDecimalStrings('1', '2'), lessThan(0));
      expect(comparePlainDecimalStrings('2', '1'), greaterThan(0));
      expect(comparePlainDecimalStrings('1.0', '1.00'), 0);
      expect(comparePlainDecimalStrings('1.50', '1.5'), 0);
      expect(comparePlainDecimalStrings('10.10', '10.1'), 0);
      // Boundary that binary doubles can get wrong at enough fractional digits.
      expect(comparePlainDecimalStrings('0.1', '0.10'), 0);
      expect(comparePlainDecimalStrings('1000.01', '1000.010'), 0);
      expect(comparePlainDecimalStrings('42.70000000000001', '42.7'), greaterThan(0));
      expect(comparePlainDecimalStrings('960', '1000'), lessThan(0));
      expect(comparePlainDecimalStrings('1000', '960'), greaterThan(0));
    });

    test('handles leading zeros and optional sign', () {
      expect(comparePlainDecimalStrings('01.5', '1.5'), 0);
      expect(comparePlainDecimalStrings('+1.5', '1.5'), 0);
      expect(comparePlainDecimalStrings('-1', '1'), lessThan(0));
      expect(comparePlainDecimalStrings('-2', '-1'), lessThan(0));
      expect(comparePlainDecimalStrings('-0', '0'), 0);
      expect(comparePlainDecimalStrings('.5', '0.5'), 0);
      expect(comparePlainDecimalStrings('5.', '5'), 0);
    });

    test('rejects scientific notation', () {
      expect(
        () => comparePlainDecimalStrings('1e3', '1000'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => comparePlainDecimalStrings('1.2E-3', '0.0012'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects malformed input fail-closed', () {
      expect(
        () => comparePlainDecimalStrings('', '1'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => comparePlainDecimalStrings('1.2.3', '1'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => comparePlainDecimalStrings('abc', '1'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => comparePlainDecimalStrings('-', '1'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => comparePlainDecimalStrings('.', '1'),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => comparePlainDecimalStrings('1.2a', '1'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
