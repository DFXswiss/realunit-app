import 'package:alchemist/alchemist.dart' show precacheImages;
import 'package:bloc_test/bloc_test.dart';
import 'package:clock/clock.dart';
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
import 'package:realunit_wallet/screens/dashboard/widgets/time_period_selection_button.dart';
import 'package:realunit_wallet/screens/settings/bloc/settings_bloc.dart';
import 'package:realunit_wallet/styles/currency.dart';

import '../../../helper/helper.dart';
import 'handbook_persona_fixtures.dart';

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
  const counterparty = '0x00000000000000000000000000000000000000aa';

  late _MockDashboardBloc dashboardBloc;
  late _MockBalanceCubit balanceCubit;
  late _MockPendingTransactionsCubit pendingTxCubit;
  late MockSettingsBloc settingsBloc;
  final transactionRepository = _MockTransactionRepository();

  final price = BigInt.from(153);
  final priceChart = <PricePoint>[
    PricePoint(asset: realUnitAsset, price: BigInt.from(148), time: DateTime.utc(2025, 11)),
    PricePoint(asset: realUnitAsset, price: BigInt.from(153), time: DateTime.utc(2026, 5)),
  ];

  Balance balanceFor(List<PortfolioValuePoint> history) {
    final shares = history.isEmpty ? BigInt.zero : history.last.balance;
    return Balance(
      chainId: realUnitAsset.chainId,
      contractAddress: realUnitAsset.address,
      walletAddress: walletAddress,
      balance: shares,
      asset: realUnitAsset,
    );
  }

  DashboardState dashboardState(List<PortfolioValuePoint> history) => DashboardState(
    price: price,
    priceChart: priceChart,
    portfolioHistory: history,
    currency: Currency.chf,
  );

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
    when(() => pendingTxCubit.state).thenReturn(const <TransactionDto>[]);
    when(() => settingsBloc.state).thenReturn(const SettingsState());
    when(() => balanceCubit.asset).thenReturn(realUnitAsset);
    when(
      () => transactionRepository.watchTransactionsOfAssets(any(), any(), any()),
    ).thenAnswer((_) => const Stream<List<Transaction>>.empty());
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

  /// Dashboard shows the three newest on-chain transfers under Bestand
  /// (`watchTransfersOfAssetsLimit(..., 3)`), newest first. Zero-delta
  /// hold points are not trades.
  List<Transaction> latestDashboardTxs(List<PortfolioValuePoint> history) {
    var prev = BigInt.zero;
    final trades = <Transaction>[];
    for (var i = 0; i < history.length; i++) {
      final point = history[i];
      final delta = point.balance - prev;
      prev = point.balance;
      if (delta == BigInt.zero) continue;
      final inbound = delta > BigInt.zero;
      trades.add(
        Transaction(
          height: 100 + i,
          txId: '0x${i.toRadixString(16).padLeft(8, '0')}',
          chainId: 1,
          senderAddress: inbound ? counterparty : walletAddress,
          receiverAddress: inbound ? walletAddress : counterparty,
          amount: delta.abs(),
          asset: realUnitAsset,
          type: TransactionTypes.tokenTransfer,
          note: null,
          data: null,
          timestamp: point.time,
        ),
      );
    }
    return trades.reversed.take(3).toList();
  }

  void stubHistory(List<PortfolioValuePoint> history) {
    when(() => dashboardBloc.state).thenReturn(dashboardState(history));
    when(() => balanceCubit.state).thenReturn(balanceFor(history));
    when(
      () => transactionRepository.watchTransactionsOfAssets(any(), any(), any()),
    ).thenAnswer((_) => Stream.value(latestDashboardTxs(history)));
  }

  // The portfolio/price chart cubits and the persona fixtures read the wall
  // clock (MAX axis end + `daysAgo` data anchor), which otherwise drifts
  // between the regenerate run and the compare run. Pin it so the render is
  // byte-stable, mirroring the settings_tax_report golden tests.
  final pinnedClock = Clock.fixed(DateTime.utc(2026, 6, 15));
  Widget pinnedSubject(List<PortfolioValuePoint> Function() historyFn) =>
      withClock(pinnedClock, () {
        stubHistory(historyFn());
        return wrapForGolden(buildSubject());
      });
  Future<void> pinnedPump(WidgetTester tester) =>
      withClock(pinnedClock, () => precacheImages(tester));

  group('handbook personas', () {
    goldenTest(
      'K1 Monatskäufer — MAX staircase of twelve equal buys',
      fileName: 'handbook_persona_dca',
      constraints: phoneConstraints,
      pumpBeforeTest: pinnedPump,
      builder: () => pinnedSubject(personaDcaHistory),
    );

    goldenTest(
      'K2 Einmalkauf — MAX lump then small top-ups',
      fileName: 'handbook_persona_lump',
      constraints: phoneConstraints,
      pumpBeforeTest: pinnedPump,
      builder: () => pinnedSubject(personaLumpHistory),
    );

    goldenTest(
      'K3 Verkauf auf 0 — MAX rise then drop to a visible zero line',
      fileName: 'handbook_persona_exit',
      constraints: phoneConstraints,
      pumpBeforeTest: pinnedPump,
      builder: () => pinnedSubject(personaExitHistory),
    );

    goldenTest(
      'K3 Verkauf auf 0 — 1J still shows the sell-down inside the year',
      fileName: 'handbook_persona_exit_1j',
      constraints: phoneConstraints,
      pumpBeforeTest: pinnedPump,
      whilePerforming: (tester) => withClock(pinnedClock, () async {
        await tester.tap(find.widgetWithText(TimePeriodSelectionButton, '1J'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        return null;
      }),
      builder: () => pinnedSubject(personaExitHistory),
    );

    goldenTest(
      'K4 Mix — MAX interleaved buys and partial sells',
      fileName: 'handbook_persona_mix',
      constraints: phoneConstraints,
      pumpBeforeTest: pinnedPump,
      builder: () => pinnedSubject(personaMixHistory),
    );

    goldenTest(
      'K5 Aufstocken — MAX rising buys',
      fileName: 'handbook_persona_scale',
      constraints: phoneConstraints,
      pumpBeforeTest: pinnedPump,
      builder: () => pinnedSubject(personaScaleHistory),
    );
  });
}
