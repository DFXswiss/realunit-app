// We deliberately use non-const constructors throughout this file so the
// generative constructor lines get counted as executed in the coverage
// report. Const-only construction is a compile-time optimisation and is
// not visible to the line-coverage instrumentation.
// ignore_for_file: prefer_const_constructors
import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/screens/buy/cubits/buy_confirm/buy_confirm_cubit.dart';

/// Equatable-`props` surface tests for `BuyConfirmState`.
void main() {
  group('BuyConfirmInitial', () {
    test('two instances are equal and props are empty', () {
      final a = BuyConfirmInitial();
      final b = BuyConfirmInitial();
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a.props, isEmpty);
    });
  });

  group('BuyConfirmLoading', () {
    test('two instances are equal and props are empty', () {
      final a = BuyConfirmLoading();
      final b = BuyConfirmLoading();
      expect(a, equals(b));
      expect(a.props, isEmpty);
    });
  });

  group('BuyConfirmSuccess', () {
    test('same fields are equal and props match', () {
      final a = BuyConfirmSuccess(
        reference: 'ref-1',
        remittanceInfo: 'ref-1',
        paymentRequest: 'qr',
      );
      final b = BuyConfirmSuccess(
        reference: 'ref-1',
        remittanceInfo: 'ref-1',
        paymentRequest: 'qr',
      );
      expect(a, equals(b));
      expect(a.props, ['ref-1', 'ref-1', 'qr']);
    });

    test('different reference is unequal', () {
      final a = BuyConfirmSuccess(reference: 'ref-1');
      final b = BuyConfirmSuccess(reference: 'ref-2');
      expect(a, isNot(equals(b)));
    });

    test('different remittanceInfo is unequal', () {
      final a = BuyConfirmSuccess(reference: 'ref', remittanceInfo: 'ref-1');
      final b = BuyConfirmSuccess(reference: 'ref', remittanceInfo: 'ref-2');
      expect(a, isNot(equals(b)));
    });

    test('different paymentRequest is unequal', () {
      final a = BuyConfirmSuccess(reference: 'ref-1', paymentRequest: 'a');
      final b = BuyConfirmSuccess(reference: 'ref-1', paymentRequest: 'b');
      expect(a, isNot(equals(b)));
    });

    test('backward compatible: only reference set leaves the rest null', () {
      final a = BuyConfirmSuccess(reference: 'RU-REF-1');
      expect(a.reference, 'RU-REF-1');
      expect(a.remittanceInfo, isNull);
      expect(a.paymentRequest, isNull);
      expect(a.props, ['RU-REF-1', null, null]);
    });
  });

  group('BuyConfirmFailure', () {
    test('same message is equal and props match', () {
      final a = BuyConfirmFailure('The purchase could not be confirmed. Please try again later.');
      final b = BuyConfirmFailure('The purchase could not be confirmed. Please try again later.');
      expect(a, equals(b));
      expect(a.props, ['The purchase could not be confirmed. Please try again later.']);
    });

    test('different message is unequal', () {
      final a = BuyConfirmFailure('The purchase could not be confirmed. Please try again later.');
      final b = BuyConfirmFailure('User must have a primary email');
      expect(a, isNot(equals(b)));
    });
  });

  group('BuyConfirmState (cross-subclass identity)', () {
    test('Initial vs Loading are unequal', () {
      expect(BuyConfirmInitial(), isNot(equals(BuyConfirmLoading())));
    });

    test('Success vs Failure are unequal', () {
      final s = BuyConfirmSuccess(reference: 'ref');
      final f = BuyConfirmFailure('oops');
      expect(s, isNot(equals(f)));
    });
  });
}
