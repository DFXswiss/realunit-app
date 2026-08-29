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
      when(() => service.fetchPendingTransactions())
          .thenAnswer((_) async => [tx1, tx2]);

      final cubit = PendingTransactionsCubit(service);
      await cubit.stream.firstWhere((s) => s.isNotEmpty);

      expect(cubit.state, [tx1, tx2]);
    });

    test('does not emit (no StateError) if closed before the fetch resolves '
        '(issue #657 P3 #16 regression)', () async {
      final completer = Completer<List<TransactionDto>>();
      when(() => service.fetchPendingTransactions())
          .thenAnswer((_) => completer.future);

      final cubit = PendingTransactionsCubit(service);
      // Close while the constructor-started fetch is still in flight.
      await cubit.close();

      // Resolving now would, without the isClosed guard, emit after close and
      // throw 'Cannot emit new states after calling close'.
      completer.complete([_StubTx()]);
      await Future<void>.delayed(Duration.zero);

      // No exception escaped; the closed cubit kept its last state.
      expect(cubit.isClosed, isTrue);
    });

    test('falls back to an empty list when the service throws', () async {
      when(() => service.fetchPendingTransactions())
          .thenAnswer((_) async => throw Exception('network'));

      final cubit = PendingTransactionsCubit(service);
      // The catch branch emits the same [] the cubit started in, so we
      // just give the microtask queue a tick and then assert state.
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state, isEmpty);
    });
  });
}
