import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/models/transactions/dto/transactions_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_buy_payment_info_service.dart';
import 'package:realunit_wallet/screens/dashboard/cubits/pending_transaction_detail/pending_transaction_detail_cubit.dart';

class _MockBuyPaymentInfoService extends Mock implements RealUnitBuyPaymentInfoService {}

TransactionDto _tx({
  int? id = 1,
  String? uid,
  TransactionType type = TransactionType.buy,
  TransactionState state = TransactionState.waitingForPayment,
}) =>
    TransactionDto(id: id, uid: uid, type: type, state: state);

void main() {
  late _MockBuyPaymentInfoService service;

  setUp(() {
    service = _MockBuyPaymentInfoService();
  });

  group('$PendingTransactionDetailCubit', () {
    test('initial state is PendingTransactionDetailInitial', () {
      expect(
        PendingTransactionDetailCubit(service).state,
        isA<PendingTransactionDetailInitial>(),
      );
    });

    test('deactivate calls service with id and emits Success', () async {
      when(() => service.deactivateQuote(any())).thenAnswer((_) async {});

      final cubit = PendingTransactionDetailCubit(service);
      final done = cubit.stream.firstWhere((s) => s is PendingTransactionDetailSuccess);
      await cubit.deactivate(_tx(id: 42));
      await done;

      expect(cubit.state, isA<PendingTransactionDetailSuccess>());
      verify(() => service.deactivateQuote('42')).called(1);
    });

    test('deactivate prefers id over uid', () async {
      when(() => service.deactivateQuote(any())).thenAnswer((_) async {});

      final cubit = PendingTransactionDetailCubit(service);
      final done = cubit.stream.firstWhere((s) => s is PendingTransactionDetailSuccess);
      await cubit.deactivate(_tx(id: 7, uid: 'uid-only'));
      await done;

      verify(() => service.deactivateQuote('7')).called(1);
    });

    test('deactivate falls back to uid when id is null', () async {
      when(() => service.deactivateQuote(any())).thenAnswer((_) async {});

      final cubit = PendingTransactionDetailCubit(service);
      final done = cubit.stream.firstWhere((s) => s is PendingTransactionDetailSuccess);
      await cubit.deactivate(_tx(id: null, uid: 'quote-uid'));
      await done;

      verify(() => service.deactivateQuote('quote-uid')).called(1);
    });

    test('deactivate no-ops for sell transactions', () async {
      final cubit = PendingTransactionDetailCubit(service);
      await cubit.deactivate(
        _tx(type: TransactionType.sell, state: TransactionState.waitingForPayment),
      );

      expect(cubit.state, isA<PendingTransactionDetailInitial>());
      verifyNever(() => service.deactivateQuote(any()));
    });

    test('deactivate no-ops for processing buy', () async {
      final cubit = PendingTransactionDetailCubit(service);
      await cubit.deactivate(
        _tx(type: TransactionType.buy, state: TransactionState.processing),
      );

      expect(cubit.state, isA<PendingTransactionDetailInitial>());
      verifyNever(() => service.deactivateQuote(any()));
    });

    test('deactivate no-ops when both id and uid are empty', () async {
      final cubit = PendingTransactionDetailCubit(service);
      await cubit.deactivate(
        const TransactionDto(
          id: null,
          uid: null,
          type: TransactionType.buy,
          state: TransactionState.waitingForPayment,
        ),
      );

      expect(cubit.state, isA<PendingTransactionDetailInitial>());
      verifyNever(() => service.deactivateQuote(any()));
    });

    test('deactivate no-ops when uid is empty string and id is null', () async {
      final cubit = PendingTransactionDetailCubit(service);
      await cubit.deactivate(
        const TransactionDto(
          id: null,
          uid: '',
          type: TransactionType.buy,
          state: TransactionState.waitingForPayment,
        ),
      );

      expect(cubit.state, isA<PendingTransactionDetailInitial>());
      verifyNever(() => service.deactivateQuote(any()));
    });

    test('deactivate emits Failure when service throws', () async {
      when(() => service.deactivateQuote(any())).thenAnswer(
        (_) async => throw Exception('network'),
      );

      final cubit = PendingTransactionDetailCubit(service);
      final done = cubit.stream.firstWhere((s) => s is PendingTransactionDetailFailure);
      await cubit.deactivate(_tx(id: 42));
      await done;

      expect(cubit.state, isA<PendingTransactionDetailFailure>());
    });

    test('deactivate emits Failure on ApiException', () async {
      when(() => service.deactivateQuote(any())).thenAnswer(
        (_) async => throw const ApiException(
          statusCode: 500,
          code: 'INTERNAL',
          message: 'oops',
        ),
      );

      final cubit = PendingTransactionDetailCubit(service);
      final done = cubit.stream.firstWhere((s) => s is PendingTransactionDetailFailure);
      await cubit.deactivate(_tx(id: 42));
      await done;

      expect(cubit.state, isA<PendingTransactionDetailFailure>());
    });

    test('deactivate while loading does not call the service again', () async {
      final gate = Completer<void>();
      when(() => service.deactivateQuote(any())).thenAnswer((_) => gate.future);

      final cubit = PendingTransactionDetailCubit(service);
      final first = cubit.deactivate(_tx(id: 42));
      expect(cubit.state, isA<PendingTransactionDetailLoading>());
      await cubit.deactivate(_tx(id: 42));
      verify(() => service.deactivateQuote('42')).called(1);

      gate.complete();
      await first;
    });

    test('deactivate completes without throwing when cubit is closed mid-flight',
        () async {
      final gate = Completer<void>();
      when(() => service.deactivateQuote(any())).thenAnswer((_) => gate.future);

      final cubit = PendingTransactionDetailCubit(service);
      final future = cubit.deactivate(_tx(id: 42));
      expect(cubit.state, isA<PendingTransactionDetailLoading>());
      await cubit.close();
      gate.complete();
      await expectLater(future, completes);
    });

    test('deactivate emits nothing after close when service fails mid-flight', () async {
      final gate = Completer<void>();
      when(() => service.deactivateQuote(any())).thenAnswer((_) => gate.future);

      final cubit = PendingTransactionDetailCubit(service);
      final future = cubit.deactivate(_tx(id: 42));
      await cubit.close();
      gate.completeError(Exception('gone'));
      await expectLater(future, completes);
    });

    test('state subclasses are equal to themselves and unequal across types', () {
      // Non-const so constructors are instrumented for line coverage.
      // ignore: prefer_const_constructors
      final initialA = PendingTransactionDetailInitial();
      // ignore: prefer_const_constructors
      final initialB = PendingTransactionDetailInitial();
      // ignore: prefer_const_constructors
      final loading = PendingTransactionDetailLoading();
      // ignore: prefer_const_constructors
      final success = PendingTransactionDetailSuccess();
      // ignore: prefer_const_constructors
      final failure = PendingTransactionDetailFailure();

      expect(initialA, equals(initialB));
      expect(initialA.props, isEmpty);
      expect(loading.props, isEmpty);
      expect(success.props, isEmpty);
      expect(failure.props, isEmpty);
      expect(initialA, isNot(equals(loading)));
      expect(success, isNot(equals(failure)));
    });
  });
}
