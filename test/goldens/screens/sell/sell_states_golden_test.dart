import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/models/balance.dart';
import 'package:realunit_wallet/packages/config/api_config.dart';
import 'package:realunit_wallet/packages/repository/balance_repository.dart';
import 'package:realunit_wallet/packages/repository/supported_fiat_repository.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_bank_account_service.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_brokerbot_service.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_price_service.dart';
import 'package:realunit_wallet/packages/service/dfx/models/bank_account/bank_account.dart';
import 'package:realunit_wallet/packages/service/dfx/models/bank_account/dto/bank_account_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/dto/eip7702/eip7702_data_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/dto/real_unit_sell_payment_info_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/sell_payment_info.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_sell_payment_info_service.dart';
import 'package:realunit_wallet/packages/utils/default_assets.dart';
import 'package:realunit_wallet/screens/sell/cubits/sell_balance/sell_balance_cubit.dart';
import 'package:realunit_wallet/screens/sell/cubits/sell_bank_accounts/sell_bank_accounts_cubit.dart';
import 'package:realunit_wallet/screens/sell/cubits/sell_confirm/sell_confirm_cubit.dart';
import 'package:realunit_wallet/screens/sell/cubits/sell_converter/sell_converter_cubit.dart';
import 'package:realunit_wallet/screens/sell/cubits/sell_payment_info/sell_payment_info_cubit.dart';
import 'package:realunit_wallet/screens/sell/cubits/sell_selected_bank_account/sell_selected_bank_account_cubit.dart';
import 'package:realunit_wallet/screens/sell/sell_page.dart';
import 'package:realunit_wallet/screens/sell/widgets/sell_add_bank_account_sheet.dart';
import 'package:realunit_wallet/screens/sell/widgets/sell_confirm_sheet.dart';
import 'package:realunit_wallet/screens/sell/widgets/sell_executed_sheet.dart';
import 'package:realunit_wallet/styles/currency.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helper/helper.dart';

class _MockSellConverterCubit extends MockCubit<SellConverterState>
    implements SellConverterCubit {}

class _MockSellPaymentInfoCubit extends MockCubit<SellPaymentInfoState>
    implements SellPaymentInfoCubit {}

class _MockSellSelectedBankAccountCubit extends MockCubit<BankAccount?>
    implements SellSelectedBankAccountCubit {}

class _MockSellBalanceCubit extends MockCubit<Balance> implements SellBalanceCubit {}

class _MockSellConfirmCubit extends MockCubit<SellConfirmState>
    implements SellConfirmCubit {}

class _MockSellBankAccountsCubit extends MockCubit<SellBankAccountsState>
    implements SellBankAccountsCubit {}

class _MockDfxBrokerbotService extends Mock implements DfxBrokerbotService {}

class _MockDfxBankAccountService extends Mock implements DfxBankAccountService {}

class _MockDfxPriceService extends Mock implements DFXPriceService {}

class _MockRealUnitSellPaymentInfoService extends Mock
    implements RealUnitSellPaymentInfoService {}

class _MockBalanceRepository extends Mock implements BalanceRepository {}

class _MockSupportedFiatRepository extends Mock implements SupportedFiatRepository {}

class _MockApiConfig extends Mock implements ApiConfig {}

// Shared review payload for the confirm/executed sheets. `amount` (100),
// `estimatedAmount` (100.0), `currency` (CHF) and `beneficiary.iban` are the
// only fields the SellConfirmSheet renders.
SellPaymentInfo _paymentInfo() => SellPaymentInfo(
      id: 42,
      eip7702: Eip7702Data.fromJson({
        'relayerAddress': '0xrelay',
        'delegationManagerAddress': '0xmgr',
        'delegatorAddress': '0xdr',
        'userNonce': 7,
        'domain': {
          'name': 'RealUnit',
          'version': '1',
          'chainId': 1,
          'verifyingContract': '0xverify',
        },
        'types': {
          'Delegation': <Map<String, dynamic>>[],
          'Caveat': <Map<String, dynamic>>[],
        },
        'message': {
          'delegate': '0xd',
          'delegator': '0xdr',
          'authority': '0xauth',
          'caveats': <Map<String, dynamic>>[],
          'salt': 0,
        },
        'tokenAddress': '0xtoken',
        'amountWei': '12345',
        'depositAddress': '0xdeposit',
      }),
      amount: 100,
      exchangeRate: 1.0,
      rate: 1.0,
      beneficiary: const BeneficiaryDto(iban: 'CH9300762011623852957'),
      estimatedAmount: 100.0,
      currency: Currency.chf,
      depositAddress: '0xdeposit',
      tokenAddress: '0xtoken',
      chainId: 1,
      ethBalance: 1.0,
      requiredGasEth: 0.001,
    );

