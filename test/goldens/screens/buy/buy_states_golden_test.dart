import 'package:alchemist/alchemist.dart' show precacheImages;
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
import 'package:realunit_wallet/screens/buy/cubits/buy_confirm/buy_confirm_cubit.dart';
import 'package:realunit_wallet/screens/buy/cubits/buy_converter/buy_converter_cubit.dart';
import 'package:realunit_wallet/screens/buy/cubits/buy_payment_info/buy_payment_info_cubit.dart';
import 'package:realunit_wallet/screens/buy/widgets/buy_confirm_button.dart';
import 'package:realunit_wallet/styles/currency.dart';

import '../../../helper/helper.dart';

class _MockBuyConfirmCubit extends MockCubit<BuyConfirmState>
    implements BuyConfirmCubit {}

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

class _MockSupportedFiatRepository extends Mock
    implements SupportedFiatRepository {}

// Shared buy quote the confirm CTA renders and confirms.
const _paymentInfo = BuyPaymentInfo(
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
);

void main() {
  late _MockSupportedFiatRepository fiatRepo;

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
    fiatRepo = _MockSupportedFiatRepository();
    getIt.registerSingleton<SupportedFiatRepository>(fiatRepo);
  });

  tearDownAll(() async => GetIt.instance.reset());

  // ---- BuyConfirmButtonView: the binding-buy CTA after a valid quote ----
  // Rendered in isolation with a mocked BuyConfirmCubit because the production
  // widget (`buy_confirm_button.dart:27`) wraps the view in its own
  // `BlocProvider(create:)`, which would shadow any injected cubit and start at
  // `BuyConfirmInitial` — the transient loading / failure surfaces are only
  // reproducible by driving a mocked cubit directly (#815).
  group('$BuyConfirmButtonView', () {
    late _MockBuyConfirmCubit confirmCubit;

    setUp(() {
      confirmCubit = _MockBuyConfirmCubit();
    });

    Widget buildCta() => wrapForGolden(
          Scaffold(
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  BlocProvider<BuyConfirmCubit>.value(
                    value: confirmCubit,
                    child: const BuyConfirmButtonView(buyPaymentInfo: _paymentInfo),
                  ),
                ],
              ),
            ),
          ),
        );

    // `BuyConfirmLoading` drives the CTA's `state: .loading` branch
    // (`buy_confirm_button.dart:82`), a `CupertinoActivityIndicator`; freeze it
    // on the first frame instead of letting pumpAndSettle time out.
    goldenTest(
      'confirm CTA loading — spinner in the buy button',
      fileName: 'buy_confirm_loading',
      constraints: phoneConstraints,
      pumpBeforeTest: pumpOnce,
      builder: () {
        when(() => confirmCubit.state).thenReturn(const BuyConfirmLoading());
        return buildCta();
      },
    );

    // Emitting `BuyConfirmFailure` drives the BlocConsumer listener
    // (`buy_confirm_button.dart:64-73`) to show the failure SnackBar. Each
    // error code's user-facing text is captured (aktionariat and
    // primaryEmailRequired intentionally share the same copy).
    // The `.state` getter follows the emission (BuyConfirmFailure) — the builder
    // still renders the idle button, which is the real post-failure UI.
    for (final (error, name) in const [
      (BuyConfirmError.aktionariat, 'buy_confirm_failed_aktionariat'),
      (BuyConfirmError.amountTooLow, 'buy_confirm_failed_amount_too_low'),
      (BuyConfirmError.primaryEmailRequired, 'buy_confirm_failed_primary_email_required'),
      (BuyConfirmError.unknown, 'buy_confirm_failed_unknown'),
    ]) {
      goldenTest(
        'confirm failed SnackBar — ${error.name}',
        fileName: name,
        constraints: phoneConstraints,
        pumpBeforeTest: (tester) async {
          await tester.pump(); // deliver the emission to the listener
          await tester.pumpAndSettle(); // run the SnackBar entrance to completion
        },
        builder: () {
          whenListen(
            confirmCubit,
            Stream<BuyConfirmState>.value(BuyConfirmFailure(error)),
            initialState: const BuyConfirmInitial(),
          );
          return buildCta();
        },
      );
    }
  });

  // ---- BuyView: gate / picker surfaces of the buy page ----
  group('$BuyView', () {
    late _MockBuyConverterCubit converterCubit;
    late _MockBuyPaymentInfoCubit paymentInfoCubit;

    setUp(() {
      converterCubit = _MockBuyConverterCubit();
      paymentInfoCubit = _MockBuyPaymentInfoCubit();
      when(() => converterCubit.state)
          .thenReturn(const BuyConverterState(currency: Currency.chf));
      when(() => paymentInfoCubit.state)
          .thenReturn(const BuyPaymentInfoInitial());
      when(
        () => paymentInfoCubit.getPaymentInfo(
          amount: any(named: 'amount'),
          currency: any(named: 'currency'),
        ),
      ).thenAnswer((_) => Future.value());
      // Deterministic, backend-authoritative picker list (no `now()`/random).
      when(() => fiatRepo.getBuyable())
          .thenAnswer((_) async => const [Currency.chf, Currency.eur]);
      when(() => fiatRepo.getSellable())
          .thenAnswer((_) async => const [Currency.chf]);
      when(() => fiatRepo.getAll())
          .thenAnswer((_) async => const [Currency.chf, Currency.eur]);
    });

    Widget buildSubject() => wrapForGolden(
          MultiBlocProvider(
            providers: [
              BlocProvider<BuyConverterCubit>.value(value: converterCubit),
              BlocProvider<BuyPaymentInfoCubit>.value(value: paymentInfoCubit),
            ],
            child: const BuyView(),
          ),
        );

    // `PaymentInfoError.bitboxDisconnected` renders the info block
    // ("BitBox ist nicht verbunden", `payment_information.dart:35-39`) plus the
    // reconnect CTA (`payment_action_button.dart:122-138`).
    goldenTest(
      'bitbox disconnected — info block + reconnect CTA',
      fileName: 'buy_bitbox_disconnected',
      constraints: phoneConstraints,
      builder: () {
        when(() => paymentInfoCubit.state).thenReturn(
          const BuyPaymentInfoFailure(PaymentInfoError.bitboxDisconnected),
        );
        return buildSubject();
      },
    );

    // Tapping the currency PopupMenuButton (`payment_converter.dart:126`) opens
    // the overlay with the buyable currencies. `precacheImages` loads the RealU
    // logo asset AND drains the `getBuyable()` future so the picker is enabled
    // before the tap.
    goldenTest(
      'currency picker popup open — CHF/EUR items',
      fileName: 'buy_currency_picker_open',
      constraints: phoneConstraints,
      pumpBeforeTest: (tester) async {
        await precacheImages(tester);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('buy-currency-picker')));
        await tester.pumpAndSettle();
      },
      builder: () => buildSubject(),
    );

    // `getBuyable()` failing drives the initState onError branch
    // (`payment_converter.dart:46-68`): the red SnackBar
    // ("Währungsliste konnte nicht geladen werden") and the disabled picker
    // (key `buy-currency-picker-disabled`, `enabled: false`).
    goldenTest(
      'currency list load failed — red SnackBar + disabled picker',
      fileName: 'buy_currency_load_failed',
      constraints: phoneConstraints,
      pumpBeforeTest: (tester) async {
        await precacheImages(tester);
        await tester.pumpAndSettle();
      },
      builder: () {
        when(() => fiatRepo.getBuyable())
            .thenAnswer((_) async => throw Exception('load failed'));
        return buildSubject();
      },
    );
  });
}
