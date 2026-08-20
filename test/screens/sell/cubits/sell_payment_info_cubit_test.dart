import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/bitbox_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/payment/buy_exceptions.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/payment_info_error.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/dto/eip7702/eip7702_data_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/dto/real_unit_sell_payment_info_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/sell_payment_info.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_sell_payment_info_service.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';
import 'package:realunit_wallet/packages/wallet/wallet_account.dart';
import 'package:realunit_wallet/screens/sell/cubits/sell_payment_info/sell_payment_info_cubit.dart';
import 'package:realunit_wallet/styles/currency.dart';

class _MockSellPaymentInfoService extends Mock implements RealUnitSellPaymentInfoService {}

class _MockAppStore extends Mock implements AppStore {}

const _testMnemonic = 'test test test test test test test test test test test junk';

SellPaymentInfo _info({
  bool isValid = true,
  double minVolume = 10,
  String? error,
  Currency currency = Currency.chf,
}) => SellPaymentInfo(
  id: 1,
  eip7702: const Eip7702Data(
    relayerAddress: '0x1',
    delegationManagerAddress: '0x2',
    delegatorAddress: '0x3',
    userNonce: 0,
    domain: Eip7702Domain(
      name: 'RealUnit',
      version: '1',
      chainId: 1,
      verifyingContract: '0x4',
    ),
    types: Eip7702Types(delegation: [], caveat: []),
    message: Eip7702Message(
      delegate: '0x5',
      delegator: '0x6',
      authority: '0x7',
      caveats: [],
      salt: 0,
    ),
    tokenAddress: '0x8',
    amountWei: '0',
    depositAddress: '0x9',
  ),
  amount: 100,
  exchangeRate: 1.0,
  rate: 1.0,
  beneficiary: const BeneficiaryDto(iban: 'CH56'),
  estimatedAmount: 100,
  currency: currency,
  depositAddress: '0xA',
  tokenAddress: '0xB',
  chainId: 1,
  ethBalance: 0.01,
  requiredGasEth: 0.001,
  isValid: isValid,
  minVolume: minVolume,
  error: error,
);

