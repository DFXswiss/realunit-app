import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/dfx/models/transactions/dto/transactions_dto.dart';
import 'package:realunit_wallet/packages/service/transaction_history_service.dart';
import 'package:realunit_wallet/screens/dashboard/bloc/pending_transactions_cubit.dart';

class _MockTransactionHistoryService extends Mock implements TransactionHistoryService {}

class _StubTx extends Fake implements TransactionDto {}

void main() {
  late _MockTransactionHistoryService service;

  setUp(() {
    service = _MockTransactionHistoryService();
  });

  group('$PendingTransactionsCubit', () {
    test('initial state is an empty list', () {
      when(() => service.fetchPendingTransactions()).thenAnswer((_) async => []);

      final cubit = PendingTransactionsCubit(service);

      expect(cubit.state, isEmpty);
    });

    test('emits the fetched pending list on construction', () async {
      final tx1 = _StubTx();
      final tx2 = _StubTx();
      when(() => service.fetchPendingTransactions()).thenAnswer((_) async => [tx1, tx2]);

      final cubit = PendingTransactionsCubit(service);
      await cubit.stream.firstWhere((s) => s.isNotEmpty);

      expect(cubit.state, [tx1, tx2]);
    });

    test('falls back to an empty list when the service throws', () async {
      when(
        () => service.fetchPendingTransactions(),
      ).thenAnswer((_) async => throw Exception('network'));

      final cubit = PendingTransactionsCubit(service);
      // The catch branch emits the same [] the cubit started in, so we
      // just give the microtask queue a tick and then assert state.
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state, isEmpty);
    });

    test('reload re-fetches the pending list', () async {
      final first = [
        const TransactionDto(id: 1, type: TransactionType.buy),
      ];
      final second = [
        const TransactionDto(id: 2, type: TransactionType.buy),
      ];
      var call = 0;
      when(() => service.fetchPendingTransactions()).thenAnswer((_) async {
        call++;
        return call == 1 ? first : second;
      });

      final cubit = PendingTransactionsCubit(service);
      await cubit.stream.firstWhere((s) => s.isNotEmpty);
      expect(cubit.state, first);

      await cubit.reload();
      expect(cubit.state, second);
    });

    test('reload that throws keeps a previously loaded non-empty list', () async {
      final buy = const TransactionDto(id: 1, type: TransactionType.buy);
      var call = 0;
      when(() => service.fetchPendingTransactions()).thenAnswer((_) async {
        call++;
        if (call == 1) return [buy];
        throw Exception('network');
      });

      final cubit = PendingTransactionsCubit(service);
      await cubit.stream.firstWhere((s) => s.isNotEmpty);
      expect(cubit.state, [buy]);

      await cubit.reload();
      expect(cubit.state, [buy]);
    });

    test('overlapping reloads: newer fetch wins over stale completion', () async {
      final initial = const TransactionDto(id: 1, type: TransactionType.buy);
      final stale = const TransactionDto(id: 2, type: TransactionType.buy);
      final newer = const TransactionDto(id: 3, type: TransactionType.buy);
      final load2 = Completer<List<TransactionDto>>();
      var call = 0;
      when(() => service.fetchPendingTransactions()).thenAnswer((_) async {
        call++;
        if (call == 1) return [initial];
        if (call == 2) return load2.future;
        return [newer];
      });

      final cubit = PendingTransactionsCubit(service);
      await cubit.stream.firstWhere((s) => s.isNotEmpty);
      expect(cubit.state, [initial]);

      // load 2 (stale) starts first and hangs; load 3 returns immediately.
      final reload2 = cubit.reload();
      final reload3 = cubit.reload();
      await reload3;
      expect(cubit.state, [newer]);

      load2.complete([stale]);
      await reload2;
      // Stale load 2 must not overwrite the newer list.
      expect(cubit.state, [newer]);
    });

    test('drop removes the matching id from the list', () async {
      final buy = const TransactionDto(id: 7, type: TransactionType.buy);
      final sell = const TransactionDto(id: 8, type: TransactionType.sell);
      when(() => service.fetchPendingTransactions()).thenAnswer((_) async => [buy, sell]);

      final cubit = PendingTransactionsCubit(service);
      await cubit.stream.firstWhere((s) => s.length == 2);

      cubit.drop('7');
      expect(cubit.state, [sell]);
    });

    test('drop removes the matching uid when id is null', () async {
      final buy = const TransactionDto(
        uid: 'u-1',
        type: TransactionType.buy,
        state: TransactionState.waitingForPayment,
      );
      when(() => service.fetchPendingTransactions()).thenAnswer((_) async => [buy]);

      final cubit = PendingTransactionsCubit(service);
      await cubit.stream.firstWhere((s) => s.isNotEmpty);

      cubit.drop('u-1');
      expect(cubit.state, isEmpty);
    });

    test('drop with empty id is a no-op', () async {
      final buy = const TransactionDto(id: 7, type: TransactionType.buy);
      when(() => service.fetchPendingTransactions()).thenAnswer((_) async => [buy]);

      final cubit = PendingTransactionsCubit(service);
      await cubit.stream.firstWhere((s) => s.isNotEmpty);

      cubit.drop('');
      expect(cubit.state, [buy]);
    });

    test('reload completes without throwing when cubit is closed during fetch', () async {
      final buyTx = const TransactionDto(
        id: 7,
        type: TransactionType.buy,
        state: TransactionState.waitingForPayment,
      );
      final fetchGate = Completer<List<TransactionDto>>();
      var call = 0;
      when(() => service.fetchPendingTransactions()).thenAnswer((_) async {
        call++;
        if (call == 1) return [buyTx];
        return fetchGate.future;
      });

      final cubit = PendingTransactionsCubit(service);
      await cubit.stream.firstWhere((s) => s.isNotEmpty);
      final reloadFuture = cubit.reload();
      await cubit.close();
      fetchGate.complete([buyTx]);
      await expectLater(reloadFuture, completes);
    });
  });
}
