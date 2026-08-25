// We deliberately use non-const constructors throughout this file so the
// generative constructor lines get counted as executed in the coverage
// report. Const-only construction is a compile-time optimisation and is
// not visible to the line-coverage instrumentation.
// ignore_for_file: prefer_const_constructors
import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/buy/buy_payment_info.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/payment_info_error.dart';
import 'package:realunit_wallet/screens/buy/cubits/buy_payment_info/buy_payment_info_cubit.dart';
import 'package:realunit_wallet/styles/currency.dart';

/// Equatable-`props` surface tests for `BuyPaymentInfoState`.
///
/// Pairs with the (const-only) cases in `buy_sell_states_test.dart` to run
/// every subclass through a runtime constructor + `.props` lookup, so the
/// value-type file lands at 100%.
const _info = BuyPaymentInfo(
  amount: 300,
  id: 1,
  iban: 'CH',
  bic: 'BIC',
  name: 'DFX',
  street: 'Bahnhof',
  number: '1',
  zip: '8000',
  city: 'ZH',
  country: 'CH',
  currency: Currency.chf,
);

void main() {
  group('BuyPaymentInfoInitial', () {
    test('two instances are equal and props are empty', () {
      final a = BuyPaymentInfoInitial();
      final b = BuyPaymentInfoInitial();
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a.props, isEmpty);
    });
  });

  group('BuyPaymentInfoLoading', () {
    test('two instances are equal and props are empty', () {
      final a = BuyPaymentInfoLoading();
      final b = BuyPaymentInfoLoading();
      expect(a, equals(b));
      expect(a.props, isEmpty);
    });
  });

  group('BuyPaymentInfoSuccess', () {
    test('same buyPaymentInfo is equal and props match', () {
      final a = BuyPaymentInfoSuccess(_info);
      final b = BuyPaymentInfoSuccess(_info);
      expect(a, equals(b));
      expect(a.props, [_info]);
    });
  });

  group('BuyPaymentInfoFailure', () {
    test('same error+level is equal and props match', () {
      final a = BuyPaymentInfoFailure(PaymentInfoError.kycRequired, requiredLevel: 30);
      final b = BuyPaymentInfoFailure(PaymentInfoError.kycRequired, requiredLevel: 30);
      expect(a, equals(b));
      expect(a.props, [PaymentInfoError.kycRequired, 30, null, '']);
    });

    test('null requiredLevel is allowed and equal across instances', () {
      final a = BuyPaymentInfoFailure(PaymentInfoError.kycRequired);
      final b = BuyPaymentInfoFailure(PaymentInfoError.kycRequired);
      expect(a, equals(b));
      expect(a.requiredLevel, isNull);
    });

    test('different errors are unequal', () {
      final a = BuyPaymentInfoFailure(PaymentInfoError.kycRequired);
      final b = BuyPaymentInfoFailure(PaymentInfoError.minAmountNotMet);
      expect(a, isNot(equals(b)));
    });

    test('same error+level+context is equal and props match', () {
      final a = BuyPaymentInfoFailure(
        PaymentInfoError.kycRequired,
        requiredLevel: 30,
        context: 'RealunitBuy',
      );
      final b = BuyPaymentInfoFailure(
        PaymentInfoError.kycRequired,
        requiredLevel: 30,
        context: 'RealunitBuy',
      );
      expect(a, equals(b));
      expect(a.props, [PaymentInfoError.kycRequired, 30, 'RealunitBuy', '']);
    });

    test('different context is unequal', () {
      final a = BuyPaymentInfoFailure(
        PaymentInfoError.kycRequired,
        context: 'RealunitBuy',
      );
      final b = BuyPaymentInfoFailure(
        PaymentInfoError.kycRequired,
        context: 'RealunitSell',
      );
      expect(a, isNot(equals(b)));
    });
  });

  group('BuyPaymentInfoMinAmountNotMetFailure', () {
    test('same error+minAmount is equal and props match', () {
      final a = BuyPaymentInfoMinAmountNotMetFailure(
        PaymentInfoError.minAmountNotMet,
        minAmount: 100,
      );
      final b = BuyPaymentInfoMinAmountNotMetFailure(
        PaymentInfoError.minAmountNotMet,
        minAmount: 100,
      );
      expect(a, equals(b));
      expect(a.props, [PaymentInfoError.minAmountNotMet, 100]);
    });

    test('different minAmount is unequal', () {
      final a = BuyPaymentInfoMinAmountNotMetFailure(
        PaymentInfoError.minAmountNotMet,
        minAmount: 100,
      );
      final b = BuyPaymentInfoMinAmountNotMetFailure(
        PaymentInfoError.minAmountNotMet,
        minAmount: 200,
      );
      expect(a, isNot(equals(b)));
    });
  });

  group('BuyPaymentInfoMaxAmountExceededFailure', () {
    test('same error+maxAmount is equal and props match', () {
      final a = BuyPaymentInfoMaxAmountExceededFailure(
        PaymentInfoError.maxAmountExceeded,
        maxAmount: 90000,
      );
      final b = BuyPaymentInfoMaxAmountExceededFailure(
        PaymentInfoError.maxAmountExceeded,
        maxAmount: 90000,
      );
      expect(a, equals(b));
      expect(a.props, [PaymentInfoError.maxAmountExceeded, 90000]);
    });

    test('different maxAmount is unequal', () {
      final a = BuyPaymentInfoMaxAmountExceededFailure(
        PaymentInfoError.maxAmountExceeded,
        maxAmount: 90000,
      );
      final b = BuyPaymentInfoMaxAmountExceededFailure(
        PaymentInfoError.maxAmountExceeded,
        maxAmount: 80000,
      );
      expect(a, isNot(equals(b)));
    });
  });

  group('BuyPaymentInfoState (cross-subclass identity)', () {
    test('Initial vs Loading are unequal', () {
      expect(BuyPaymentInfoInitial(), isNot(equals(BuyPaymentInfoLoading())));
    });

    test('Failure vs MinAmountNotMetFailure with matching error are unequal', () {
      final f = BuyPaymentInfoFailure(PaymentInfoError.minAmountNotMet);
      final m = BuyPaymentInfoMinAmountNotMetFailure(
        PaymentInfoError.minAmountNotMet,
        minAmount: 50,
      );
      // MinAmountNotMetFailure extends Failure, but Equatable's runtimeType
      // check separates them.
      expect(f, isNot(equals(m)));
    });

    test('Failure vs MaxAmountExceededFailure with matching error are unequal', () {
      final f = BuyPaymentInfoFailure(PaymentInfoError.maxAmountExceeded);
      final m = BuyPaymentInfoMaxAmountExceededFailure(
        PaymentInfoError.maxAmountExceeded,
        maxAmount: 90000,
      );
      expect(f, isNot(equals(m)));
    });
  });
}
