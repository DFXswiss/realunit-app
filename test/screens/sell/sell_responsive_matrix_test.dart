// Responsive matrix gate for SellView primary CTA.
//
// Proves the sell button stays fully tappable across the full device ×
// text-scale matrix (see test/helper/responsive_matrix.dart).
// Regression lock for the IntrinsicHeight + Spacer collapse that pushed the
// CTA below the viewport on first frame without a RenderFlex overflow.
//
// Also proves the sticky actions stay above the soft keyboard via Scaffold's
// default resizeToAvoidBottomInset (viewInsets shrink the bounded height).
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/models/balance.dart';
import 'package:realunit_wallet/packages/config/api_config.dart';
import 'package:realunit_wallet/packages/repository/balance_repository.dart';
import 'package:realunit_wallet/packages/repository/supported_fiat_repository.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_bank_account_service.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_brokerbot_service.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_price_service.dart';
import 'package:realunit_wallet/packages/service/dfx/models/bank_account/bank_account.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_sell_payment_info_service.dart';
import 'package:realunit_wallet/packages/utils/default_assets.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';
import 'package:realunit_wallet/screens/sell/cubits/sell_balance/sell_balance_cubit.dart';
import 'package:realunit_wallet/screens/sell/cubits/sell_converter/sell_converter_cubit.dart';
import 'package:realunit_wallet/screens/sell/cubits/sell_payment_info/sell_payment_info_cubit.dart';
import 'package:realunit_wallet/screens/sell/cubits/sell_selected_bank_account/sell_selected_bank_account_cubit.dart';
import 'package:realunit_wallet/screens/sell/sell_page.dart';
import 'package:realunit_wallet/styles/currency.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helper/helper.dart';

class MockSellConverterCubit extends MockCubit<SellConverterState> implements SellConverterCubit {}

class MockSellPaymentInfoCubit extends MockCubit<SellPaymentInfoState>
    implements SellPaymentInfoCubit {}

class MockSellSelectedBankAccountCubit extends MockCubit<BankAccount?>
    implements SellSelectedBankAccountCubit {}

class MockSellBalanceCubit extends MockCubit<Balance> implements SellBalanceCubit {}

class MockDfxBrokerbotService extends Mock implements DfxBrokerbotService {}

class MockDfxBankAccountService extends Mock implements DfxBankAccountService {}

class MockDfxPriceService extends Mock implements DFXPriceService {}

class MockRealUnitSellPaymentInfoService extends Mock implements RealUnitSellPaymentInfoService {}

class MockBalanceRepository extends Mock implements BalanceRepository {}

class MockSupportedFiatRepository extends Mock implements SupportedFiatRepository {}

class MockApiConfig extends Mock implements ApiConfig {}

class MockAppStore extends Mock implements AppStore {}

class MockWallet extends Mock implements SoftwareWallet {}

