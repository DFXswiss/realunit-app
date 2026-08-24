import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/bitbox_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/payment/buy_exceptions.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/buy/buy_payment_info.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/payment_info_error.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_buy_payment_info_service.dart';
import 'package:realunit_wallet/screens/buy/cubits/buy_payment_info/buy_payment_info_cubit.dart';
import 'package:realunit_wallet/styles/currency.dart';

class _MockBuyPaymentInfoService extends Mock
    implements RealUnitBuyPaymentInfoService {}

BuyPaymentInfo _info({
  bool isValid = true,
  double? minVolume,
  double? maxVolume,
  String? error,
  Currency currency = Currency.chf,
  String iban = 'CH56 0483 5012 3456 78',
}) => BuyPaymentInfo(
  amount: 300,
  id: 1,
  iban: iban,
  bic: 'CRESCHZZ80A',
  name: 'DFX AG',
  street: 'Bahnhofstrasse',
  number: '1',
  zip: '8000',
  city: 'Zurich',
  country: 'CH',
  currency: currency,
  isValid: isValid,
  minVolume: minVolume,
  maxVolume: maxVolume,
  error: error,
);

void main() {
  late _MockBuyPaymentInfoService service;

  setUpAll(() {
    registerFallbackValue(Currency.chf);
  });

  setUp(() {
    service = _MockBuyPaymentInfoService();
  });

  BuyPaymentInfoCubit build() => BuyPaymentInfoCubit(service);

  group('$BuyPaymentInfoCubit', () {
    test('initial state is BuyPaymentInfoInitial', () {
      expect(build().state, isA<BuyPaymentInfoInitial>());
    });

    test('happy path emits Success with the payment info from the API', () async {
      when(() => service.getPaymentInfo(any(), currency: any(named: 'currency')))
          .thenAnswer((_) async => _info());

      final cubit = build();
      await cubit.getPaymentInfo(amount: '300');

      expect(cubit.state, isA<BuyPaymentInfoSuccess>());
      verify(() => service.getPaymentInfo(300, currency: Currency.chf)).called(1);
    });

    test('EUR quote emits Success with the EUR IBAN and currency from the API', () async {
      when(() => service.getPaymentInfo(any(), currency: any(named: 'currency')))
          .thenAnswer(
            (_) async => _info(
              currency: Currency.eur,
              iban: 'CH9708307000560946317',
            ),
          );

      final cubit = build();
      await cubit.getPaymentInfo(amount: '300', currency: Currency.eur);

      expect(cubit.state, isA<BuyPaymentInfoSuccess>());
      final success = cubit.state as BuyPaymentInfoSuccess;
      expect(success.buyPaymentInfo.iban, 'CH9708307000560946317');
      expect(success.buyPaymentInfo.currency, Currency.eur);
      verify(() => service.getPaymentInfo(300, currency: Currency.eur)).called(1);
    });

    test('API isValid=false with error=AmountTooLow → MinAmountNotMetFailure with API limit', () async {
      when(() => service.getPaymentInfo(any(), currency: any(named: 'currency')))
          .thenAnswer((_) async => _info(isValid: false, error: 'AmountTooLow', minVolume: 100));

      final cubit = build();
      await cubit.getPaymentInfo(amount: '50');

      expect(cubit.state, isA<BuyPaymentInfoMinAmountNotMetFailure>());
      final f = cubit.state as BuyPaymentInfoMinAmountNotMetFailure;
      expect(f.error, PaymentInfoError.minAmountNotMet);
      expect(f.minAmount, 100);
      verify(() => service.getPaymentInfo(50, currency: Currency.chf)).called(1);
    });

    test('EUR min is reported by the API as-is, not scaled in the app', () async {
      // For EUR the API returns its own currency-specific minVolume; the
      // app no longer multiplies a hardcoded CHF baseline by an exchange
      // rate locally — the rate lives server-side.
      when(() => service.getPaymentInfo(any(), currency: any(named: 'currency')))
          .thenAnswer((_) async => _info(
            isValid: false,
            error: 'AmountTooLow',
            minVolume: 92,
            currency: Currency.eur,
          ));

      final cubit = build();
      await cubit.getPaymentInfo(amount: '50', currency: Currency.eur);

      final f = cubit.state as BuyPaymentInfoMinAmountNotMetFailure;
      expect(f.minAmount, 92);
      verify(() => service.getPaymentInfo(50, currency: Currency.eur)).called(1);
    });

    test('API isValid=false with error=PrimaryEmailRequired → Failure(primaryEmailRequired)', () async {
      // The API pre-tells on the quote that the account has no primary
      // email; the app gates the confirm before the tap instead of
      // reacting to a post-submit 400.
      when(() => service.getPaymentInfo(any(), currency: any(named: 'currency')))
          .thenAnswer((_) async => _info(isValid: false, error: 'PrimaryEmailRequired'));

      final cubit = build();
      await cubit.getPaymentInfo(amount: '300');

      expect(cubit.state, isA<BuyPaymentInfoFailure>());
      expect((cubit.state as BuyPaymentInfoFailure).error, PaymentInfoError.primaryEmailRequired);
    });

    test('API isValid=false with error=PrimaryEmailNotConfirmed → '
        'Failure(primaryEmailNotConfirmed)', () async {
      // A registered-but-unconfirmed email routes to the confirmation flow
      // (via KYC) instead of a post-submit failure or the email-capture path.
      when(() => service.getPaymentInfo(any(), currency: any(named: 'currency')))
          .thenAnswer(
            (_) async => _info(isValid: false, error: 'PrimaryEmailNotConfirmed'),
          );

      final cubit = build();
      await cubit.getPaymentInfo(amount: '300');

      expect(cubit.state, isA<BuyPaymentInfoFailure>());
      expect(
        (cubit.state as BuyPaymentInfoFailure).error,
        PaymentInfoError.primaryEmailNotConfirmed,
      );
    });

    test('API isValid=false with error=PrimaryEmailNotConfirmed → '
        'Failure carries context', () async {
      when(() => service.getPaymentInfo(any(), currency: any(named: 'currency')))
          .thenAnswer(
            (_) async => _info(isValid: false, error: 'PrimaryEmailNotConfirmed'),
          );

      final cubit = build();
      await cubit.getPaymentInfo(amount: '300');

      expect(cubit.state, isA<BuyPaymentInfoFailure>());
      expect((cubit.state as BuyPaymentInfoFailure).context, 'RealunitBuy');
    });

    test('API isValid=false with error=AmountTooHigh and maxVolume → '
        'MaxAmountExceededFailure with API limit', () async {
      when(() => service.getPaymentInfo(any(), currency: any(named: 'currency')))
          .thenAnswer(
            (_) async => _info(isValid: false, error: 'AmountTooHigh', maxVolume: 90000),
          );

      final cubit = build();
      await cubit.getPaymentInfo(amount: '90001');

      expect(cubit.state, isA<BuyPaymentInfoMaxAmountExceededFailure>());
      final f = cubit.state as BuyPaymentInfoMaxAmountExceededFailure;
      expect(f.error, PaymentInfoError.maxAmountExceeded);
      expect(f.maxAmount, 90000);
      verify(() => service.getPaymentInfo(90001, currency: Currency.chf)).called(1);
    });

    test('API isValid=false with error=LimitExceeded and maxVolume → '
        'MaxAmountExceededFailure with API limit', () async {
      when(() => service.getPaymentInfo(any(), currency: any(named: 'currency')))
          .thenAnswer(
            (_) async => _info(isValid: false, error: 'LimitExceeded', maxVolume: 90000.4),
          );

      final cubit = build();
      await cubit.getPaymentInfo(amount: '100000');

      expect(cubit.state, isA<BuyPaymentInfoMaxAmountExceededFailure>());
      final f = cubit.state as BuyPaymentInfoMaxAmountExceededFailure;
      expect(f.error, PaymentInfoError.maxAmountExceeded);
      expect(f.maxAmount, 90000.4);
      verify(() => service.getPaymentInfo(100000, currency: Currency.chf)).called(1);
    });

    test('AmountTooHigh without maxVolume → generic Failure(unknown)', () async {
      when(() => service.getPaymentInfo(any(), currency: any(named: 'currency')))
          .thenAnswer((_) async => _info(isValid: false, error: 'AmountTooHigh'));

      final cubit = build();
      await cubit.getPaymentInfo(amount: '90001');

      expect(cubit.state, isA<BuyPaymentInfoFailure>());
      expect(cubit.state, isNot(isA<BuyPaymentInfoMaxAmountExceededFailure>()));
      expect((cubit.state as BuyPaymentInfoFailure).error, PaymentInfoError.unknown);
    });

    test('LimitExceeded without maxVolume → generic Failure(unknown)', () async {
      when(() => service.getPaymentInfo(any(), currency: any(named: 'currency')))
          .thenAnswer((_) async => _info(isValid: false, error: 'LimitExceeded'));

      final cubit = build();
      await cubit.getPaymentInfo(amount: '100000');

      expect(cubit.state, isA<BuyPaymentInfoFailure>());
      expect(cubit.state, isNot(isA<BuyPaymentInfoMaxAmountExceededFailure>()));
      expect((cubit.state as BuyPaymentInfoFailure).error, PaymentInfoError.unknown);
    });

    test('API isValid=false with unknown error → generic Failure', () async {
      when(() => service.getPaymentInfo(any(), currency: any(named: 'currency')))
          .thenAnswer((_) async => _info(isValid: false, error: 'CountryNotAllowed'));

      final cubit = build();
      await cubit.getPaymentInfo(amount: '999999999');

      expect(cubit.state, isA<BuyPaymentInfoFailure>());
      expect((cubit.state as BuyPaymentInfoFailure).error, PaymentInfoError.unknown);
    });

    test('empty amount string is treated as 0 → still calls the API', () async {
      when(() => service.getPaymentInfo(any(), currency: any(named: 'currency')))
          .thenAnswer((_) async => _info(isValid: false, error: 'AmountTooLow', minVolume: 100));

      final cubit = build();
      await cubit.getPaymentInfo(amount: '');

      expect(cubit.state, isA<BuyPaymentInfoMinAmountNotMetFailure>());
      verify(() => service.getPaymentInfo(0, currency: Currency.chf)).called(1);
    });

    test('comma decimal separator is normalised to dot', () async {
      when(() => service.getPaymentInfo(any(), currency: any(named: 'currency')))
          .thenAnswer((_) async => _info());

      final cubit = build();
      await cubit.getPaymentInfo(amount: '300,75');

      verify(() => service.getPaymentInfo(300.75, currency: Currency.chf)).called(1);
    });

    test('KycLevelRequiredException → Failure(kycRequired, requiredLevel)', () async {
      when(() => service.getPaymentInfo(any(), currency: any(named: 'currency')))
          .thenAnswer(
        (_) async => throw const KycLevelRequiredException(
          statusCode: 403,
          code: 'KYC_REQUIRED',
          message: 'KYC required',
          requiredLevel: 30,
          currentLevel: 10,
        ),
      );

      final cubit = build();
      await cubit.getPaymentInfo(amount: '300');

      final f = cubit.state as BuyPaymentInfoFailure;
      expect(f.error, PaymentInfoError.kycRequired);
      expect(f.requiredLevel, 30);
    });

    test('KycLevelRequiredException with context → Failure carries context', () async {
      when(() => service.getPaymentInfo(any(), currency: any(named: 'currency')))
          .thenAnswer(
        (_) async => throw const KycLevelRequiredException(
          statusCode: 403,
          code: 'KYC_REQUIRED',
          message: 'KYC required',
          requiredLevel: 30,
          currentLevel: 10,
          context: 'RealunitBuy',
        ),
      );

      final cubit = build();
      await cubit.getPaymentInfo(amount: '300');

      final f = cubit.state as BuyPaymentInfoFailure;
      expect(f.error, PaymentInfoError.kycRequired);
      expect(f.requiredLevel, 30);
      expect(f.context, 'RealunitBuy');
    });

    test('RegistrationRequiredException → Failure(registrationRequired)', () async {
      when(() => service.getPaymentInfo(any(), currency: any(named: 'currency')))
          .thenAnswer(
        (_) async => throw const RegistrationRequiredException(
          statusCode: 403,
          code: 'REGISTRATION_REQUIRED',
          message: 'Sign first',
        ),
      );

      final cubit = build();
      await cubit.getPaymentInfo(amount: '300');

      final f = cubit.state as BuyPaymentInfoFailure;
      expect(f.error, PaymentInfoError.registrationRequired);
    });

    test('RegistrationRequiredException with context → Failure carries context', () async {
      when(() => service.getPaymentInfo(any(), currency: any(named: 'currency')))
          .thenAnswer(
        (_) async => throw const RegistrationRequiredException(
          statusCode: 403,
          code: 'REGISTRATION_REQUIRED',
          message: 'Sign first',
          context: 'RealunitBuy',
        ),
      );

      final cubit = build();
      await cubit.getPaymentInfo(amount: '300');

      final f = cubit.state as BuyPaymentInfoFailure;
      expect(f.error, PaymentInfoError.registrationRequired);
      expect(f.context, 'RealunitBuy');
    });

    test('generic exception → Failure(unknown)', () async {
      when(() => service.getPaymentInfo(any(), currency: any(named: 'currency')))
          .thenAnswer((_) async => throw Exception('network'));

      final cubit = build();
      await cubit.getPaymentInfo(amount: '300');

      final f = cubit.state as BuyPaymentInfoFailure;
      expect(f.error, PaymentInfoError.unknown);
      expect(f.message, '');
    });

    test('FormatException from service → Failure(unknown) with empty message', () async {
      when(() => service.getPaymentInfo(any(), currency: any(named: 'currency')))
          .thenAnswer(
        (_) async => throw const FormatException(
          'Unexpected character (at character 1)',
          'error code: 502',
        ),
      );

      final cubit = build();
      await cubit.getPaymentInfo(amount: '300');

      final f = cubit.state as BuyPaymentInfoFailure;
      expect(f.error, PaymentInfoError.unknown);
      expect(f.message, '');
      expect(f.message, isNot(contains('FormatException')));
      expect(f.message, isNot(contains('error code: 502')));
    });

    test('BitboxNotConnectedException → Failure(bitboxDisconnected)', () async {
      when(() => service.getPaymentInfo(any(), currency: any(named: 'currency')))
          .thenAnswer((_) async => throw const BitboxNotConnectedException());

      final cubit = build();
      await cubit.getPaymentInfo(amount: '300');

      final f = cubit.state as BuyPaymentInfoFailure;
      expect(f.error, PaymentInfoError.bitboxDisconnected);
    });

    test('ApiException 503 → Failure(priceSourceUnavailable)', () async {
      when(() => service.getPaymentInfo(any(), currency: any(named: 'currency')))
          .thenAnswer(
        (_) async => throw const ApiException(
          statusCode: 503,
          code: 'PRICE_SOURCE_UNAVAILABLE',
          message: 'RealUnit price source (Aktionariat) is currently unavailable',
        ),
      );

      final cubit = build();
      await cubit.getPaymentInfo(amount: '300');

      expect((cubit.state as BuyPaymentInfoFailure).error, PaymentInfoError.priceSourceUnavailable);
      expect(
        (cubit.state as BuyPaymentInfoFailure).message,
        'RealUnit price source (Aktionariat) is currently unavailable',
      );
    });

    test('ApiException 502 with empty message → Failure(priceSourceUnavailable)', () async {
      when(() => service.getPaymentInfo(any(), currency: any(named: 'currency')))
          .thenAnswer(
        (_) async => throw const ApiException(
          statusCode: 502,
          code: 'UNKNOWN',
          message: '',
        ),
      );

      final cubit = build();
      await cubit.getPaymentInfo(amount: '300');

      final f = cubit.state as BuyPaymentInfoFailure;
      expect(f.error, PaymentInfoError.priceSourceUnavailable);
      expect(f.message, '');
    });

    test('ApiException 502 with message → Failure(priceSourceUnavailable)', () async {
      when(() => service.getPaymentInfo(any(), currency: any(named: 'currency')))
          .thenAnswer(
        (_) async => throw const ApiException(
          statusCode: 502,
          code: 'UNKNOWN',
          message: 'upstream down',
        ),
      );

      final cubit = build();
      await cubit.getPaymentInfo(amount: '300');

      final f = cubit.state as BuyPaymentInfoFailure;
      expect(f.error, PaymentInfoError.priceSourceUnavailable);
      expect(f.message, 'upstream down');
    });

    test('ApiException with code PRICE_SOURCE_UNAVAILABLE (non-503) → priceSourceUnavailable', () async {
      when(() => service.getPaymentInfo(any(), currency: any(named: 'currency')))
          .thenAnswer(
        (_) async => throw const ApiException(
          statusCode: 500,
          code: 'PRICE_SOURCE_UNAVAILABLE',
          message: 'unavailable',
        ),
      );

      final cubit = build();
      await cubit.getPaymentInfo(amount: '300');

      expect((cubit.state as BuyPaymentInfoFailure).error, PaymentInfoError.priceSourceUnavailable);
      expect((cubit.state as BuyPaymentInfoFailure).message, 'unavailable');
    });

    test('other ApiException (e.g. 400) → Failure(unknown)', () async {
      when(() => service.getPaymentInfo(any(), currency: any(named: 'currency')))
          .thenAnswer(
        (_) async => throw const ApiException(statusCode: 400, code: 'BAD_REQUEST', message: 'bad'),
      );

      final cubit = build();
      await cubit.getPaymentInfo(amount: '300');

      expect((cubit.state as BuyPaymentInfoFailure).error, PaymentInfoError.unknown);
      expect((cubit.state as BuyPaymentInfoFailure).message, 'bad');
    });

    test('does not emit after close', () async {
      final completer = Completer<BuyPaymentInfo>();
      when(() => service.getPaymentInfo(any(), currency: any(named: 'currency')))
          .thenAnswer((_) => completer.future);

      final cubit = build();
      unawaited(cubit.getPaymentInfo(amount: '300'));
      await cubit.close();
      completer.complete(_info());
    });
  });
}
