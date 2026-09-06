import 'package:bloc_test/bloc_test.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/models/transaction.dart';
import 'package:realunit_wallet/packages/config/api_config.dart';
import 'package:realunit_wallet/packages/repository/transaction_repository.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_pdf_service.dart';
import 'package:realunit_wallet/packages/utils/default_assets.dart';
import 'package:realunit_wallet/screens/settings/bloc/settings_bloc.dart';
import 'package:realunit_wallet/screens/transaction_history/cubits/filter/transaction_history_filter_cubit.dart';
import 'package:realunit_wallet/screens/transaction_history/transaction_history_page.dart';

import '../../../helper/helper.dart';

// Visual regression for transfer title labels on the history list.
//
// (1) problem: inbound REALU from an external wallet with `category: null`
//     falls back to the direction-based Kauf label.
// (2) fix: API `TransferCategory` drives Kauf / Empfangen / Gesendet / Verkauf
//     so all four titles are visible on one screen.
//
// Same mock/DI/clock pattern as `transaction_history_states_golden_test.dart`.
// Dates are timezone-dependent (rendered via `.toLocal()`); baselines are
// generated on the Europe/Zurich self-hosted runner.

class _MockTransactionHistoryFilterCubit
    extends MockCubit<TransactionHistoryFilterState>
    implements TransactionHistoryFilterCubit {}

class _MockTransactionRepository extends Mock implements TransactionRepository {}

class _MockRealUnitPdfService extends Mock implements RealUnitPdfService {}

class _MockApiConfig extends Mock implements ApiConfig {}

void main() {
  const walletAddress = '0xcabd3f4b10a7089986e708d19140bfc98e5880c0';
  const counterparty = '0x1234567890abcdef1234567890abcdef12345678';

  late MockSettingsBloc settingsBloc;
  final transactionRepository = _MockTransactionRepository();

  // decimals of realUnitAsset is 0 → amounts are plain share counts.
  Transaction row({
    required String txId,
    required int shares,
    required bool inbound,
    TransferCategory? category,
    required DateTime timestamp,
  }) =>
      Transaction(
        height: 200,
        txId: txId,
        chainId: 1,
        senderAddress: inbound ? counterparty : walletAddress,
        receiverAddress: inbound ? walletAddress : counterparty,
        amount: BigInt.from(shares),
        asset: realUnitAsset,
        type: TransactionTypes.tokenTransfer,
        category: category,
        note: null,
        data: null,
        timestamp: timestamp,
      );

  final pinnedClock = Clock.fixed(DateTime.utc(2026, 5, 23));

  setUpAll(() {
    final getIt = GetIt.instance;
    final apiConfig = _MockApiConfig();
    final appStore = MockAppStore();
    when(() => apiConfig.asset).thenReturn(realUnitAsset);
    when(() => appStore.apiConfig).thenReturn(apiConfig);
    when(() => appStore.primaryAddress).thenReturn(walletAddress);
    when(() => transactionRepository.watchTransactionsOfAssets(any(), any()))
        .thenAnswer((_) => const Stream<List<Transaction>>.empty());
    getIt.registerSingleton<AppStore>(appStore);
    getIt.registerSingleton<RealUnitPdfService>(_MockRealUnitPdfService());
    getIt.registerSingleton<TransactionRepository>(transactionRepository);
  });

  tearDownAll(() async => GetIt.instance.reset());

  setUp(() {
    settingsBloc = MockSettingsBloc();
    when(() => settingsBloc.state).thenReturn(const SettingsState());
  });

  group('$TransactionHistoryView', () {
    late _MockTransactionHistoryFilterCubit filterCubit;

    setUp(() {
      filterCubit = _MockTransactionHistoryFilterCubit();
      when(() => filterCubit.state).thenReturn(TransactionHistoryFilterState());
    });

    Widget buildSubject() => MultiBlocProvider(
          providers: [
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
            BlocProvider<TransactionHistoryFilterCubit>.value(value: filterCubit),
          ],
          child: TransactionHistoryView(walletAddress: walletAddress),
        );

    goldenTest(
      'legacy inbound from an external wallet labelled Kauf',
      fileName: 'transaction_history_labels_problem',
      constraints: phoneConstraints,
      builder: () {
        final transactions = [
          row(
            txId: '0xtx-problem-in',
            shares: 10,
            inbound: true,
            category: null,
            timestamp: DateTime.utc(2026, 5, 20, 10, 30),
          ),
          row(
            txId: '0xtx-problem-out',
            shares: 10,
            inbound: false,
            category: null,
            timestamp: DateTime.utc(2026, 5, 18, 14),
          ),
        ];
        when(() => filterCubit.state).thenReturn(
          TransactionHistoryFilterState(all: transactions, filtered: transactions),
        );
        return withClock(pinnedClock, () => wrapForGolden(buildSubject()));
      },
    );

    goldenTest(
      'API category labels purchase, received, sent, sale',
      fileName: 'transaction_history_labels_fix',
      constraints: phoneConstraints,
      builder: () {
        final transactions = [
          row(
            txId: '0xtx-fix-purchase',
            shares: 100,
            inbound: true,
            category: TransferCategory.purchase,
            timestamp: DateTime.utc(2026, 5, 20, 10, 30),
          ),
          row(
            txId: '0xtx-fix-in',
            shares: 10,
            inbound: true,
            category: TransferCategory.transferIn,
            timestamp: DateTime.utc(2026, 5, 19, 12),
          ),
          row(
            txId: '0xtx-fix-out',
            shares: 10,
            inbound: false,
            category: TransferCategory.transferOut,
            timestamp: DateTime.utc(2026, 5, 18, 14),
          ),
          row(
            txId: '0xtx-fix-sale',
            shares: 20,
            inbound: false,
            category: TransferCategory.sale,
            timestamp: DateTime.utc(2026, 5, 15, 9, 15),
          ),
        ];
        when(() => filterCubit.state).thenReturn(
          TransactionHistoryFilterState(all: transactions, filtered: transactions),
        );
        return withClock(pinnedClock, () => wrapForGolden(buildSubject()));
      },
    );
  });
}
