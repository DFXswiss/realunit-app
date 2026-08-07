import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/config/api_config.dart';
import 'package:realunit_wallet/packages/repository/cache_repository.dart';
import 'package:realunit_wallet/packages/repository/supported_fiat_repository.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_brokerbot_service.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_price_service.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/buy/buy_payment_info.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/payment_info_error.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_buy_payment_info_service.dart';
import 'package:realunit_wallet/packages/service/session_cache.dart';
import 'package:realunit_wallet/screens/buy/buy_page.dart';
import 'package:realunit_wallet/screens/buy/cubits/buy_converter/buy_converter_cubit.dart';
import 'package:realunit_wallet/screens/buy/cubits/buy_payment_info/buy_payment_info_cubit.dart';
import 'package:realunit_wallet/styles/currency.dart';

import '../../../helper/helper.dart';

class _MockBuyConverterCubit extends MockCubit<BuyConverterState>
    implements BuyConverterCubit {}

class _MockBuyPaymentInfoCubit extends MockCubit<BuyPaymentInfoState>
    implements BuyPaymentInfoCubit {}

class _MockDfxBrokerbotService extends Mock implements DfxBrokerbotService {}

class _MockRealUnitBuyPaymentInfoService extends Mock
    implements RealUnitBuyPaymentInfoService {}

class _MockDfxPriceService extends Mock implements DFXPriceService {}

class _MockApiConfig extends Mock implements ApiConfig {}

class _MockCacheRepository extends Mock implements CacheRepository {}

class _MockSupportedFiatRepository extends Mock implements SupportedFiatRepository {}

