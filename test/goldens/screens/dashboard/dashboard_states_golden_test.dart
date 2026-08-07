import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/models/balance.dart';
import 'package:realunit_wallet/models/portfolio_value_point.dart';
import 'package:realunit_wallet/models/price_point.dart';
import 'package:realunit_wallet/models/transaction.dart';
import 'package:realunit_wallet/packages/config/api_config.dart';
import 'package:realunit_wallet/packages/repository/transaction_repository.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/models/transactions/dto/transactions_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_pdf_service.dart';
import 'package:realunit_wallet/packages/utils/default_assets.dart';
import 'package:realunit_wallet/screens/dashboard/bloc/balance_cubit.dart';
import 'package:realunit_wallet/screens/dashboard/bloc/dashboard_bloc.dart';
import 'package:realunit_wallet/screens/dashboard/bloc/pending_transactions_cubit.dart';
import 'package:realunit_wallet/screens/dashboard/dashboard_page.dart';
import 'package:realunit_wallet/screens/settings/bloc/settings_bloc.dart';
import 'package:realunit_wallet/styles/currency.dart';

import '../../../helper/helper.dart';

// `dashboard_empty` (zero balance) and `dashboard_with_balance` live in
// `dashboard_golden_test.dart`. This file adds the state surfaces the base
// file leaves uncovered: the loaded price chart, the portfolio-history header
// variant, the pending-transactions section, the recent-transactions section,
// and the hide-amounts masking.
//
// Determinism note — charts: `PriceChartCubit` / `PortfolioChartCubit`
// (`price_chart_cubit.dart:45`, `portfolio_chart_cubit.dart:51`) call
// `DateTime.now()`, but the value is only consumed by the non-`all` period
// branches of their `switch`. The default `selectedPeriod` is `TimePeriod.all`
// (`price_chart_cubit.dart:12`), whose `minX`/`maxX` come purely from the first
// / last fixture `PricePoint.time`. No period selector is tapped, so `now()`
// never reaches the rendered spots — the curve, gradient and axis labels are a
// pure function of the fixed fixtures below.

class _MockDashboardBloc extends MockBloc<DashboardEvent, DashboardState>
    implements DashboardBloc {}

class _MockBalanceCubit extends MockCubit<Balance> implements BalanceCubit {}

class _MockPendingTransactionsCubit extends MockCubit<List<TransactionDto>>
    implements PendingTransactionsCubit {}

class _MockTransactionRepository extends Mock implements TransactionRepository {}

class _MockRealUnitPdfService extends Mock implements RealUnitPdfService {}

class _MockApiConfig extends Mock implements ApiConfig {}