void main() {
  Balance zeroBalance() => Balance(
        chainId: 1,
        contractAddress: '0x0',
        walletAddress: '0x0',
        balance: BigInt.zero,
        asset: realUnitAsset,
      );

  Balance withBalance() => Balance(
        chainId: 1,
        contractAddress: '0x0',
        walletAddress: '0x0',
        balance: BigInt.from(1000000000000000000),
        asset: realUnitAsset,
      );

  late _MockDfxBankAccountService bankAccountService;

  setUpAll(() async {
    registerFallbackValue(zeroBalance());

    SharedPreferences.setMockInitialValues({});
    final getIt = GetIt.instance;
    final apiConfig = _MockApiConfig();
    when(() => apiConfig.asset).thenReturn(realUnitAsset);
    final appStore = MockAppStore();
    when(() => appStore.apiConfig).thenReturn(apiConfig);
    when(() => appStore.wallet).thenReturn(MockSoftwareWallet());
    when(() => appStore.primaryAddress).thenReturn(
      '0x0000000000000000000000000000000000000000',
    );
    getIt.registerSingleton<AppStore>(appStore);
    getIt.registerSingleton<DfxBrokerbotService>(_MockDfxBrokerbotService());
    bankAccountService = _MockDfxBankAccountService();
    // The one bank account the picker offers. `id` matches the selected
    // BankAccount below so DropdownButtonFormField resolves its value to a
    // single matching item.
    when(() => bankAccountService.getBankAccounts()).thenAnswer(
      (_) async => const [
        BankAccountDto(
          id: 1,
          iban: 'CH9300762011623852957',
          label: 'Raiffeisen',
          isActive: true,
          isDefault: true,
        ),
      ],
    );
    getIt.registerSingleton<DfxBankAccountService>(bankAccountService);
    getIt.registerSingleton<DFXPriceService>(_MockDfxPriceService());
    getIt.registerSingleton<RealUnitSellPaymentInfoService>(
      _MockRealUnitSellPaymentInfoService(),
    );
    getIt.registerSingleton<SharedPreferences>(await SharedPreferences.getInstance());
    final balanceRepository = _MockBalanceRepository();
    when(() => balanceRepository.watchBalance(any()))
        .thenAnswer((_) => Stream.value(withBalance()));
    when(() => balanceRepository.saveBalance(any())).thenAnswer((_) async {});
    getIt.registerSingleton<BalanceRepository>(balanceRepository);

    final fiatRepo = _MockSupportedFiatRepository();
    when(() => fiatRepo.getSellable()).thenAnswer((_) async => const [Currency.chf]);
    when(() => fiatRepo.getBuyable())
        .thenAnswer((_) async => const [Currency.chf, Currency.eur]);
    when(() => fiatRepo.getAll())
        .thenAnswer((_) async => const [Currency.chf, Currency.eur]);
    getIt.registerSingleton<SupportedFiatRepository>(fiatRepo);
  });

  tearDownAll(() async => GetIt.instance.reset());

  // ---- A) SellView: bank account selected + active Sell button ----
  group('$SellView', () {
    late _MockSellConverterCubit converterCubit;
    late _MockSellPaymentInfoCubit paymentInfoCubit;
    late _MockSellSelectedBankAccountCubit selectedBankAccountCubit;
    late _MockSellBalanceCubit balanceCubit;

    const selectedAccount = BankAccount(
      id: 1,
      iban: 'CH9300762011623852957',
      name: 'Raiffeisen',
      isActive: true,
      isDefault: true,
    );

    setUp(() {
      converterCubit = _MockSellConverterCubit();
      paymentInfoCubit = _MockSellPaymentInfoCubit();
      selectedBankAccountCubit = _MockSellSelectedBankAccountCubit();
      balanceCubit = _MockSellBalanceCubit();

      // A converter that settles from loading:true → loading:false with a
      // filled share amount. SellView's BlocConsumer fires its listener on that
      // exact transition (listenWhen: prev.loading && !next.loading) and syncs
      // the amount controller to '100' — which is what flips the Sell button to
      // its active branch (bankAccount != null && amount != ''). The state
      // getter is intentionally left at the whenListen initialState
      // (loading:true); stubbing it to the final state would erase the
      // transition and the listener would never run.
      whenListen(
        converterCubit,
        Stream<SellConverterState>.value(
          const SellConverterState(sharesText: '100', fiatText: '100'),
        ),
        initialState: const SellConverterState(loading: true),
      );
      when(() => paymentInfoCubit.state).thenReturn(const SellPaymentInfoInitial());
      when(() => selectedBankAccountCubit.state).thenReturn(selectedAccount);
      when(() => balanceCubit.state).thenReturn(withBalance());
    });

    Widget buildSubject() => MultiBlocProvider(
          providers: [
            BlocProvider<SellConverterCubit>.value(value: converterCubit),
            BlocProvider<SellPaymentInfoCubit>.value(value: paymentInfoCubit),
            BlocProvider<SellSelectedBankAccountCubit>.value(value: selectedBankAccountCubit),
            BlocProvider<SellBalanceCubit>.value(value: balanceCubit),
          ],
          child: const SellView(),
        );

    goldenTest(
      'bank account selected — IBAN in field, active sell button',
      fileName: 'sell_bank_account_selected',
      constraints: phoneConstraints,
      builder: () => wrapForGolden(buildSubject()),
    );
  });

  // ---- B) SellConfirmSheet (bottom sheet after payment-info success) ----
  // Rendered in the Scaffold.bottomSheet slot with a mocked SellConfirmCubit,
  // matching the repo's sheet-golden convention
  // (settings_confirm_logout_wallet_sheet_golden_test.dart).
  group('$SellConfirmSheet', () {
    late _MockSellConfirmCubit confirmCubit;

    setUp(() {
      confirmCubit = _MockSellConfirmCubit();
    });

    Widget sheetFor(SellConfirmState state) {
      when(() => confirmCubit.state).thenReturn(state);
      return wrapForGolden(
        Scaffold(
          backgroundColor: Colors.black54,
          bottomSheet: BlocProvider<SellConfirmCubit>.value(
            value: confirmCubit,
            child: SellConfirmSheetView(paymentInfo: _paymentInfo()),
          ),
        ),
      );
    }

    goldenTest(
      'review card, confirm button idle',
      fileName: 'sell_confirm_sheet',
      constraints: phoneConstraints,
      builder: () => sheetFor(SellConfirmInitial()),
    );

    goldenTest(
      'confirm button loading',
      fileName: 'sell_confirm_sheet_loading',
      // The loading button hosts a CupertinoActivityIndicator; freeze it on the
      // first frame instead of letting pumpAndSettle time out.
      pumpBeforeTest: pumpOnce,
      constraints: phoneConstraints,
      builder: () => sheetFor(SellConfirmLoading()),
    );
  });

  // ---- SellExecutedSheet (success sheet after a confirmed sell) ----
  group('$SellExecutedSheet', () {
    goldenTest(
      'check icon, success copy, close button',
      fileName: 'sell_executed_sheet',
      constraints: phoneConstraints,
      builder: () => wrapForGolden(
        const Scaffold(
          backgroundColor: Colors.black54,
          bottomSheet: SellExecutedSheet(),
        ),
      ),
    );
  });

  // ---- SellAddBankAccountSheet (shown when the user has zero accounts) ----
  group('$SellAddBankAccountSheet', () {
    late _MockSellBankAccountsCubit bankAccountsCubit;

    setUp(() {
      bankAccountsCubit = _MockSellBankAccountsCubit();
      when(() => bankAccountsCubit.state).thenReturn(const SellBankAccountsInitial());
    });

    goldenTest(
      'empty form: IBAN + optional label + next',
      fileName: 'sell_add_bank_account_sheet',
      constraints: phoneConstraints,
      builder: () => wrapForGolden(
        Scaffold(
          backgroundColor: Colors.black54,
          bottomSheet: BlocProvider<SellBankAccountsCubit>.value(
            value: bankAccountsCubit,
            child: const SellAddBankAccountSheet(),
          ),
        ),
      ),
    );
  });
}
