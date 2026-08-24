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

    group('defaultForCountryCode', () {
      test('CHF for Switzerland and Liechtenstein', () {
        expect(Currency.defaultForCountryCode('CH'), Currency.chf);
        expect(Currency.defaultForCountryCode('LI'), Currency.chf);
        expect(Currency.defaultForCountryCode('ch'), Currency.chf);
        expect(Currency.defaultForCountryCode('li'), Currency.chf);
      });

      test('EUR for every other country and when the code is missing', () {
        expect(Currency.defaultForCountryCode('DE'), Currency.eur);
        expect(Currency.defaultForCountryCode('AT'), Currency.eur);
        expect(Currency.defaultForCountryCode('US'), Currency.eur);
        expect(Currency.defaultForCountryCode(''), Currency.eur);
        expect(Currency.defaultForCountryCode(null), Currency.eur);
      });
    });
  });
}
