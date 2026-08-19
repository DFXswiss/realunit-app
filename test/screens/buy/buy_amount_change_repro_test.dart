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
import 'package:realunit_wallet/packages/service/dfx/models/brokerbot/dfx_buy_price_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/brokerbot/dfx_buy_shares_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/buy/buy_payment_info.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_buy_payment_info_service.dart';
import 'package:realunit_wallet/packages/service/session_cache.dart';
import 'package:realunit_wallet/packages/utils/fiat_amount.dart';
import 'package:realunit_wallet/screens/buy/buy_page.dart';
import 'package:realunit_wallet/screens/buy/cubits/buy_converter/buy_converter_cubit.dart';
import 'package:realunit_wallet/screens/buy/cubits/buy_payment_info/buy_payment_info_cubit.dart';
import 'package:realunit_wallet/screens/buy/widgets/payment_action_required.dart';
import 'package:realunit_wallet/styles/currency.dart';

import '../../helper/helper.dart';

class MockDfxBrokerbotService extends Mock implements DfxBrokerbotService {}

class MockRealUnitBuyPaymentInfoService extends Mock
    implements RealUnitBuyPaymentInfoService {}

class MockDfxPriceService extends Mock implements DFXPriceService {}

class MockApiConfig extends Mock implements ApiConfig {}

class MockCacheRepository extends Mock implements CacheRepository {}

class MockSupportedFiatRepository extends Mock implements SupportedFiatRepository {}

/// Matches [BuyConverterCubit]'s 100 ms debounce, plus a little slack so the
/// timer body (brokerbot call → loading:false → payment-info fetch) can finish.
const _afterDebounce = Duration(milliseconds: 150);

/// Production-like floor used when the quote returns `AmountTooLow`.
const _minVolume = 100.0;