void main() {
  late _MockBuyConverterCubit converterCubit;
  late _MockBuyPaymentInfoCubit paymentInfoCubit;

  setUp(() {
    converterCubit = _MockBuyConverterCubit();
    paymentInfoCubit = _MockBuyPaymentInfoCubit();
    when(() => converterCubit.state).thenReturn(const BuyConverterState());
    when(() => paymentInfoCubit.state).thenReturn(const BuyPaymentInfoInitial());
    when(
      () => paymentInfoCubit.getPaymentInfo(
        amount: any(named: 'amount'),
        currency: any(named: 'currency'),
      ),
    ).thenAnswer((_) => Future.value());
  });

  setUpAll(() {
    registerFallbackValue(Currency.chf);
    final getIt = GetIt.instance;
    getIt.registerSingleton<AppStore>(
      AppStore(() => _MockApiConfig(), SessionCache(_MockCacheRepository())),
    );
    getIt.registerSingleton<DfxBrokerbotService>(_MockDfxBrokerbotService());
    getIt.registerSingleton<RealUnitBuyPaymentInfoService>(
      _MockRealUnitBuyPaymentInfoService(),
    );
    getIt.registerSingleton<DFXPriceService>(_MockDfxPriceService());
    final fiatRepo = _MockSupportedFiatRepository();
    when(() => fiatRepo.getBuyable())
        .thenAnswer((_) async => const [Currency.chf, Currency.eur]);
    when(() => fiatRepo.getSellable()).thenAnswer((_) async => const [Currency.chf]);
    when(() => fiatRepo.getAll())
        .thenAnswer((_) async => const [Currency.chf, Currency.eur]);
    getIt.registerSingleton<SupportedFiatRepository>(fiatRepo);
  });

  tearDownAll(() async => GetIt.instance.reset());

  Widget buildSubject() => MultiBlocProvider(
        providers: [
          BlocProvider<BuyConverterCubit>.value(value: converterCubit),
          BlocProvider<BuyPaymentInfoCubit>.value(value: paymentInfoCubit),
        ],
        child: const BuyView(),
      );

  group('$BuyView', () {
    goldenTest(
      'initial empty converter',
      fileName: 'buy_initial',
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      builder: () => wrapForGolden(buildSubject()),
    );

    goldenTest(
      'payment info loaded',
      fileName: 'buy_payment_info_loaded',
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      builder: () {
        when(() => paymentInfoCubit.state).thenReturn(
          const BuyPaymentInfoSuccess(
            BuyPaymentInfo(
              amount: 300,
              id: 1,
              iban: 'CH00 0000 0000 0000 0000 0',
              bic: 'BICCBIC',
              name: 'RealUnit AG',
              street: 'Bahnhofstrasse',
              number: '1',
              zip: '8001',
              city: 'Zurich',
              country: 'Switzerland',
              currency: Currency.chf,
            ),
          ),
        );
        when(() => converterCubit.state).thenReturn(
          const BuyConverterState(
            fiatText: '100',
            sharesText: '1.00',
            currency: Currency.chf,
          ),
        );
        return wrapForGolden(buildSubject());
      },
    );

    goldenTest(
      'payment info loading',
      fileName: 'buy_payment_info_loading',
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      // Loading state renders a CircularProgressIndicator — its animation
      // never settles, so pumpAndSettle (default in precacheImages) hits
      // its timeout. pumpOnce captures the first frame without waiting.
      pumpBeforeTest: pumpOnce,
      builder: () {
        when(() => paymentInfoCubit.state)
            .thenReturn(const BuyPaymentInfoLoading());
        when(() => converterCubit.state).thenReturn(
          const BuyConverterState(
            fiatText: '100',
            sharesText: '1.00',
            currency: Currency.chf,
          ),
        );
        return wrapForGolden(buildSubject());
      },
    );

    goldenTest(
      'kyc required failure',
      fileName: 'buy_kyc_required',
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      builder: () {
        when(() => paymentInfoCubit.state).thenReturn(
          const BuyPaymentInfoFailure(PaymentInfoError.kycRequired),
        );
        when(() => converterCubit.state).thenReturn(
          const BuyConverterState(
            fiatText: '100',
            sharesText: '1.00',
            currency: Currency.chf,
          ),
        );
        return wrapForGolden(buildSubject());
      },
    );

    goldenTest(
      'registration required failure',
      fileName: 'buy_registration_required',
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      builder: () {
        when(() => paymentInfoCubit.state).thenReturn(
          const BuyPaymentInfoFailure(PaymentInfoError.registrationRequired),
        );
        when(() => converterCubit.state).thenReturn(
          const BuyConverterState(
            fiatText: '100',
            sharesText: '1.00',
            currency: Currency.chf,
          ),
        );
        return wrapForGolden(buildSubject());
      },
    );

    goldenTest(
      'primary email required failure',
      fileName: 'buy_primary_email_required',
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      builder: () {
        when(() => paymentInfoCubit.state).thenReturn(
          const BuyPaymentInfoFailure(PaymentInfoError.primaryEmailRequired),
        );
        when(() => converterCubit.state).thenReturn(
          const BuyConverterState(
            fiatText: '100',
            sharesText: '1.00',
            currency: Currency.chf,
          ),
        );
        return wrapForGolden(buildSubject());
      },
    );

    goldenTest(
      'primary email not confirmed failure',
      fileName: 'buy_primary_email_not_confirmed',
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      builder: () {
        when(() => paymentInfoCubit.state).thenReturn(
          const BuyPaymentInfoFailure(PaymentInfoError.primaryEmailNotConfirmed),
        );
        when(() => converterCubit.state).thenReturn(
          const BuyConverterState(
            fiatText: '100',
            sharesText: '1.00',
            currency: Currency.chf,
          ),
        );
        return wrapForGolden(buildSubject());
      },
    );

    goldenTest(
      'min amount not met failure',
      fileName: 'buy_min_amount_not_met',
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      builder: () {
        when(() => paymentInfoCubit.state).thenReturn(
          const BuyPaymentInfoMinAmountNotMetFailure(
            PaymentInfoError.minAmountNotMet,
            minAmount: 10,
          ),
        );
        when(() => converterCubit.state).thenReturn(
          const BuyConverterState(
            fiatText: '1',
            sharesText: '0.01',
            currency: Currency.chf,
          ),
        );
        return wrapForGolden(buildSubject());
      },
    );

    goldenTest(
      'unknown error failure',
      fileName: 'buy_unknown_error',
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      builder: () {
        when(() => paymentInfoCubit.state).thenReturn(
          const BuyPaymentInfoFailure(PaymentInfoError.unknown),
        );
        when(() => converterCubit.state).thenReturn(
          const BuyConverterState(
            fiatText: '100',
            sharesText: '1.00',
            currency: Currency.chf,
          ),
        );
        return wrapForGolden(buildSubject());
      },
    );

    goldenTest(
      'price source (Aktionariat) unavailable failure',
      fileName: 'buy_price_source_unavailable',
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      builder: () {
        when(() => paymentInfoCubit.state).thenReturn(
          const BuyPaymentInfoFailure(PaymentInfoError.priceSourceUnavailable),
        );
        when(() => converterCubit.state).thenReturn(
          const BuyConverterState(
            fiatText: '100',
            sharesText: '1.00',
            currency: Currency.chf,
          ),
        );
        return wrapForGolden(buildSubject());
      },
    );
  });
}
