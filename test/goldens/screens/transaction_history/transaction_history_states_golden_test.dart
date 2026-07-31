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
import 'package:realunit_wallet/screens/transaction_history/cubits/multi_receipt/transaction_history_multi_receipt_cubit.dart';
import 'package:realunit_wallet/screens/transaction_history/cubits/receipt/transaction_history_receipt_cubit.dart';
import 'package:realunit_wallet/screens/transaction_history/transaction_history_page.dart';
import 'package:realunit_wallet/screens/transaction_history/widgets/transaction_history_download_button.dart';
import 'package:realunit_wallet/screens/transaction_history/widgets/transaction_history_row.dart';
import 'package:realunit_wallet/widgets/date_picker_field.dart';

import '../../../helper/helper.dart';

// `transaction_history_page_default` and `..._with_transactions` live in
// `transaction_history_golden_test.dart` — both mock the filter cubit with an
// empty `filtered` list, so they render the same empty page (the `_with_...`
// baseline never actually shows a row). This file adds the surfaces that base
// file leaves uncovered: a populated list, the per-row receipt spinner, the
// multi-receipt spinner, the receipt-failure SnackBar and the date picker.
//
// Determinism note — dates: `TransactionHistoryRow` formats via
// `DateFormat('MMM dd, yyyy | H:mm').format(transaction.timestamp.toLocal())`
// (`transaction_history_row.dart:112`). The fixed UTC instants are rendered in
// the runner's local time, so these baselines are timezone-dependent — they are
// generated and validated on the same Europe/Zurich self-hosted runner (like
// the chat-bubble goldens). `TransactionHistoryView` itself reads `clock.now()`
// for the date-picker bounds (`transaction_history_page.dart:36`), so its
// builders are pinned with `withClock`, matching the base file.

class _MockTransactionHistoryFilterCubit
    extends MockCubit<TransactionHistoryFilterState>
    implements TransactionHistoryFilterCubit {}

class _MockTransactionHistoryReceiptCubit
    extends MockCubit<TransactionHistoryReceiptState>
    implements TransactionHistoryReceiptCubit {}

class _MockTransactionHistoryMultiReceiptCubit
    extends MockCubit<TransactionHistoryMultiReceiptState>
    implements TransactionHistoryMultiReceiptCubit {}

class _MockTransactionRepository extends Mock implements TransactionRepository {}

class _MockRealUnitPdfService extends Mock implements RealUnitPdfService {}

class _MockApiConfig extends Mock implements ApiConfig {}

