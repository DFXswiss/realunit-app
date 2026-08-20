import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/models/transaction.dart';
import 'package:realunit_wallet/packages/repository/transaction_repository.dart';
import 'package:realunit_wallet/packages/utils/default_assets.dart';
import 'package:realunit_wallet/screens/transaction_history/cubits/filter/transaction_history_filter_cubit.dart';

class _MockTransactionRepository extends Mock implements TransactionRepository {}

const _address = '0x0000000000000000000000000000000000000001';

Transaction _tx(DateTime ts) => Transaction(
      height: 1,
      txId: 'tx-${ts.millisecondsSinceEpoch}',
      chainId: realUnitAsset.chainId,
      senderAddress: _address,
      receiverAddress: _address,
      amount: BigInt.one,
      asset: realUnitAsset,
      type: TransactionTypes.tokenTransfer,
      note: '',
      data: null,
      timestamp: ts,
    );

void main() {
  late _MockTransactionRepository repo;
  late StreamController<List<Transaction>> stream;

  setUp(() {
    repo = _MockTransactionRepository();
    stream = StreamController<List<Transaction>>();
    when(() => repo.watchTransactionsOfAssets(any(), any()))
        .thenAnswer((_) => stream.stream);
  });

  tearDown(() async {
    await stream.close();
  });

  TransactionHistoryFilterCubit build() => TransactionHistoryFilterCubit(
        repo,
        asset: realUnitAsset,
        walletAddress: _address,
      );

  group('$TransactionHistoryFilterCubit', () {
    test('subscribes to the repository stream for the configured asset + address on init', () {
      build();

      verify(() => repo.watchTransactionsOfAssets([realUnitAsset], _address)).called(1);
    });

    test('initial state has a 1-year-back default startDate', () {
      final cubit = build();
      final now = DateTime.now();

      // The 365-day window should put startDate roughly one year before now.
      expect(
        now.difference(cubit.state.startDate!).inDays,
        inInclusiveRange(364, 366),
      );
    });

    blocTest<TransactionHistoryFilterCubit, TransactionHistoryFilterState>(
      'stream pushes populate both `all` and `filtered`',
      build: build,
      act: (_) async {
        // Keep timestamps inside the default 1-year-back window so the
        // initial filter does not silently drop them.
        final now = DateTime.now();
        stream.add([
          _tx(now.subtract(const Duration(days: 30))),
          _tx(now.subtract(const Duration(days: 60))),
        ]);
        await Future<void>.delayed(Duration.zero);
      },
      verify: (cubit) {
        expect(cubit.state.all, hasLength(2));
        expect(cubit.state.filtered, hasLength(2));
      },
    );

    blocTest<TransactionHistoryFilterCubit, TransactionHistoryFilterState>(
      'changeFilter narrows `filtered` to the selected window without touching `all`',
      build: build,
      act: (cubit) async {
        stream.add([
          _tx(DateTime(2026, 1, 1)),
          _tx(DateTime(2026, 3, 1)),
          _tx(DateTime(2026, 6, 1)),
        ]);
        await Future<void>.delayed(Duration.zero);

        cubit.changeFilter(
          startDate: DateTime(2026, 2, 1),
          endDate: DateTime(2026, 4, 1),
        );
      },
      verify: (cubit) {
        expect(cubit.state.all, hasLength(3));
        expect(cubit.state.filtered, hasLength(1));
        expect(cubit.state.filtered.single.timestamp, DateTime(2026, 3, 1));
      },
    );

    blocTest<TransactionHistoryFilterCubit, TransactionHistoryFilterState>(
      'changeFilter includes the boundary days',
      build: build,
      act: (cubit) async {
        stream.add([
          _tx(DateTime(2026, 2, 1)),
          _tx(DateTime(2026, 4, 1)),
        ]);
        await Future<void>.delayed(Duration.zero);

        cubit.changeFilter(
          startDate: DateTime(2026, 2, 1),
          endDate: DateTime(2026, 4, 1),
        );
      },
      verify: (cubit) {
        // Both endpoints are inclusive.
        expect(cubit.state.filtered, hasLength(2));
      },
    );

    blocTest<TransactionHistoryFilterCubit, TransactionHistoryFilterState>(
      'changeFilter keeps transactions timestamped later on the selected end day '
      '(issue #779 regression)',
      build: build,
      act: (cubit) async {
        stream.add([
          _tx(DateTime(2026, 4, 1)),
          _tx(DateTime(2026, 4, 1, 14)),
          _tx(DateTime(2026, 4, 1, 23, 59, 59)),
        ]);
        await Future<void>.delayed(Duration.zero);

        cubit.changeFilter(
          startDate: DateTime(2026, 2, 1),
          endDate: DateTime(2026, 4, 1),
        );
      },
      verify: (cubit) {
        // The end bound arrives as local midnight; the whole selected day belongs to it.
        // Before the fix only the 00:00 transaction survived.
        expect(cubit.state.filtered, hasLength(3));
      },
    );

    blocTest<TransactionHistoryFilterCubit, TransactionHistoryFilterState>(
      'changeFilter still excludes the day after the selected end date',
      build: build,
      act: (cubit) async {
        stream.add([
          _tx(DateTime(2026, 4, 1, 23, 59, 59)),
          _tx(DateTime(2026, 4, 2)),
        ]);
        await Future<void>.delayed(Duration.zero);

        cubit.changeFilter(
          startDate: DateTime(2026, 2, 1),
          endDate: DateTime(2026, 4, 1),
        );
      },
      verify: (cubit) {
        expect(cubit.state.filtered, hasLength(1));
        expect(cubit.state.filtered.single.timestamp, DateTime(2026, 4, 1, 23, 59, 59));
      },
    );

    blocTest<TransactionHistoryFilterCubit, TransactionHistoryFilterState>(
      'changeFilter includes a UTC-flagged timestamp falling on the local end day',
      build: build,
      act: (cubit) async {
        // Same instant as 14:00 local — the UTC flag must not shift it out of the window.
        stream.add([_tx(DateTime(2026, 4, 1, 14).toUtc())]);
        await Future<void>.delayed(Duration.zero);

        cubit.changeFilter(
          startDate: DateTime(2026, 2, 1),
          endDate: DateTime(2026, 4, 1),
        );
      },
      verify: (cubit) {
        expect(cubit.state.filtered, hasLength(1));
      },
    );

    blocTest<TransactionHistoryFilterCubit, TransactionHistoryFilterState>(
      'changeFilter keeps the previously-set bound when only the other changes '
      '(issue #657 P3 regression)',
      build: build,
      act: (cubit) async {
        stream.add([
          _tx(DateTime(2026, 1, 1)),
          _tx(DateTime(2026, 3, 1)),
          _tx(DateTime(2026, 5, 1)),
        ]);
        await Future<void>.delayed(Duration.zero);

        // Two pickers, two separate partial updates — start first, then end.
        cubit.changeFilter(startDate: DateTime(2026, 2, 1));
        cubit.changeFilter(endDate: DateTime(2026, 4, 1));
      },
      verify: (cubit) {
        // Both bounds must survive: the window [Feb 1, Apr 1] leaves only Mar 1.
        // Before the fix the second call dropped the start bound, leaking Jan 1.
        expect(cubit.state.startDate, DateTime(2026, 2, 1));
        expect(cubit.state.endDate, DateTime(2026, 4, 1));
        expect(cubit.state.filtered, hasLength(1));
        expect(cubit.state.filtered.single.timestamp, DateTime(2026, 3, 1));
      },
    );

    test('close cancels the stream subscription (no emit after close)', () async {
      final cubit = build();
      await cubit.close();

      // Emit on the source stream after close — must not propagate.
      stream.add([_tx(DateTime.now())]);
      await Future<void>.delayed(Duration.zero);

      // If the subscription were still active, the cubit would throw
      // StateError on emit.
    });

    blocTest<TransactionHistoryFilterCubit, TransactionHistoryFilterState>(
      'a subsequent stream update re-applies the current filter',
      build: build,
      act: (cubit) async {
        cubit.changeFilter(
          startDate: DateTime(2026, 2, 1),
          endDate: DateTime(2026, 4, 1),
        );
        stream.add([
          _tx(DateTime(2026, 1, 1)),
          _tx(DateTime(2026, 3, 1)),
        ]);
        await Future<void>.delayed(Duration.zero);
      },
      verify: (cubit) {
        expect(cubit.state.all, hasLength(2));
        expect(cubit.state.filtered, hasLength(1));
        expect(cubit.state.filtered.single.timestamp, DateTime(2026, 3, 1));
      },
    );
  });
}