void main() {
  late SellConverterCubit converterCubit;
  late SellPaymentInfoCubit sellPaymentInfoCubit;
  late SellSelectedBankAccountCubit sellSelectedBankAccountCubit;
  late SellBalanceCubit sellBalanceCubit;

  setUpAll(() {
    registerFallbackValue(
      Balance(
        chainId: 1,
        contractAddress: '0x0',
        walletAddress: '0x0',
        balance: BigInt.zero,
        asset: realUnitAsset,
      ),
    );
  });

  Future<void> setupDependencyInjection() async {
    SharedPreferences.setMockInitialValues({});
    final getIt = GetIt.instance;
    final apiConfig = MockApiConfig();
    when(() => apiConfig.asset).thenReturn(realUnitAsset);
    final appStore = MockAppStore();
    when(() => appStore.apiConfig).thenReturn(apiConfig);
    when(() => appStore.wallet).thenReturn(MockWallet());
    when(() => appStore.primaryAddress).thenReturn('0x0000000000000000000000000000000000000000');
    getIt.registerSingleton<AppStore>(appStore);
    getIt.registerSingleton<DfxBrokerbotService>(MockDfxBrokerbotService());
    getIt.registerSingleton<DfxBankAccountService>(MockDfxBankAccountService());
    getIt.registerSingleton<DFXPriceService>(MockDfxPriceService());
    getIt.registerSingleton<RealUnitSellPaymentInfoService>(MockRealUnitSellPaymentInfoService());
    getIt.registerSingleton<SharedPreferences>(await SharedPreferences.getInstance());
    final balanceRepository = MockBalanceRepository();
    when(() => balanceRepository.watchBalance(any())).thenAnswer(
      (_) => Stream.value(
        Balance(
          chainId: 1,
          contractAddress: '0x0',
          walletAddress: '0x0',
          balance: BigInt.zero,
          asset: realUnitAsset,
        ),
      ),
    );
    when(() => balanceRepository.saveBalance(any())).thenAnswer((_) async {});
    getIt.registerSingleton<BalanceRepository>(balanceRepository);

    final fiatRepo = MockSupportedFiatRepository();
    when(() => fiatRepo.getSellable()).thenAnswer((_) async => const [Currency.chf]);
    when(() => fiatRepo.getBuyable()).thenAnswer((_) async => const [Currency.chf, Currency.eur]);
    when(() => fiatRepo.getAll()).thenAnswer((_) async => const [Currency.chf, Currency.eur]);
    getIt.registerSingleton<SupportedFiatRepository>(fiatRepo);
  }

  setUpAll(() async => await setupDependencyInjection());

  tearDownAll(() async => await GetIt.instance.reset());

  setUp(() {
    converterCubit = MockSellConverterCubit();
    sellPaymentInfoCubit = MockSellPaymentInfoCubit();
    sellSelectedBankAccountCubit = MockSellSelectedBankAccountCubit();
    sellBalanceCubit = MockSellBalanceCubit();

    when(() => converterCubit.state).thenReturn(const SellConverterState());
    when(() => sellPaymentInfoCubit.state).thenReturn(const SellPaymentInfoInitial());
    when(
      () => sellPaymentInfoCubit.getPaymentInfo(
        amount: any(named: 'amount'),
        iban: any(named: 'iban'),
        currency: Currency.chf,
      ),
    ).thenAnswer((_) => Future.value());
    when(() => sellSelectedBankAccountCubit.state).thenReturn(null);
    when(() => sellBalanceCubit.state).thenReturn(
      Balance(
        chainId: 1,
        contractAddress: '0x0',
        walletAddress: '0x0',
        balance: BigInt.zero,
        asset: realUnitAsset,
      ),
    );
  });

  /// Primary CTA state matching "enabled button when amount and bankaccount
  /// are given". SellButton takes amount from the view controller, which is
  /// synced only on loading true→false (see SellView listener) — so we emit
  /// that transition with long amount strings as worst-case content. Tap then
  /// only calls the stubbed getPaymentInfo (no router).
  void stubPrimaryCtaState() {
    whenListen(
      converterCubit,
      Stream.fromIterable([
        const SellConverterState(
          fiatText: '999999999',
          sharesText: '1234567.89',
          loading: true,
        ),
        const SellConverterState(
          fiatText: '999999999',
          sharesText: '1234567.89',
          loading: false,
        ),
      ]),
      initialState: const SellConverterState(
        fiatText: '999999999',
        sharesText: '1234567.89',
        loading: true,
      ),
    );
    when(() => converterCubit.state).thenReturn(
      const SellConverterState(fiatText: '999999999', sharesText: '1234567.89'),
    );
    when(() => sellSelectedBankAccountCubit.state).thenReturn(
      const BankAccount(id: 1, iban: 'CH12 3456 7890 1234 5678 9'),
    );
    when(() => sellPaymentInfoCubit.state).thenReturn(const SellPaymentInfoInitial());
  }

  Widget buildSubject() {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: converterCubit),
        BlocProvider.value(value: sellPaymentInfoCubit),
        BlocProvider.value(value: sellSelectedBankAccountCubit),
        BlocProvider.value(value: sellBalanceCubit),
      ],
      child: const SellView(),
    );
  }

  Future<void> pumpScreen(
    WidgetTester tester,
    MatrixCell cell,
    Widget child, {
    MediaQueryData? mediaQueryOverride,
  }) async {
    final mediaQuery = mediaQueryOverride ?? cell.mediaQuery;
    await tester.binding.setSurfaceSize(mediaQuery.size);
    addTearDown(() async => await tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MediaQuery(
        data: mediaQuery,
        child: MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: const [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: S.delegate.supportedLocales,
          home: child,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    // Settle the loading true→false emission so amount controllers sync.
    await tester.pumpAndSettle();
  }

  group('SellView responsive matrix (full device × textScale)', () {
    for (final cell in kFullResponsiveMatrix) {
      testWidgets(cell.id, (tester) async {
        await withTargetPlatform(cell.device.platform, () async {
          stubPrimaryCtaState();

          await expectNoLayoutOverflow(
            tester,
            () async {
              await pumpScreen(tester, cell, buildSubject());
            },
            reason: 'overflow on ${cell.label}',
          );

          await expectFullyTappable(
            tester,
            find.byType(AppFilledButton),
            within: find.byType(SellView),
            reason: '${cell.label}: sell CTA not tappable',
          );
        });
      });
    }
  });

  // Keyboard: Scaffold.resizeToAvoidBottomInset (default true) shrinks the
  // body; ScrollableActionsLayout receives the reduced bounded height. Prove
  // the CTA stays fully tappable with a simulated open keyboard.
  testWidgets(
    'KEYBOARD: iPhone SE textScale 1.0 — CTA tappable with viewInsets keyboard',
    (tester) async {
      final cell = MatrixCell(
        kIosDeviceProfiles.firstWhere((d) => d.id == 'iphone_se_3'),
        1.0,
      );
      final keyboardMediaQuery = cell.mediaQuery.copyWith(
        viewInsets: const EdgeInsets.only(bottom: 336),
      );

      await withTargetPlatform(cell.device.platform, () async {
        stubPrimaryCtaState();

        await expectNoLayoutOverflow(
          tester,
          () async {
            await pumpScreen(
              tester,
              cell,
              buildSubject(),
              mediaQueryOverride: keyboardMediaQuery,
            );
          },
          reason: 'overflow with keyboard on ${cell.label}',
        );

        await expectFullyTappable(
          tester,
          find.byType(AppFilledButton),
          within: find.byType(SellView),
          reason: 'sell CTA not tappable above the keyboard (viewInsets.bottom=336)',
        );
      });
    },
  );
}