void main() {
  late _MockSellPaymentInfoService service;
  late _MockAppStore appStore;

  setUpAll(() {
    registerFallbackValue(Currency.chf);
  });

  setUp(() {
    service = _MockSellPaymentInfoService();
    appStore = _MockAppStore();
    when(() => appStore.wallet).thenReturn(SoftwareWallet(1, 'Main', _testMnemonic));
  });

  SellPaymentInfoCubit build() => SellPaymentInfoCubit(service, appStore);

  group('$SellPaymentInfoCubit', () {
    test('initial state is SellPaymentInfoInitial', () {
      expect(build().state, isA<SellPaymentInfoInitial>());
    });

    test('happy path emits Success with isBitbox=false for a software wallet', () async {
      when(
        () => service.getPaymentInfo(any(), any(), currency: any(named: 'currency')),
      ).thenAnswer((_) async => _info());

      final cubit = build();
      await cubit.getPaymentInfo(amount: '100', iban: 'CH56');

      final success = cubit.state as SellPaymentInfoSuccess;
      expect(success.isBitbox, isFalse);
      verify(() => service.getPaymentInfo(100, 'CH56', currency: Currency.chf)).called(1);
    });

    test('a comma-decimal amount is charged as the rounded integer (300,75 → 301)', () async {
      when(
        () => service.getPaymentInfo(any(), any(), currency: any(named: 'currency')),
      ).thenAnswer((_) async => _info());

      await build().getPaymentInfo(amount: '300,75', iban: 'CH56');

      verify(() => service.getPaymentInfo(301, 'CH56', currency: Currency.chf)).called(1);
    });

    test('Success.isBitbox=true when the current wallet is a BitboxWallet', () async {
      when(
        () => service.getPaymentInfo(any(), any(), currency: any(named: 'currency')),
      ).thenAnswer((_) async => _info());
      when(() => appStore.wallet).thenReturn(_BitboxStubWallet());

      final cubit = build();
      await cubit.getPaymentInfo(amount: '100', iban: 'CH56');

      expect((cubit.state as SellPaymentInfoSuccess).isBitbox, isTrue);
    });

    test('API isValid=false with error=AmountTooLow → MinAmountNotMet with API limit', () async {
      when(
        () => service.getPaymentInfo(any(), any(), currency: any(named: 'currency')),
      ).thenAnswer((_) async => _info(isValid: false, error: 'AmountTooLow', minVolume: 10));

      final cubit = build();
      await cubit.getPaymentInfo(amount: '5', iban: 'CH56');

      final s = cubit.state as SellPaymentInfoMinAmountNotMet;
      expect(s.minAmount, 10);
      expect(s.currency, Currency.chf);
    });

    test('EUR minimum is reported by the API as-is, not scaled in the app', () async {
      when(() => service.getPaymentInfo(any(), any(), currency: any(named: 'currency'))).thenAnswer(
        (_) async => _info(
          isValid: false,
          error: 'AmountTooLow',
          minVolume: 9,
          currency: Currency.eur,
        ),
      );

      final cubit = build();
      await cubit.getPaymentInfo(amount: '5', iban: 'CH56', currency: Currency.eur);

      final s = cubit.state as SellPaymentInfoMinAmountNotMet;
      expect(s.minAmount, 9);
      expect(s.currency, Currency.eur);
    });

    test('API isValid=false with unrelated error → Failure(unknown) carrying the error', () async {
      when(
        () => service.getPaymentInfo(any(), any(), currency: any(named: 'currency')),
      ).thenAnswer((_) async => _info(isValid: false, error: 'KycRequired'));

      final cubit = build();
      await cubit.getPaymentInfo(amount: '100', iban: 'CH56');

      final f = cubit.state as SellPaymentInfoFailure;
      expect(f.error, PaymentInfoError.unknown);
      expect(f.message, 'KycRequired');
    });

    test('KycLevelRequiredException → Failure(kycRequired, requiredLevel)', () async {
      when(() => service.getPaymentInfo(any(), any(), currency: any(named: 'currency'))).thenAnswer(
        (_) async => throw const KycLevelRequiredException(
          statusCode: 403,
          code: 'KYC_REQUIRED',
          message: 'KYC required',
          requiredLevel: 30,
          currentLevel: 10,
        ),
      );

      final cubit = build();
      await cubit.getPaymentInfo(amount: '100', iban: 'CH56');

      final f = cubit.state as SellPaymentInfoFailure;
      expect(f.error, PaymentInfoError.kycRequired);
      expect(f.requiredLevel, 30);
    });

    test('KycLevelRequiredException with context → Failure carries context', () async {
      when(() => service.getPaymentInfo(any(), any(), currency: any(named: 'currency'))).thenAnswer(
        (_) async => throw const KycLevelRequiredException(
          statusCode: 403,
          code: 'KYC_REQUIRED',
          message: 'KYC required',
          requiredLevel: 50,
          currentLevel: 30,
          context: 'RealunitSell',
        ),
      );

      final cubit = build();
      await cubit.getPaymentInfo(amount: '100', iban: 'CH56');

      final f = cubit.state as SellPaymentInfoFailure;
      expect(f.error, PaymentInfoError.kycRequired);
      expect(f.requiredLevel, 50);
      expect(f.context, 'RealunitSell');
    });

    test(
      'BitboxNotConnectedException → Failure(bitboxDisconnected) carrying the message',
      () async {
        // BitBox quote flow lifts a typed disconnect into its own failure state
        // so the UI can prompt the user to re-plug / re-pair instead of
        // surfacing it as a generic unknown error.
        when(
          () => service.getPaymentInfo(any(), any(), currency: any(named: 'currency')),
        ).thenAnswer((_) async => throw const BitboxNotConnectedException());

        final cubit = build();
        await cubit.getPaymentInfo(amount: '100', iban: 'CH56');

        final f = cubit.state as SellPaymentInfoFailure;
        expect(f.error, PaymentInfoError.bitboxDisconnected);
        expect(f.message, contains('BitBox is not connected'));
      },
    );

    test('BitboxNotConnectedException does not emit after close', () async {
      // Async-tail guard: a late BitBox disconnect must not throw a
      // post-close emit. Mirrors the generic-exception / KycRequired guards
      // already covered above.
      final completer = Completer<SellPaymentInfo>();
      when(
        () => service.getPaymentInfo(any(), any(), currency: any(named: 'currency')),
      ).thenAnswer((_) => completer.future);

      final cubit = build();
      unawaited(cubit.getPaymentInfo(amount: '100', iban: 'CH56'));
      await cubit.close();
      completer.completeError(const BitboxNotConnectedException());
    });

    test('RegistrationRequiredException → Failure(registrationRequired)', () async {
      when(() => service.getPaymentInfo(any(), any(), currency: any(named: 'currency'))).thenAnswer(
        (_) async => throw const RegistrationRequiredException(
          statusCode: 403,
          code: 'REGISTRATION_REQUIRED',
          message: 'Sign first',
        ),
      );

      final cubit = build();
      await cubit.getPaymentInfo(amount: '100', iban: 'CH56');

      expect(
        (cubit.state as SellPaymentInfoFailure).error,
        PaymentInfoError.registrationRequired,
      );
    });

    test('RegistrationRequiredException with context → Failure carries context', () async {
      when(() => service.getPaymentInfo(any(), any(), currency: any(named: 'currency'))).thenAnswer(
        (_) async => throw const RegistrationRequiredException(
          statusCode: 403,
          code: 'REGISTRATION_REQUIRED',
          message: 'Sign first',
          context: 'RealunitSell',
        ),
      );

      final cubit = build();
      await cubit.getPaymentInfo(amount: '100', iban: 'CH56');

      final f = cubit.state as SellPaymentInfoFailure;
      expect(f.error, PaymentInfoError.registrationRequired);
      expect(f.context, 'RealunitSell');
    });

    test('generic exception → Failure(unknown) carrying the message', () async {
      when(
        () => service.getPaymentInfo(any(), any(), currency: any(named: 'currency')),
      ).thenAnswer((_) async => throw Exception('network'));

      final cubit = build();
      await cubit.getPaymentInfo(amount: '100', iban: 'CH56');

      final f = cubit.state as SellPaymentInfoFailure;
      expect(f.error, PaymentInfoError.unknown);
      expect(f.message, contains('network'));
    });

    test('ApiException 503 → Failure(priceSourceUnavailable)', () async {
      when(() => service.getPaymentInfo(any(), any(), currency: any(named: 'currency'))).thenAnswer(
        (_) async => throw const ApiException(
          statusCode: 503,
          code: 'PRICE_SOURCE_UNAVAILABLE',
          message: 'RealUnit price source (Aktionariat) is currently unavailable',
        ),
      );

      final cubit = build();
      await cubit.getPaymentInfo(amount: '100', iban: 'CH56');

      expect((cubit.state as SellPaymentInfoFailure).error, PaymentInfoError.priceSourceUnavailable);
      expect(
        (cubit.state as SellPaymentInfoFailure).message,
        'RealUnit price source (Aktionariat) is currently unavailable',
      );
    });

    test('other ApiException (e.g. 400) → Failure(unknown)', () async {
      when(() => service.getPaymentInfo(any(), any(), currency: any(named: 'currency'))).thenAnswer(
        (_) async => throw const ApiException(statusCode: 400, code: 'BAD_REQUEST', message: 'bad'),
      );

      final cubit = build();
      await cubit.getPaymentInfo(amount: '100', iban: 'CH56');

      expect((cubit.state as SellPaymentInfoFailure).error, PaymentInfoError.unknown);
      expect((cubit.state as SellPaymentInfoFailure).message, 'bad');
    });

    test(
      'negative amount is sent to service (UI prevents this via digitsOnly formatter)',
      () async {
        when(
          () => service.getPaymentInfo(any(), any(), currency: any(named: 'currency')),
        ).thenAnswer((_) async => _info());

        final cubit = build();
        await cubit.getPaymentInfo(amount: '-100', iban: 'CH56');

        verify(() => service.getPaymentInfo(-100, 'CH56', currency: Currency.chf)).called(1);
      },
    );

    test(
      'structurally invalid amount (multiple separators) fails without a service call',
      () async {
        final cubit = build();
        await cubit.getPaymentInfo(amount: '1.300,75', iban: 'CH56');

        expect(cubit.state, isA<SellPaymentInfoFailure>());
        verifyNever(() => service.getPaymentInfo(any(), any(), currency: any(named: 'currency')));
      },
    );

    test('does not emit after close', () async {
      final completer = Completer<SellPaymentInfo>();
      when(
        () => service.getPaymentInfo(any(), any(), currency: any(named: 'currency')),
      ).thenAnswer((_) => completer.future);

      final cubit = build();
      unawaited(cubit.getPaymentInfo(amount: '100', iban: 'CH56'));
      await cubit.close();
      completer.complete(_info());
    });
  });
}

class _BitboxStubWallet extends AWallet {
  _BitboxStubWallet() : super(1, 'BB');
  @override
  WalletType get walletType => WalletType.bitbox;
  @override
  AWalletAccount get primaryAccount => throw UnimplementedError();
  @override
  AWalletAccount get currentAccount => throw UnimplementedError();
}
