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

    test('deactivate on a buy with id calls deactivateQuote then reloads', () async {
      final buyTx = const TransactionDto(id: 7, type: TransactionType.buy);
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

    test('deactivate on a buy with null id and null uid does not call deactivateQuote', () async {
      final buyTx = const TransactionDto(
        id: null,
        uid: null,
        type: TransactionType.buy,
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
      final buyTx = const TransactionDto(id: 7, type: TransactionType.buy);
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
    });
  });
}
