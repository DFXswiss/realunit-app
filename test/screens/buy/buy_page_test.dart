import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/config/api_config.dart';
import 'package:realunit_wallet/packages/repository/cache_repository.dart';
import 'package:realunit_wallet/packages/repository/supported_fiat_repository.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_brokerbot_service.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_price_service.dart';
import 'package:realunit_wallet/packages/service/dfx/models/brokerbot/dfx_buy_shares_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/buy/buy_payment_info.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/payment_info_error.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_buy_payment_info_service.dart';
import 'package:realunit_wallet/packages/service/session_cache.dart';
import 'package:realunit_wallet/screens/buy/buy_page.dart';
import 'package:realunit_wallet/screens/buy/cubits/buy_converter/buy_converter_cubit.dart';
import 'package:realunit_wallet/screens/buy/cubits/buy_payment_info/buy_payment_info_cubit.dart';
import 'package:realunit_wallet/screens/buy/widgets/buy_confirm_button.dart';
import 'package:realunit_wallet/screens/buy/widgets/payment_action_required.dart';
import 'package:realunit_wallet/screens/buy/widgets/payment_converter.dart';
import 'package:realunit_wallet/screens/buy/widgets/payment_information.dart';
import 'package:realunit_wallet/styles/currency.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';

import '../../helper/helper.dart';

class MockBuyConverterCubit extends MockCubit<BuyConverterState> implements BuyConverterCubit {}

class MockBuyPaymentInfoCubit extends MockCubit<BuyPaymentInfoState>
    implements BuyPaymentInfoCubit {}

class MockDfxBrokerbotService extends Mock implements DfxBrokerbotService {}

class MockRealUnitBuyPaymentInfoService extends Mock implements RealUnitBuyPaymentInfoService {}

class MockDfxPriceService extends Mock implements DFXPriceService {}

class MockApiConfig extends Mock implements ApiConfig {}

class MockCacheRepository extends Mock implements CacheRepository {}

class MockSupportedFiatRepository extends Mock implements SupportedFiatRepository {}

