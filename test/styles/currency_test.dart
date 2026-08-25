import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/styles/currency.dart';

void main() {
  group('$Currency', () {
    test('eur and chf have the wire codes "EUR" and "CHF"', () {
      expect(Currency.eur.code, 'EUR');
      expect(Currency.chf.code, 'CHF');
    });

    test('values has exactly the two entries', () {
      expect(Currency.values, hasLength(2));
      expect(Currency.values, contains(Currency.eur));
      expect(Currency.values, contains(Currency.chf));
    });

    group('fromCode', () {
      test('resolves "EUR" and "CHF"', () {
        expect(Currency.fromCode('EUR'), Currency.eur);
        expect(Currency.fromCode('CHF'), Currency.chf);
      });

      test('is case-insensitive on the input', () {
        expect(Currency.fromCode('eur'), Currency.eur);
        expect(Currency.fromCode('chf'), Currency.chf);
        expect(Currency.fromCode('Eur'), Currency.eur);
      });

      test('throws StateError on an unknown code', () {
        expect(() => Currency.fromCode('USD'), throwsA(isA<StateError>()));
        expect(() => Currency.fromCode(''), throwsA(isA<StateError>()));
      });
    });

    group('tryFromCode', () {
      test('resolves known codes and returns null otherwise', () {
        expect(Currency.tryFromCode('CHF'), Currency.chf);
        expect(Currency.tryFromCode('eur'), Currency.eur);
        expect(Currency.tryFromCode('USD'), isNull);
        expect(Currency.tryFromCode(''), isNull);
        expect(Currency.tryFromCode(null), isNull);
      });
    });
  });
}