void main() {
  late MockDfxBrokerbotService brokerbotService;
  late MockRealUnitBuyPaymentInfoService paymentInfoService;

  void setupDependencyInjection() {
    final getIt = GetIt.instance;
    brokerbotService = MockDfxBrokerbotService();
    paymentInfoService = MockRealUnitBuyPaymentInfoService();

    getIt.registerSingleton<AppStore>(
      AppStore(() => MockApiConfig(), SessionCache(MockCacheRepository())),
    );
    getIt.registerSingleton<DfxBrokerbotService>(brokerbotService);
    getIt.registerSingleton<RealUnitBuyPaymentInfoService>(paymentInfoService);
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

  setUp(() {
    reset(brokerbotService);
    reset(paymentInfoService);
    _stubProductionLikeQuotes(brokerbotService, paymentInfoService);
  });

  group('BuyPage amount change (customer reproduction)', () {
    testWidgets(
      'character-by-character replace of 300 with 100 does not show the support-contact error',
      (tester) async {
        await _pumpLoadedBuyPage(tester);

        for (final value in ['30', '3', '', '1', '10', '100']) {
          await _enterAmount(tester, value);
        }

        _expectHealthyQuote(
          tester,
          expectedAmount: '100',
          reasonPrefix:
              'After deleting 300 digit-by-digit and typing 100, the screen must '
              'keep a valid quote. Intermediate 0–3 are AmountTooLow only; 100 '
              'is a valid quote in production.',
        );
      },
    );

    testWidgets(
      'replacing 300 with 100 in one step does not show the support-contact error',
      (tester) async {
        await _pumpLoadedBuyPage(tester);

        await _enterAmount(tester, '');
        await _enterAmount(tester, '100');

        _expectHealthyQuote(
          tester,
          expectedAmount: '100',
          reasonPrefix:
              'After clearing the default 300 and typing 100 in one step, the '
              'screen must keep a valid quote. The quote API accepts 100.',
        );
      },
    );

    testWidgets(
      'typing 1.000 (thousands grouping) is shown as 1000 and does not show an error',
      (tester) async {
        await _pumpLoadedBuyPage(tester);

        await _enterAmount(tester, '1.000');

        final snapshot = _snapshot(tester);
        expect(
          find.text(S.current.invalidAmountFormatTitle),
          findsNothing,
          reason:
              'Typing 1.000 must be rewritten to 1000; the ambiguous-amount '
              'hint must not appear. $snapshot',
        );
        expect(
          find.text(S.current.invalidAmountFormatDescription),
          findsNothing,
          reason:
              'Typing 1.000 must be rewritten to 1000; the ambiguous-amount '
              'description must not appear. $snapshot',
        );
        _expectHealthyQuote(
          tester,
          expectedAmount: '1000',
          reasonPrefix:
              'Typing 1.000 must appear in the field as 1000 and keep a valid '
              'quote. The field normalises the thousands group before the '
              'parser sees it.',
        );
      },
    );

    testWidgets(
      'typing 1.000 character by character leaves partials alone, then shows 1000',
      (tester) async {
        await _pumpLoadedBuyPage(tester);
        await tester.enterText(_amountField, '');
        await tester.pump();

        for (final value in ['1', '1.', '1.0', '1.00']) {
          await tester.enterText(_amountField, value);
          await tester.pump();
          expect(
            tester.widget<TextField>(_amountField).controller!.text,
            value,
            reason:
                'Intermediate "$value" must stay as typed; the formatter must '
                'not rewrite partial thousands-group input. ${_snapshot(tester)}',
          );
        }

        await tester.enterText(_amountField, '1.000');
        await tester.pump();

        final afterGroup = tester.widget<TextField>(_amountField).controller!;
        expect(
          afterGroup.text,
          '1000',
          reason:
              'The last character of 1.000 must rewrite the field to 1000. '
              '${_snapshot(tester)}',
        );
        expect(
          afterGroup.selection,
          const TextSelection.collapsed(offset: 4),
          reason:
              'After rewriting 1.000 to 1000 the caret must sit at the end '
              'so further typing appends. ${_snapshot(tester)}',
        );

        for (final value in ['1000.', '1000.0', '1000.00']) {
          await tester.enterText(_amountField, value);
          await tester.pump();
          expect(
            tester.widget<TextField>(_amountField).controller!.text,
            value,
            reason:
                'Continuation "$value" must stay as typed. ${_snapshot(tester)}',
          );
        }

        await tester.enterText(_amountField, '1000.000');
        await tester.pump(_afterDebounce);
        await tester.pump();

        _expectHealthyQuote(
          tester,
          expectedAmount: '1000000',
          reasonPrefix:
              'Typing .000 after 1000 must appear in the field as 1000000 '
              'and keep a valid quote.',
        );
        expect(
          tester.widget<TextField>(_amountField).controller!.selection,
          const TextSelection.collapsed(offset: 7),
          reason:
              'After rewriting 1000.000 to 1000000 the caret must sit at '
              'the end. ${_snapshot(tester)}',
        );
      },
    );
  });
}

void _stubProductionLikeQuotes(
  MockDfxBrokerbotService brokerbot,
  MockRealUnitBuyPaymentInfoService paymentInfo,
) {
  // Real DfxBrokerbotService rejects unparseable / non-positive input
  // (empty, "1.000") and otherwise returns a conversion. Amounts 1–3 are
  // convertible; the min-amount gate lives on the quote, not here.
  when(() => brokerbot.getBuyShares(any(), any())).thenAnswer((invocation) async {
    final raw = invocation.positionalArguments[0] as String;
    final parsed = tryParseFiatAmount(raw);
    if (parsed == null || parsed <= 0) {
      throw Exception('Shares request failed: amountInput is not valid');
    }
    return BrokerbotBuySharesDto(
      shares: parsed < 1.43 ? 1 : parsed ~/ 1.43,
      pricePerShare: 1.43,
      availableShares: 100000,
    );
  });

  when(() => brokerbot.getBuyPrice(any(), any())).thenAnswer((invocation) async {
    final raw = invocation.positionalArguments[0] as String;
    final shares = int.tryParse(raw);
    if (shares == null || shares <= 0) {
      throw Exception('BuyPrice request failed: sharesInput is not valid');
    }
    return BrokerbotBuyPriceDto(
      totalCost: shares * 1.43,
      pricePerShare: 1.43,
      availableShares: 100000,
    );
  });

  when(
    () => paymentInfo.getPaymentInfo(any(), currency: any(named: 'currency')),
  ).thenAnswer((invocation) async {
    final amount = invocation.positionalArguments[0] as int;
    final currency =
        invocation.namedArguments[#currency] as Currency? ?? Currency.chf;
    if (amount >= 4) {
      return _quote(amount: amount, currency: currency, isValid: true);
    }
    return _quote(
      amount: amount,
      currency: currency,
      isValid: false,
      error: 'AmountTooLow',
      minVolume: _minVolume,
    );
  });
}

BuyPaymentInfo _quote({
  required int amount,
  required Currency currency,
  required bool isValid,
  String? error,
  double? minVolume,
}) {
  return BuyPaymentInfo(
    id: 1,
    iban: 'CH56 0483 5012 3456 78',
    bic: 'CRESCHZZ80A',
    name: 'DFX AG',
    street: 'Bahnhofstrasse',
    number: '1',
    zip: '8000',
    city: 'Zurich',
    country: 'CH',
    currency: currency,
    amount: amount.toDouble(),
    isValid: isValid,
    error: error,
    minVolume: minVolume,
  );
}

Finder get _amountField => find.byType(TextField).first;

Future<void> _pumpLoadedBuyPage(WidgetTester tester) async {
  await tester.pumpApp(const BuyPage());
  // BuyPage constructs BuyConverterCubit(..)..onFiatChanged('300').
  await tester.pump();
  await tester.pump(_afterDebounce);
  await tester.pump();

  final amount = tester.widget<TextField>(_amountField);
  expect(
    amount.controller!.text,
    '300',
    reason: 'Precondition failed: default 300 did not land. ${_snapshot(tester)}',
  );
  expect(
    find.text(S.current.paymentInformationFailed),
    findsNothing,
    reason:
        'Precondition failed: support-contact error already visible on the '
        'default 300. ${_snapshot(tester)}',
  );
}

Future<void> _enterAmount(WidgetTester tester, String value) async {
  await tester.enterText(_amountField, value);
  await tester.pump(_afterDebounce);
  await tester.pump();
}

void _expectHealthyQuote(
  WidgetTester tester, {
  required String expectedAmount,
  required String reasonPrefix,
}) {
  final snapshot = _snapshot(tester);
  final amount = tester.widget<TextField>(_amountField);

  expect(
    find.text(S.current.paymentInformationFailed),
    findsNothing,
    reason: '$reasonPrefix Support title is visible. $snapshot',
  );
  expect(
    find.text(S.current.paymentInformationFailedDescription),
    findsNothing,
    reason: '$reasonPrefix Support description is visible. $snapshot',
  );
  expect(
    find.byType(CupertinoActivityIndicator),
    findsNothing,
    reason: '$reasonPrefix Payment info is still spinning. $snapshot',
  );
  expect(
    amount.controller!.text,
    expectedAmount,
    reason: '$reasonPrefix Amount field is not "$expectedAmount". $snapshot',
  );
}

String _snapshot(WidgetTester tester) {
  final amountText = tester.widget<TextField>(_amountField).controller?.text;
  final viewContext = tester.element(find.byType(BuyView));
  final paymentState = viewContext.read<BuyPaymentInfoCubit>().state;
  final converterState = viewContext.read<BuyConverterCubit>().state;
  final supportVisible = find.text(S.current.paymentInformationFailed).evaluate().isNotEmpty;
  final spinnerVisible = find.byType(CupertinoActivityIndicator).evaluate().isNotEmpty;
  final actionRequired = find.byType(PaymentActionRequired).evaluate().isNotEmpty;
  return 'amountField="$amountText" '
      'converter(fiat=${converterState.fiatText}, shares=${converterState.sharesText}, '
      'loading=${converterState.loading}, currency=${converterState.currency.code}) '
      'paymentInfo=${_describePayment(paymentState)} '
      'supportText=$supportVisible spinner=$spinnerVisible '
      'PaymentActionRequired=$actionRequired';
}

String _describePayment(BuyPaymentInfoState state) {
  if (state is BuyPaymentInfoSuccess) {
    return 'Success(amount=${state.buyPaymentInfo.amount}, '
        'isValid=${state.buyPaymentInfo.isValid})';
  }
  if (state is BuyPaymentInfoMinAmountNotMetFailure) {
    return 'MinAmountNotMet(minAmount=${state.minAmount})';
  }
  if (state is BuyPaymentInfoFailure) {
    return 'Failure(${state.error})';
  }
  if (state is BuyPaymentInfoLoading) return 'Loading';
  if (state is BuyPaymentInfoInitial) return 'Initial';
  return state.runtimeType.toString();
}