void main() {
  late BuyConverterCubit converterCubit;
  late BuyPaymentInfoCubit buyPaymentInfoCubit;

  setUp(() {
    converterCubit = MockBuyConverterCubit();
    buyPaymentInfoCubit = MockBuyPaymentInfoCubit();

    when(() => converterCubit.state).thenReturn(const BuyConverterState());
    when(() => buyPaymentInfoCubit.state).thenReturn(const BuyPaymentInfoInitial());
    when(
      () => buyPaymentInfoCubit.getPaymentInfo(
        amount: any(named: 'amount'),
        currency: any(named: 'currency'),
      ),
    ).thenAnswer((_) => Future.value());
  });

  void setupDependencyInjection() {
    final getIt = GetIt.instance;
    getIt.registerSingleton<AppStore>(
      AppStore(() => MockApiConfig(), SessionCache(MockCacheRepository())),
    );
    getIt.registerSingleton<DfxBrokerbotService>(MockDfxBrokerbotService());
    getIt.registerSingleton<RealUnitBuyPaymentInfoService>(MockRealUnitBuyPaymentInfoService());
    getIt.registerSingleton<DFXPriceService>(MockDfxPriceService());
    final fiatRepo = MockSupportedFiatRepository();
    when(() => fiatRepo.getBuyable()).thenAnswer((_) async => const [Currency.chf, Currency.eur]);
    when(() => fiatRepo.getSellable()).thenAnswer((_) async => const [Currency.chf]);
    when(() => fiatRepo.getAll()).thenAnswer((_) async => const [Currency.chf, Currency.eur]);
    getIt.registerSingleton<SupportedFiatRepository>(fiatRepo);
  }

  setUpAll(() {
    registerFallbackValue(Currency.chf);
    setupDependencyInjection();
  });

  tearDownAll(() async => await GetIt.instance.reset());

  Widget buildSubject(Widget child) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: converterCubit),
        BlocProvider.value(value: buyPaymentInfoCubit),
      ],
      child: const BuyView(),
    );
  }

  group('$BuyPage', () {
    testWidgets('renders $BuyView', (tester) async {
      await tester.pumpApp(const BuyPage());

      expect(find.byType(BuyView), findsOne);
    });

    testWidgets('shows the 300 default and keeps the field freely editable — '
        'the payable never replaces the typed amount', (tester) async {
      final brokerbot = GetIt.instance<DfxBrokerbotService>() as MockDfxBrokerbotService;
      when(() => brokerbot.getBuyShares(any(), any())).thenAnswer(
        (_) async => BrokerbotBuySharesDto(
          shares: 217,
          pricePerShare: 1.38,
          availableShares: 50000,
        ),
      );

      await tester.pumpApp(const BuyPage());
      // Past the 100ms conversion debounce of the initial default.
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();

      final amountField = find.byType(TextField).first;
      // The default stays 300 — the Rappen payable (217 × 1.38 = 299.46)
      // belongs to the quote, not to the input field.
      expect(tester.widget<TextField>(amountField).controller!.text, '300');

      await tester.enterText(amountField, '25');
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();

      expect(tester.widget<TextField>(amountField).controller!.text, '25');
    });

    testWidgets('shows Rappen-exact charge under the amount without writing it into the field', (
      tester,
    ) async {
      final brokerbot = GetIt.instance<DfxBrokerbotService>() as MockDfxBrokerbotService;
      when(() => brokerbot.getBuyShares(any(), any())).thenAnswer(
        (_) async => BrokerbotBuySharesDto(
          shares: 217,
          pricePerShare: 1.38,
          availableShares: 50000,
        ),
      );

      await tester.pumpApp(const BuyPage());
      // Past the 100ms conversion debounce of the initial default.
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();

      final amountField = find.byType(TextField).first;
      expect(tester.widget<TextField>(amountField).controller!.text, '300');
      expect(find.byKey(const Key('buy-charged-amount')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('buy-charged-amount'))).data,
        contains('299.46'),
      );
    });
  });

  group('$BuyView', () {
    testWidgets('renders initially correctly', (tester) async {
      await tester.pumpApp(buildSubject(const BuyView()));

      expect(find.byType(PaymentConverter), findsOne);
      expect(find.byType(PaymentInformation), findsOne);
    });

    testWidgets('hides charged amount when payable is empty', (tester) async {
      when(() => converterCubit.state).thenReturn(
        const BuyConverterState(fiatText: '300', payableText: ''),
      );

      await tester.pumpApp(buildSubject(const BuyView()));

      expect(find.byKey(const Key('buy-charged-amount')), findsNothing);
    });

    testWidgets('hides charged amount when payable matches the typed text', (tester) async {
      when(() => converterCubit.state).thenReturn(
        const BuyConverterState(fiatText: '125.50', payableText: '125.50'),
      );

      await tester.pumpApp(buildSubject(const BuyView()));

      expect(find.byKey(const Key('buy-charged-amount')), findsNothing);
    });

    testWidgets('hides charged amount when payable is the same value with extra fraction digits', (
      tester,
    ) async {
      when(() => converterCubit.state).thenReturn(
        const BuyConverterState(fiatText: '300', payableText: '300.00'),
      );

      await tester.pumpApp(buildSubject(const BuyView()));

      expect(find.byKey(const Key('buy-charged-amount')), findsNothing);
    });

    testWidgets('renders correctly when $BuyPaymentInfo is available', (tester) async {
      when(() => buyPaymentInfoCubit.state).thenReturn(
        const BuyPaymentInfoSuccess(
          BuyPaymentInfo(
            amount: 300,
            id: 1,
            iban: 'iban',
            bic: 'bic',
            name: 'name',
            street: 'street',
            number: 'number',
            zip: 'zip',
            city: 'city',
            country: 'country',
            currency: Currency.chf,
          ),
        ),
      );

      whenListen(
        converterCubit,
        Stream.fromIterable([
          const BuyConverterState(fiatText: '100', sharesText: '1.00', loading: true),
          const BuyConverterState(fiatText: '100', sharesText: '1.00', loading: false),
        ]),
        initialState: const BuyConverterState(fiatText: '100', sharesText: '1.00'),
      );

      await tester.pumpApp(buildSubject(const BuyView()));
      await tester.pumpAndSettle();

      expect(find.byType(PaymentConverter), findsOne);
      // On a valid quote the bottom CTA is the binding-buy button; the
      // bank-transfer details have moved to the BuyPaymentDetailsPage.
      expect(find.byType(BuyConfirmButton), findsOne);
      expect(find.text(S.current.buyPaymentConfirm), findsOne);
    });

    testWidgets('on an EUR quote the confirm CTA keeps the EUR settlement IBAN, not a CHF leftover', (
      tester,
    ) async {
      const eurQuote = BuyPaymentInfo(
        amount: 300,
        id: 1,
        iban: 'CH9708307000560946317',
        bic: 'bic',
        name: 'name',
        street: 'street',
        number: 'number',
        zip: 'zip',
        city: 'city',
        country: 'country',
        currency: Currency.eur,
      );
      when(() => buyPaymentInfoCubit.state).thenReturn(
        const BuyPaymentInfoSuccess(eurQuote),
      );
      when(() => converterCubit.state).thenReturn(
        const BuyConverterState(currency: Currency.eur, fiatText: '300'),
      );

      await tester.pumpApp(buildSubject(const BuyView()));

      expect(find.byType(BuyConfirmButton), findsOne);
      expect(find.text(S.current.buyPaymentConfirm), findsOne);
      final confirm = tester.widget<BuyConfirmButton>(find.byType(BuyConfirmButton));
      expect(confirm.buyPaymentInfo.iban, 'CH9708307000560946317');
      expect(confirm.buyPaymentInfo.currency, Currency.eur);
      expect(confirm.buyPaymentInfo.iban, isNot('CH2208307000560946309'));
    });

    testWidgets('renders correctly when $BuyPaymentInfo is loading', (tester) async {
      when(() => buyPaymentInfoCubit.state).thenReturn(const BuyPaymentInfoLoading());

      await tester.pumpApp(buildSubject(const BuyView()));

      expect(find.byType(PaymentConverter), findsOne);
      expect(find.byType(CupertinoActivityIndicator), findsOne);
    });

    testWidgets('renders correctly when registration is required', (tester) async {
      when(() => buyPaymentInfoCubit.state).thenReturn(
        const BuyPaymentInfoFailure(PaymentInfoError.registrationRequired),
      );

      await tester.pumpApp(buildSubject(const BuyView()));

      expect(find.byType(PaymentActionRequired), findsOne);
      expect(find.byType(PaymentInformation), findsOne);
      expect(find.text(S.current.registrationRequired), findsOne);
      expect(
        find.byWidgetPredicate(
          (Widget widget) => widget is AppFilledButton && widget.onPressed != null,
        ),
        findsOne,
      );
    });

    testWidgets('renders correctly when kyc is required', (tester) async {
      when(() => buyPaymentInfoCubit.state).thenReturn(
        const BuyPaymentInfoFailure(PaymentInfoError.kycRequired),
      );

      await tester.pumpApp(buildSubject(const BuyView()));

      expect(find.byType(PaymentActionRequired), findsOne);
      expect(find.byType(PaymentInformation), findsOne);
      expect(find.text(S.current.identityCheckRequired), findsOne);
      expect(
        find.byWidgetPredicate(
          (Widget widget) => widget is AppFilledButton && widget.onPressed != null,
        ),
        findsOne,
      );
    });

    testWidgets('renders correctly when min amount is not met', (tester) async {
      // Non-integer min: the API returns the minimum in the input currency, so
      // a CHF-denominated minimum shown in EUR comes back fractional (here 108.4).
      // The traded amount is quantized with .round() before it is sent, so the
      // displayed value must round UP to the smallest whole amount that still
      // satisfies the server-side minimum.
      final minAmount = 108.4;
      final currency = Currency.eur;

      when(() => buyPaymentInfoCubit.state).thenReturn(
        BuyPaymentInfoMinAmountNotMetFailure(
          PaymentInfoError.minAmountNotMet,
          minAmount: minAmount,
        ),
      );
      when(() => converterCubit.state).thenReturn(
        BuyConverterState(
          currency: currency,
        ),
      );

      await tester.pumpApp(buildSubject(const BuyView()));

      expect(find.byType(PaymentActionRequired), findsNothing);
      expect(find.byType(PaymentInformation), findsOne);
      expect(find.text(S.current.buyMinAmount('${minAmount.ceil()}', currency.code)), findsOne);
      expect(
        find.byWidgetPredicate(
          (Widget widget) => widget is AppFilledButton && widget.onPressed == null,
        ),
        findsOne,
      );
    });

    testWidgets('retries payment info when unknown error is shown', (tester) async {
      when(() => buyPaymentInfoCubit.state).thenReturn(
        const BuyPaymentInfoFailure(
          PaymentInfoError.unknown,
          message: 'The purchase could not be quoted. Please try again later.',
        ),
      );
      when(() => converterCubit.state).thenReturn(
        const BuyConverterState(
          currency: Currency.eur,
          fiatText: '300',
          payableText: '299.46',
        ),
      );

      await tester.pumpApp(buildSubject(const BuyView()));

      expect(
        find.text('The purchase could not be quoted. Please try again later.'),
        findsOne,
      );
      expect(find.text(S.current.retry), findsOne);

      await tester.tap(find.text(S.current.retry));
      await tester.pump();

      verify(
        () => buyPaymentInfoCubit.getPaymentInfo(
          amount: '299.46',
          currency: Currency.eur,
        ),
      ).called(1);
    });

    testWidgets('updates controllers when $BuyConverterState changes', (tester) async {
      whenListen(
        converterCubit,
        Stream.fromIterable([
          const BuyConverterState(fiatText: '5.00', sharesText: '0.10', loading: true),
          const BuyConverterState(fiatText: '5.00', sharesText: '0.50', loading: false),
        ]),
        initialState: const BuyConverterState(fiatText: '1.00', sharesText: '0.10'),
      );

      await tester.pumpApp(buildSubject(const BuyView()));
      await tester.pumpAndSettle();

      final amountField = find.byType(TextField).first;
      final resultField = find.byType(TextField).last;

      TextField amount = tester.widget(amountField);
      TextField result = tester.widget(resultField);

      expect(amount.controller!.text, equals('5.00'));
      expect(result.controller!.text, equals('0.50'));
    });

    testWidgets('requests the quote with the live payable, not the typed field text', (
      tester,
    ) async {
      whenListen(
        converterCubit,
        Stream.fromIterable([
          const BuyConverterState(
            fiatText: '300',
            payableText: '',
            sharesText: '217',
            loading: true,
          ),
          const BuyConverterState(
            fiatText: '300',
            payableText: '299.46',
            sharesText: '217',
            loading: false,
          ),
        ]),
        initialState: const BuyConverterState(fiatText: '300'),
      );

      await tester.pumpApp(buildSubject(const BuyView()));
      await tester.pumpAndSettle();

      verify(
        () => buyPaymentInfoCubit.getPaymentInfo(
          amount: '299.46',
          currency: Currency.chf,
        ),
      ).called(1);
    });

    testWidgets('requests the EUR quote with the live payable when converter settles in EUR', (
      tester,
    ) async {
      whenListen(
        converterCubit,
        Stream.fromIterable([
          const BuyConverterState(
            fiatText: '300',
            payableText: '',
            sharesText: '217',
            loading: true,
            currency: Currency.eur,
          ),
          const BuyConverterState(
            fiatText: '300',
            payableText: '299.46',
            sharesText: '217',
            loading: false,
            currency: Currency.eur,
          ),
        ]),
        initialState: const BuyConverterState(fiatText: '300', currency: Currency.eur),
      );

      await tester.pumpApp(buildSubject(const BuyView()));
      await tester.pumpAndSettle();

      verify(
        () => buyPaymentInfoCubit.getPaymentInfo(
          amount: '299.46',
          currency: Currency.eur,
        ),
      ).called(1);
    });
  });
}
