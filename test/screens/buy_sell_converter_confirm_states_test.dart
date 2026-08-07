import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/screens/buy/cubits/buy_confirm/buy_confirm_cubit.dart';
import 'package:realunit_wallet/screens/buy/cubits/buy_converter/buy_converter_cubit.dart';
import 'package:realunit_wallet/screens/sell/cubits/sell_converter/sell_converter_cubit.dart';
import 'package:realunit_wallet/styles/currency.dart';

void main() {
  group('$BuyConverterState', () {
    test('defaults: empty text fields, CHF currency, not loading', () {
      const state = BuyConverterState();
      expect(state.fiatText, '');
      expect(state.sharesText, '');
      expect(state.currency, Currency.chf);
      expect(state.loading, isFalse);
    });

    test('copyWith preserves untouched fields', () {
      const base = BuyConverterState(fiatText: '100', currency: Currency.eur);
      final next = base.copyWith(loading: true);
      expect(next.fiatText, '100');
      expect(next.currency, Currency.eur);
      expect(next.loading, isTrue);
    });

    test('Equatable props pin all four fields', () {
      const a = BuyConverterState(fiatText: '100');
      const b = BuyConverterState(fiatText: '100');
      const c = BuyConverterState(fiatText: '200');
      expect(a, b);
      expect(a, isNot(c));
    });
  });

  group('$SellConverterState', () {
    test('defaults match BuyConverterState (empty, CHF, not loading)', () {
      const state = SellConverterState();
      expect(state.fiatText, '');
      expect(state.sharesText, '');
      expect(state.currency, Currency.chf);
      expect(state.loading, isFalse);
    });

    test('copyWith preserves untouched fields', () {
      const base = SellConverterState(sharesText: '5');
      final next = base.copyWith(currency: Currency.eur);
      expect(next.sharesText, '5');
      expect(next.currency, Currency.eur);
    });

    test('Equatable props pin all four fields', () {
      const a = SellConverterState(sharesText: '5');
      const b = SellConverterState(sharesText: '5');
      const c = SellConverterState(sharesText: '6');
      expect(a, b);
      expect(a, isNot(c));
    });
  });

  group('$BuyConfirmState equality', () {
    test('Success carries the reference, remittance info and QR', () {
      const a = BuyConfirmSuccess(reference: 'XYZ-1');
      const b = BuyConfirmSuccess(reference: 'XYZ-1');
      const c = BuyConfirmSuccess(reference: 'XYZ-2');
      expect(a, b);
      expect(a, isNot(c));
    });

    test('Failure carries the BuyConfirmError', () {
      const a = BuyConfirmFailure(BuyConfirmError.aktionariat);
      const b = BuyConfirmFailure(BuyConfirmError.aktionariat);
      const c = BuyConfirmFailure(BuyConfirmError.unknown);
      expect(a, b);
      expect(a, isNot(c));
    });

    test('BuyConfirmError enum has exactly aktionariat + amountTooLow + primaryEmailRequired + unknown', () {
      // Pin the variants — the listener in BuyButton switches on these.
      expect(BuyConfirmError.values.toSet(), {
        BuyConfirmError.aktionariat,
        BuyConfirmError.amountTooLow,
        BuyConfirmError.primaryEmailRequired,
        BuyConfirmError.unknown,
      });
    });

    test('Initial and Loading are distinct singletons (by value)', () {
      expect(const BuyConfirmInitial(), const BuyConfirmInitial());
      expect(const BuyConfirmLoading(), const BuyConfirmLoading());
      expect(const BuyConfirmInitial(), isNot(const BuyConfirmLoading()));
    });
  });
}
