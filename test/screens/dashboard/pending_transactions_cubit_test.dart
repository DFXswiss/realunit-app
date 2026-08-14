import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/dfx/models/transactions/dto/transactions_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_buy_payment_info_service.dart';
import 'package:realunit_wallet/packages/service/transaction_history_service.dart';
import 'package:realunit_wallet/screens/dashboard/bloc/pending_transactions_cubit.dart';

class _MockTransactionHistoryService extends Mock implements TransactionHistoryService {}

class _MockBuyPaymentInfoService extends Mock implements RealUnitBuyPaymentInfoService {}

class _StubTx extends Fake implements TransactionDto {}

void main() {
  late _MockTransactionHistoryService service;
  late _MockBuyPaymentInfoService buyService;

  setUp(() {
    service = _MockTransactionHistoryService();
    buyService = _MockBuyPaymentInfoService();
    when(() => buyService.deactivateQuote(any())).thenAnswer((_) async {});
  });

  group('$PendingTransactionsCubit', () {
    test('initial state is an empty list', () {
      when(() => service.fetchPendingTransactions()).thenAnswer((_) async => []);

      final cubit = PendingTransactionsCubit(service, buyService);

      expect(cubit.state, isEmpty);
    });

    test('emits the fetched pending list on construction', () async {
      final tx1 = _StubTx();
      final tx2 = _StubTx();
      when(() => service.fetchPendingTransactions()).thenAnswer((_) async => [tx1, tx2]);

      final cubit = PendingTransactionsCubit(service, buyService);
      await cubit.stream.firstWhere((s) => s.isNotEmpty);

      expect(cubit.state, [tx1, tx2]);
    });

    test('falls back to an empty list when the service throws', () async {
      when(
        () => service.fetchPendingTransactions(),
      ).thenAnswer((_) async => throw Exception('network'));

      final cubit = PendingTransactionsCubit(service, buyService);
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

      final cubit = PendingTransactionsCubit(service, buyService);
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

      final cubit = PendingTransactionsCubit(service, buyService);
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

      final cubit = PendingTransactionsCubit(service, buyService);
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

    test('deactivate on a buy with id calls deactivateQuote then reloads', () async {
      final buyTx = const TransactionDto(
        id: 7,
        type: TransactionType.buy,
        state: TransactionState.waitingForPayment,
      );
      when(() => service.fetchPendingTransactions()).thenAnswer((_) async => [buyTx]);

      final cubit = PendingTransactionsCubit(service, buyService);
      await cubit.stream.firstWhere((s) => s.isNotEmpty);

      await cubit.deactivate(buyTx);

      verify(() => buyService.deactivateQuote('7')).called(1);
      // constructor load + reload after deactivate
      verify(() => service.fetchPendingTransactions()).called(2);
    });

    test('deactivate on a buy with null id uses uid', () async {
      final buyTx = const TransactionDto(
        id: null,
        uid: 'u-1',
        type: TransactionType.buy,
        state: TransactionState.waitingForPayment,
      );
      when(() => service.fetchPendingTransactions()).thenAnswer((_) async => [buyTx]);

      final cubit = PendingTransactionsCubit(service, buyService);
      await cubit.stream.firstWhere((s) => s.isNotEmpty);

      await cubit.deactivate(buyTx);

      verify(() => buyService.deactivateQuote('u-1')).called(1);
    });

    test('deactivate on a sell does not call deactivateQuote', () async {
      final sellTx = const TransactionDto(id: 9, type: TransactionType.sell);
      when(() => service.fetchPendingTransactions()).thenAnswer((_) async => [sellTx]);

      final cubit = PendingTransactionsCubit(service, buyService);
      await cubit.stream.firstWhere((s) => s.isNotEmpty);

      await cubit.deactivate(sellTx);

      verifyNever(() => buyService.deactivateQuote(any()));
      // only the constructor load
      verify(() => service.fetchPendingTransactions()).called(1);
    });

    test('deactivate on a processing buy with numeric id does not call deactivateQuote', () async {
      final buyTx = const TransactionDto(
        id: 7,
        type: TransactionType.buy,
        state: TransactionState.processing,
      );
      when(() => service.fetchPendingTransactions()).thenAnswer((_) async => [buyTx]);
      final cubit = PendingTransactionsCubit(service, buyService);
      await cubit.stream.firstWhere((s) => s.isNotEmpty);
      await cubit.deactivate(buyTx);
      verifyNever(() => buyService.deactivateQuote(any()));
      verify(() => service.fetchPendingTransactions()).called(1);
    });

    test('deactivate on a buy with null id and null uid does not call deactivateQuote', () async {
      final buyTx = const TransactionDto(
        id: null,
        uid: null,
        type: TransactionType.buy,
        state: TransactionState.waitingForPayment,
      );
      when(() => service.fetchPendingTransactions()).thenAnswer((_) async => [buyTx]);

      final cubit = PendingTransactionsCubit(service, buyService);
      await cubit.stream.firstWhere((s) => s.isNotEmpty);

      await cubit.deactivate(buyTx);

      verifyNever(() => buyService.deactivateQuote(any()));
      // only the constructor load
      verify(() => service.fetchPendingTransactions()).called(1);
    });

    test('deactivate on a buy with null id and empty uid does not call deactivateQuote', () async {
      final buyTx = const TransactionDto(
        id: null,
        uid: '',
        type: TransactionType.buy,
        state: TransactionState.waitingForPayment,
      );
      when(() => service.fetchPendingTransactions()).thenAnswer((_) async => [buyTx]);

      final cubit = PendingTransactionsCubit(service, buyService);
      await cubit.stream.firstWhere((s) => s.isNotEmpty);

      await cubit.deactivate(buyTx);

      verifyNever(() => buyService.deactivateQuote(any()));
      // only the constructor load
      verify(() => service.fetchPendingTransactions()).called(1);
    });

    test('when deactivateQuote throws, exception propagates and list is not reloaded', () async {
      final buyTx = const TransactionDto(
        id: 7,
        type: TransactionType.buy,
        state: TransactionState.waitingForPayment,
      );
      when(() => service.fetchPendingTransactions()).thenAnswer((_) async => [buyTx]);
      when(
        () => buyService.deactivateQuote(any()),
      ).thenAnswer((_) async => throw Exception('api down'));

      final cubit = PendingTransactionsCubit(service, buyService);
      await cubit.stream.firstWhere((s) => s.isNotEmpty);

      await expectLater(
        cubit.deactivate(buyTx),
        throwsA(isA<Exception>()),
      );

      // only the constructor load — no reload after failed deactivate
      verify(() => service.fetchPendingTransactions()).called(1);
      expect(cubit.state, [buyTx]);
    });

    test(
      'after successful deactivateQuote, optimistic remove stays if reload fetch fails',
      () async {
        final buyTx = const TransactionDto(
          id: 7,
          type: TransactionType.buy,
          state: TransactionState.waitingForPayment,
        );
        var call = 0;
        when(() => service.fetchPendingTransactions()).thenAnswer((_) async {
          call++;
          if (call == 1) return [buyTx];
          throw Exception('network');
        });

        final cubit = PendingTransactionsCubit(service, buyService);
        await cubit.stream.firstWhere((s) => s.isNotEmpty);
        expect(cubit.state, [buyTx]);

        await cubit.deactivate(buyTx);

        verify(() => buyService.deactivateQuote('7')).called(1);
        // constructor load + reload after deactivate
        verify(() => service.fetchPendingTransactions()).called(2);
        expect(cubit.state, isEmpty);
      },
    );

    test(
      'after successful deactivate of one of two quotes, remaining stays if reload throws',
      () async {
        final buy7 = const TransactionDto(
          id: 7,
          type: TransactionType.buy,
          state: TransactionState.waitingForPayment,
        );
        final buy8 = const TransactionDto(
          id: 8,
          type: TransactionType.buy,
          state: TransactionState.waitingForPayment,
        );
        var call = 0;
        when(() => service.fetchPendingTransactions()).thenAnswer((_) async {
          call++;
          if (call == 1) return [buy7, buy8];
          throw Exception('network');
        });

        final cubit = PendingTransactionsCubit(service, buyService);
        await cubit.stream.firstWhere((s) => s.isNotEmpty);
        expect(cubit.state, [buy7, buy8]);

        await cubit.deactivate(buy7);

        verify(() => buyService.deactivateQuote('7')).called(1);
        // constructor load + reload after deactivate
        verify(() => service.fetchPendingTransactions()).called(2);
        // optimistic remove of 7; reload throw must keep remaining quote 8
        expect(cubit.state, [buy8]);
      },
    );

    test('overlapping deactivate of the same idOrUid does not call deactivateQuote a second time',
        () async {
      final buyTx = const TransactionDto(
        id: 7,
        type: TransactionType.buy,
        state: TransactionState.waitingForPayment,
      );
      when(() => service.fetchPendingTransactions()).thenAnswer((_) async => [buyTx]);
      final completer = Completer<void>();
      when(() => buyService.deactivateQuote(any())).thenAnswer((_) => completer.future);
      final cubit = PendingTransactionsCubit(service, buyService);
      await cubit.stream.firstWhere((s) => s.isNotEmpty);
      final first = cubit.deactivate(buyTx);
      await cubit.deactivate(buyTx);
      completer.complete();
      await first;
      verify(() => buyService.deactivateQuote('7')).called(1);
    });

    test('overlapping deactivate of two different waiting buys both call deactivateQuote',
        () async {
      final buyTx = const TransactionDto(
        id: 7,
        type: TransactionType.buy,
        state: TransactionState.waitingForPayment,
      );
      final otherBuy = const TransactionDto(
        id: 8,
        type: TransactionType.buy,
        state: TransactionState.waitingForPayment,
      );
      when(() => service.fetchPendingTransactions()).thenAnswer((_) async => [buyTx, otherBuy]);
      final firstGate = Completer<void>();
      when(() => buyService.deactivateQuote(any())).thenAnswer((_) => firstGate.future);
      final cubit = PendingTransactionsCubit(service, buyService);
      await cubit.stream.firstWhere((s) => s.isNotEmpty);
      final first = cubit.deactivate(buyTx);
      final second = cubit.deactivate(otherBuy);
      firstGate.complete();
      await Future.wait([first, second]);
      verify(() => buyService.deactivateQuote('7')).called(1);
      verify(() => buyService.deactivateQuote('8')).called(1);
    });

    test('optimistic remove filters by idOrUid, not object identity', () async {
      final listed = const TransactionDto(
        id: 7,
        uid: 'listed',
        type: TransactionType.buy,
        state: TransactionState.waitingForPayment,
      );
      final other = const TransactionDto(
        id: 8,
        type: TransactionType.buy,
        state: TransactionState.waitingForPayment,
      );
      // Different instance than `listed` — object-identity filter would miss it.
      final otherInstance = const TransactionDto(
        id: 7,
        uid: 'other-instance',
        type: TransactionType.buy,
        state: TransactionState.waitingForPayment,
      );
      var call = 0;
      when(() => service.fetchPendingTransactions()).thenAnswer((_) async {
        call++;
        if (call == 1) return [listed, other];
        // Keep the optimistic remove visible (reload must not repaint the list).
        throw Exception('network');
      });

      final cubit = PendingTransactionsCubit(service, buyService);
      await cubit.stream.firstWhere((s) => s.isNotEmpty);
      expect(cubit.state, [listed, other]);

      await cubit.deactivate(otherInstance);

      verify(() => buyService.deactivateQuote('7')).called(1);
      // constructor load + reload after deactivate
      verify(() => service.fetchPendingTransactions()).called(2);
      expect(cubit.state, [other]);
    });

    test('deactivate completes without throwing when cubit is closed mid-flight', () async {
      final buyTx = const TransactionDto(
        id: 7,
        type: TransactionType.buy,
        state: TransactionState.waitingForPayment,
      );
      when(() => service.fetchPendingTransactions()).thenAnswer((_) async => [buyTx]);
      final completer = Completer<void>();
      when(() => buyService.deactivateQuote(any())).thenAnswer((_) => completer.future);

      final cubit = PendingTransactionsCubit(service, buyService);
      await cubit.stream.firstWhere((s) => s.isNotEmpty);
      final future = cubit.deactivate(buyTx);
      await cubit.close();
      completer.complete();
      await expectLater(future, completes);
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

      final cubit = PendingTransactionsCubit(service, buyService);
      await cubit.stream.firstWhere((s) => s.isNotEmpty);
      final reloadFuture = cubit.reload();
      await cubit.close();
      fetchGate.complete([buyTx]);
      await expectLater(reloadFuture, completes);
    });
  });
}
