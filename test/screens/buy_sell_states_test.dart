import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/packages/service/dfx/models/bank_account/bank_account.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/buy/buy_payment_info.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/payment_info_error.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/sell_payment_info.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/dto/eip7702/eip7702_data_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/dto/real_unit_sell_payment_info_dto.dart';
import 'package:realunit_wallet/screens/buy/cubits/buy_payment_info/buy_payment_info_cubit.dart';
import 'package:realunit_wallet/screens/sell/cubits/sell_bank_accounts/sell_bank_accounts_cubit.dart';
import 'package:realunit_wallet/screens/sell/cubits/sell_confirm/sell_confirm_cubit.dart';
import 'package:realunit_wallet/screens/sell/cubits/sell_payment_info/sell_payment_info_cubit.dart';
import 'package:realunit_wallet/styles/currency.dart';

const _bankA = BankAccount(id: 1, iban: 'CH1', name: 'A');
const _bankB = BankAccount(id: 2, iban: 'CH2', name: 'B');

const _buyInfo = BuyPaymentInfo(
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

Map<String, dynamic> _eip7702Json() => {
      'relayerAddress': '0xr',
      'delegationManagerAddress': '0xm',
      'delegatorAddress': '0xd',
      'userNonce': 0,
      'domain': {
        'name': 'X',
        'version': '1',
        'chainId': 1,
        'verifyingContract': '0xv',
      },
      'types': {'Delegation': <Map<String, dynamic>>[], 'Caveat': <Map<String, dynamic>>[]},
      'message': {
        'delegate': '0xd',
        'delegator': '0xd',
        'authority': '0xa',
        'caveats': <Map<String, dynamic>>[],
        'salt': 0,
      },
      'tokenAddress': '0xt',
      'amountWei': '1',
      'depositAddress': '0xd',
    };

SellPaymentInfo _sellInfo() => SellPaymentInfo(
      id: 1,
      eip7702: Eip7702Data.fromJson(_eip7702Json()),
      amount: 1,
      exchangeRate: 1,
      rate: 1,
      beneficiary: const BeneficiaryDto(iban: 'CH'),
      estimatedAmount: 1,
      currency: Currency.chf,
      depositAddress: '0xd',
      tokenAddress: '0xt',
      chainId: 1,
      ethBalance: 0,
      requiredGasEth: 0,
    );

void main() {
  group('$BuyPaymentInfoState equality', () {
    test('Initial vs Loading are different but each equals itself', () {
      expect(const BuyPaymentInfoInitial(), const BuyPaymentInfoInitial());
      expect(const BuyPaymentInfoLoading(), const BuyPaymentInfoLoading());
      expect(const BuyPaymentInfoInitial(), isNot(const BuyPaymentInfoLoading()));
    });

    test('Success carries buyPaymentInfo; identical info → equal', () {
      const a = BuyPaymentInfoSuccess(_buyInfo);
      const b = BuyPaymentInfoSuccess(_buyInfo);
      expect(a, b);
    });

    test('Failure props are [error, requiredLevel]', () {
      const a = BuyPaymentInfoFailure(PaymentInfoError.kycRequired, requiredLevel: 30);
      const b = BuyPaymentInfoFailure(PaymentInfoError.kycRequired, requiredLevel: 30);
      const c = BuyPaymentInfoFailure(PaymentInfoError.kycRequired, requiredLevel: 50);
      expect(a, b);
      expect(a, isNot(c));
    });

    test('MinAmountNotMetFailure adds the minAmount to props', () {
      const a = BuyPaymentInfoMinAmountNotMetFailure(
        PaymentInfoError.minAmountNotMet,
        minAmount: 100,
      );
      const b = BuyPaymentInfoMinAmountNotMetFailure(
        PaymentInfoError.minAmountNotMet,
        minAmount: 100,
      );
      const c = BuyPaymentInfoMinAmountNotMetFailure(
        PaymentInfoError.minAmountNotMet,
        minAmount: 200,
      );
      expect(a, b);
      expect(a, isNot(c));
    });

    test('MaxAmountExceededFailure adds the maxAmount to props', () {
      const a = BuyPaymentInfoMaxAmountExceededFailure(
        PaymentInfoError.maxAmountExceeded,
        maxAmount: 90000,
      );
      const b = BuyPaymentInfoMaxAmountExceededFailure(
        PaymentInfoError.maxAmountExceeded,
        maxAmount: 90000,
      );
      const c = BuyPaymentInfoMaxAmountExceededFailure(
        PaymentInfoError.maxAmountExceeded,
        maxAmount: 80000,
      );
      expect(a, b);
      expect(a, isNot(c));
    });
  });

  group('$SellPaymentInfoState equality', () {
    test('Success props include isBitbox flag', () {
      final info = _sellInfo();
      expect(
        SellPaymentInfoSuccess(info, isBitbox: false),
        SellPaymentInfoSuccess(info, isBitbox: false),
      );
      expect(
        SellPaymentInfoSuccess(info, isBitbox: false),
        isNot(SellPaymentInfoSuccess(info, isBitbox: true)),
      );
    });

    test('Failure default message is empty', () {
      const a = SellPaymentInfoFailure(PaymentInfoError.kycRequired);
      expect(a.message, '');
    });

    test('MinAmountNotMet carries (minAmount, currency)', () {
      const a = SellPaymentInfoMinAmountNotMet(minAmount: 10, currency: Currency.chf);
      const b = SellPaymentInfoMinAmountNotMet(minAmount: 10, currency: Currency.chf);
      const c = SellPaymentInfoMinAmountNotMet(minAmount: 10, currency: Currency.eur);
      expect(a, b);
      expect(a, isNot(c));
    });
  });

  group('$SellBankAccountsState equality', () {
    test('Initial: empty accounts list, equal to a fresh Initial', () {
      const a = SellBankAccountsInitial();
      const b = SellBankAccountsInitial();
      expect(a, b);
      expect(a.accounts, isEmpty);
    });

    test('Success(<accounts>) equality reflects the accounts list', () {
      const a = SellBankAccountsSuccess([_bankA]);
      const b = SellBankAccountsSuccess([_bankA]);
      const c = SellBankAccountsSuccess([_bankA, _bankB]);
      expect(a, b);
      expect(a, isNot(c));
    });

    test('AddFailure props include (accounts, message)', () {
      const a = SellBankAccountsAddFailure([_bankA], 'duplicate');
      const b = SellBankAccountsAddFailure([_bankA], 'duplicate');
      const c = SellBankAccountsAddFailure([_bankA], 'something else');
      expect(a, b);
      expect(a, isNot(c));
    });
  });

  group('$SellConfirmState equality', () {
    test('Failure carries the error string and is equatable on it', () {
      expect(SellConfirmFailure('boom'), SellConfirmFailure('boom'));
      expect(SellConfirmFailure('boom'), isNot(SellConfirmFailure('other')));
    });
  });
}