void main() {
  const walletAddress = '0xcabd3f4b10a7089986e708d19140bfc98e5880c0';
  const counterparty = '0x1234567890abcdef1234567890abcdef12345678';

  late MockSettingsBloc settingsBloc;
  final transactionRepository = _MockTransactionRepository();

  // decimals of realUnitAsset is 0 → amounts are plain share counts.
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

  final transactions = <Transaction>[
    buy('0xtx1', 50, DateTime.utc(2026, 5, 20, 10, 30)),
    sell('0xtx2', 20, DateTime.utc(2026, 5, 18, 14)),
    buy('0xtx3', 100, DateTime.utc(2026, 5, 15, 9, 15)),
  ];

  // `TransactionHistoryView` field-initializes its date models from
  // `clock.now()` when constructed inside the alchemist builder; pin it so the
  // date-picker fields (and, for the picker overlay, `showDatePicker`) render
  // deterministically. Same fixed instant as the base file.
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

  // ---- A) TransactionHistoryView: populated list + date picker ----
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
      'populated transaction list',
      fileName: 'transaction_history_page_list',
      constraints: phoneConstraints,
      builder: () {
        when(() => filterCubit.state).thenReturn(
          TransactionHistoryFilterState(all: transactions, filtered: transactions),
        );
        return withClock(pinnedClock, () => wrapForGolden(buildSubject()));
      },
    );

    // Tapping a DatePickerField opens the platform date picker. Headless the
    // `DeviceInfo.instance.isIOS` guard (`date_picker.dart:13`) is false, so the
    // deterministic Material `showDatePicker` dialog renders — pinned to the
    // start field's initial date (23 May 2025) via the fixed clock.
    goldenTest(
      'date picker overlay (Material dialog)',
      fileName: 'transaction_history_page_date_picker',
      constraints: phoneConstraints,
      pumpBeforeTest: (tester) => withClock(pinnedClock, () async {
        await tester.pumpAndSettle();
        await tester.tap(find.byType(DatePickerField).first);
        await tester.pumpAndSettle();
      }),
      builder: () => withClock(pinnedClock, () => wrapForGolden(buildSubject())),
    );
  });

  // ---- B) TransactionHistoryRowView: per-row receipt spinner + failure ----
  group('$TransactionHistoryRowView', () {
    late _MockTransactionHistoryReceiptCubit receiptCubit;

    setUp(() {
      receiptCubit = _MockTransactionHistoryReceiptCubit();
      when(() => receiptCubit.state)
          .thenReturn(const TransactionHistoryReceiptInitial());
    });

    Widget rowSubject() => wrapForGolden(
          Scaffold(
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
              child: MultiBlocProvider(
                providers: [
                  BlocProvider<SettingsBloc>.value(value: settingsBloc),
                  BlocProvider<TransactionHistoryReceiptCubit>.value(value: receiptCubit),
                ],
                child: TransactionHistoryRowView(
                  transaction: transactions.first,
                  isOutbound: false,
                ),
              ),
            ),
          ),
        );

    goldenTest(
      'receipt generating — 12px spinner replaces the download icon',
      fileName: 'transaction_history_row_receipt_loading',
      // The 12px CircularProgressIndicator never settles; freeze the first frame.
      pumpBeforeTest: pumpOnce,
      constraints: phoneConstraints,
      builder: () {
        when(() => receiptCubit.state)
            .thenReturn(const TransactionHistoryReceiptLoading());
        return rowSubject();
      },
    );

    // Emitting a failure drives the BlocConsumer listener
    // (`transaction_history_row.dart:52-59`) to show the red error SnackBar.
    goldenTest(
      'receipt failure SnackBar (red)',
      fileName: 'transaction_history_row_receipt_failure',
      constraints: phoneConstraints,
      pumpBeforeTest: (tester) async {
        await tester.pump(); // deliver the whenListen emission to the listener
        await tester.pumpAndSettle(); // run the SnackBar entrance to completion
      },
      builder: () {
        whenListen(
          receiptCubit,
          Stream<TransactionHistoryReceiptState>.value(
            const TransactionHistoryReceiptFailure('Beleg konnte nicht erstellt werden.'),
          ),
          initialState: const TransactionHistoryReceiptInitial(),
        );
        return rowSubject();
      },
    );
  });

  // ---- C) TransactionHistoryDownloadButtonView: multi-receipt spinner ----
  group('$TransactionHistoryDownloadButtonView', () {
    late _MockTransactionHistoryMultiReceiptCubit multiReceiptCubit;

    setUp(() {
      multiReceiptCubit = _MockTransactionHistoryMultiReceiptCubit();
      when(() => multiReceiptCubit.state)
          .thenReturn(const TransactionHistoryMultiReceiptInitial());
    });

    goldenTest(
      'multi-receipt generating — 44x44 CircularProgressIndicator',
      fileName: 'transaction_history_multi_receipt_loading',
      // The CircularProgressIndicator never settles; freeze the first frame.
      pumpBeforeTest: pumpOnce,
      constraints: phoneConstraints,
      builder: () {
        when(() => multiReceiptCubit.state)
            .thenReturn(const TransactionHistoryMultiReceiptLoading());
        return wrapForGolden(
          Scaffold(
            body: Center(
              child: BlocProvider<TransactionHistoryMultiReceiptCubit>.value(
                value: multiReceiptCubit,
                child: TransactionHistoryDownloadButtonView(transactions: transactions),
              ),
            ),
          ),
        );
      },
    );
  });
}