void main() {
  const walletAddress = '0xcabd3f4b10a7089986e708d19140bfc98e5880c0';
  const counterparty = '0x1234567890abcdef1234567890abcdef12345678';

  late _MockDashboardBloc dashboardBloc;
  late _MockBalanceCubit balanceCubit;
  late _MockPendingTransactionsCubit pendingTxCubit;
  late MockSettingsBloc settingsBloc;
  final transactionRepository = _MockTransactionRepository();

  // Price in rappen (2 implied decimals): 153 -> "1.53" CHF.
  final price = BigInt.from(153);

  // Fixed, ascending monthly price points. UTC instants keep the millisecond
  // X-values host-independent; the chart draws a stable curve from them.
  final priceChart = <PricePoint>[
    PricePoint(asset: realUnitAsset, price: BigInt.from(148), time: DateTime.utc(2025, 11)),
    PricePoint(asset: realUnitAsset, price: BigInt.from(150), time: DateTime.utc(2025, 12)),
    PricePoint(asset: realUnitAsset, price: BigInt.from(149), time: DateTime.utc(2026, 1)),
    PricePoint(asset: realUnitAsset, price: BigInt.from(152), time: DateTime.utc(2026, 2)),
    PricePoint(asset: realUnitAsset, price: BigInt.from(151), time: DateTime.utc(2026, 3)),
    PricePoint(asset: realUnitAsset, price: BigInt.from(155), time: DateTime.utc(2026, 4)),
    PricePoint(asset: realUnitAsset, price: BigInt.from(153), time: DateTime.utc(2026, 5)),
  ];

  // Portfolio value points (value in rappen, balance in REALU shares).
  final portfolioHistory = <PortfolioValuePoint>[
    PortfolioValuePoint(value: BigInt.from(14800), balance: BigInt.from(100), time: DateTime.utc(2025, 11)),
    PortfolioValuePoint(value: BigInt.from(15000), balance: BigInt.from(100), time: DateTime.utc(2025, 12)),
    PortfolioValuePoint(value: BigInt.from(14900), balance: BigInt.from(100), time: DateTime.utc(2026, 1)),
    PortfolioValuePoint(value: BigInt.from(15200), balance: BigInt.from(100), time: DateTime.utc(2026, 2)),
    PortfolioValuePoint(value: BigInt.from(15100), balance: BigInt.from(100), time: DateTime.utc(2026, 3)),
    PortfolioValuePoint(value: BigInt.from(15500), balance: BigInt.from(100), time: DateTime.utc(2026, 4)),
    PortfolioValuePoint(value: BigInt.from(15300), balance: BigInt.from(100), time: DateTime.utc(2026, 5)),
  ];

  Balance zeroBalance() => Balance(
        chainId: realUnitAsset.chainId,
        contractAddress: realUnitAsset.address,
        walletAddress: walletAddress,
        balance: BigInt.zero,
        asset: realUnitAsset,
      );

  Balance heldBalance() => Balance(
        chainId: realUnitAsset.chainId,
        contractAddress: realUnitAsset.address,
        walletAddress: walletAddress,
        balance: BigInt.from(100),
        asset: realUnitAsset,
      );

  DashboardState dashboardState({
    List<PortfolioValuePoint> history = const [],
  }) =>
      DashboardState(
        price: price,
        priceChart: priceChart,
        portfolioHistory: history,
        currency: Currency.chf,
      );

  // decimals of realUnitAsset is 0, so amounts are plain share counts.
  Transaction buy(String txId, int shares, DateTime timestamp) => Transaction(
        height: 200,
        txId: txId,
        chainId: 1,
        senderAddress: counterparty,
        receiverAddress: walletAddress,
        amount: BigInt.from(shares),
        asset: realUnitAsset,
        type: TransactionTypes.tokenTransfer,
        note: null,
        data: null,
        timestamp: timestamp,
      );

  Transaction sell(String txId, int shares, DateTime timestamp) => Transaction(
        height: 199,
        txId: txId,
        chainId: 1,
        senderAddress: walletAddress,
        receiverAddress: counterparty,
        amount: BigInt.from(shares),
        asset: realUnitAsset,
        type: TransactionTypes.tokenTransfer,
        note: null,
        data: null,
        timestamp: timestamp,
      );

  final recentTransactions = <Transaction>[
    buy('0xrecent1', 50, DateTime.utc(2026, 5, 20, 10, 30)),
    sell('0xrecent2', 20, DateTime.utc(2026, 5, 18, 14)),
    buy('0xrecent3', 100, DateTime.utc(2026, 5, 15, 9, 15)),
  ];

  final pendingTransactions = <TransactionDto>[
    TransactionDto(
      id: 1,
      type: TransactionType.buy,
      state: TransactionState.processing,
      inputAmount: 500,
      inputAsset: 'CHF',
      date: DateTime.utc(2026, 5, 21, 8),
    ),
    TransactionDto(
      id: 2,
      type: TransactionType.sell,
      state: TransactionState.waitingForPayment,
      inputAmount: 30,
      inputAsset: 'REALU',
      date: DateTime.utc(2026, 5, 20, 12),
    ),
  ];

  setUpAll(() {
    final getIt = GetIt.instance;
    final apiConfig = _MockApiConfig();
    final appStore = MockAppStore();
    when(() => apiConfig.asset).thenReturn(realUnitAsset);
    when(() => appStore.apiConfig).thenReturn(apiConfig);
    when(() => appStore.primaryAddress).thenReturn(walletAddress);
    getIt.registerSingleton<AppStore>(appStore);
    getIt.registerSingleton<RealUnitPdfService>(_MockRealUnitPdfService());
    getIt.registerSingleton<TransactionRepository>(transactionRepository);
  });

  tearDownAll(() async => GetIt.instance.reset());

  setUp(() {
    dashboardBloc = _MockDashboardBloc();
    balanceCubit = _MockBalanceCubit();
    pendingTxCubit = _MockPendingTransactionsCubit();
    settingsBloc = MockSettingsBloc();

    when(() => dashboardBloc.state).thenReturn(dashboardState());
    when(() => balanceCubit.state).thenReturn(zeroBalance());
    when(() => balanceCubit.asset).thenReturn(realUnitAsset);
    when(() => pendingTxCubit.state).thenReturn(const <TransactionDto>[]);
    when(() => settingsBloc.state).thenReturn(const SettingsState());
    // Default: no recent transactions. Overridden per-builder where needed.
    when(() => transactionRepository.watchTransactionsOfAssets(any(), any(), any()))
        .thenAnswer((_) => const Stream<List<Transaction>>.empty());
  });

  Widget buildSubject() => MultiBlocProvider(
        providers: [
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
          BlocProvider<DashboardBloc>.value(value: dashboardBloc),
          BlocProvider<BalanceCubit>.value(value: balanceCubit),
          BlocProvider<PendingTransactionsCubit>.value(value: pendingTxCubit),
        ],
        child: const DashboardView(),
      );

  group('$DashboardView', () {
    goldenTest(
      'price chart loaded — price text, curve, gradient, axis labels',
      fileName: 'dashboard_price_chart',
      constraints: phoneConstraints,
      builder: () => wrapForGolden(buildSubject()),
    );

    goldenTest(
      'portfolio history header variant',
      fileName: 'dashboard_portfolio_chart',
      constraints: phoneConstraints,
      builder: () {
        when(() => dashboardBloc.state)
            .thenReturn(dashboardState(history: portfolioHistory));
        return wrapForGolden(buildSubject());
      },
    );

    goldenTest(
      'pending transactions section',
      fileName: 'dashboard_pending_transactions',
      constraints: phoneConstraints,
      // The pending rows host a CupertinoActivityIndicator (never settles) and
      // the empty-balance body an illustration SVG. Give the SVG a couple of
      // deterministic frames to decode, then stop before pumpAndSettle would
      // time out on the spinner (same pattern as settings_seed_page_loading).
      pumpBeforeTest: (tester) async {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
      },
      builder: () {
        when(() => pendingTxCubit.state).thenReturn(pendingTransactions);
        return wrapForGolden(buildSubject());
      },
    );

    goldenTest(
      'recent transactions section (held balance)',
      fileName: 'dashboard_recent_transactions',
      constraints: phoneConstraints,
      builder: () {
        when(() => balanceCubit.state).thenReturn(heldBalance());
        when(() => transactionRepository.watchTransactionsOfAssets(any(), any(), any()))
            .thenAnswer((_) => Stream.value(recentTransactions));
        return wrapForGolden(buildSubject());
      },
    );

    goldenTest(
      'hide amounts — masked balance and transaction amounts',
      fileName: 'dashboard_hidden_amounts',
      constraints: phoneConstraints,
      builder: () {
        when(() => settingsBloc.state)
            .thenReturn(const SettingsState(hideAmounts: true));
        when(() => balanceCubit.state).thenReturn(heldBalance());
        when(() => transactionRepository.watchTransactionsOfAssets(any(), any(), any()))
            .thenAnswer((_) => Stream.value(recentTransactions));
        return wrapForGolden(buildSubject());
      },
    );
  });
}
