import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/payment/sell_exceptions.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/dto/eip7702/eip7702_data_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/dto/real_unit_sell_payment_info_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/sell_payment_info.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_sell_payment_info_service.dart';
import 'package:realunit_wallet/screens/sell/cubits/sell_confirm/sell_confirm_cubit.dart';
import 'package:realunit_wallet/styles/currency.dart';

class _MockSellPaymentInfoService extends Mock implements RealUnitSellPaymentInfoService {}

class _FakeSellPaymentInfo extends Fake implements SellPaymentInfo {}

SellPaymentInfo _stubPaymentInfo() => const SellPaymentInfo(
  id: 1,
  eip7702: Eip7702Data(
    relayerAddress: '0x1',
    delegationManagerAddress: '0x2',
    delegatorAddress: '0x3',
    userNonce: 0,
    domain: Eip7702Domain(
      name: 'RealUnit',
      version: '1',
      chainId: 1,
      verifyingContract: '0x4',
    ),
    types: Eip7702Types(delegation: [], caveat: []),
    message: Eip7702Message(
      delegate: '0x5',
      delegator: '0x6',
      authority: '0x7',
      caveats: [],
      salt: 0,
    ),
    tokenAddress: '0x8',
    amountWei: '0',
    depositAddress: '0x9',
  ),
  amount: 100,
  exchangeRate: 1.0,
  rate: 1.0,
  beneficiary: BeneficiaryDto(iban: 'CH56'),
  estimatedAmount: 100,
  currency: Currency.chf,
  depositAddress: '0xA',
  tokenAddress: '0xB',
  chainId: 1,
  ethBalance: 0.01,
  requiredGasEth: 0.001,
);

void main() {
  late _MockSellPaymentInfoService service;

  setUpAll(() {
    registerFallbackValue(_FakeSellPaymentInfo());
  });

  setUp(() {
    service = _MockSellPaymentInfoService();
  });

  group('$SellConfirmCubit', () {
    test('initial state is SellConfirmInitial', () {
      expect(SellConfirmCubit(service).state, isA<SellConfirmInitial>());
    });

    test('confirmPayment happy path passes through Loading and ends in Success', () async {
      // Mock the service to suspend long enough that Loading is observable
      // on the broadcast stream before Success replaces it.
      final completer = <SellConfirmState>[];
      when(() => service.confirmPayment(any())).thenAnswer((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });

      final cubit = SellConfirmCubit(service);
      final sub = cubit.stream.listen(completer.add);
      final future = cubit.confirmPayment(_stubPaymentInfo());
      // After microtask, Loading should have been emitted.
      await Future<void>.delayed(const Duration(milliseconds: 1));
      expect(completer.any((s) => s is SellConfirmLoading), isTrue);

      await future;
      await sub.cancel();

      expect(cubit.state, isA<SellConfirmSuccess>());
      verify(() => service.confirmPayment(any())).called(1);
    });

    test('confirmPayment emits Failure with the error message on throw', () async {
      when(
        () => service.confirmPayment(any()),
      ).thenAnswer((_) async => throw Exception('signing cancelled'));
      final cubit = SellConfirmCubit(service);

      await cubit.confirmPayment(_stubPaymentInfo());

      expect(cubit.state, isA<SellConfirmFailure>());
      expect(
        (cubit.state as SellConfirmFailure).error,
        contains('signing cancelled'),
      );
    });

    test('confirmPayment emits the API message 1:1 on ApiException', () async {
      when(() => service.confirmPayment(any())).thenAnswer(
        (_) async => throw const ApiException(
          statusCode: 503,
          code: 'AKTIONARIAT_UNAVAILABLE',
          message: 'Price source is temporarily unavailable',
        ),
      );
      final cubit = SellConfirmCubit(service);

      await cubit.confirmPayment(_stubPaymentInfo());

      expect(cubit.state, isA<SellConfirmFailure>());
      expect(
        (cubit.state as SellConfirmFailure).error,
        'Price source is temporarily unavailable',
      );
    });

    test(
      'already-confirmed conflict resolves to Success — the sell completed server-side',
      () async {
        when(() => service.confirmPayment(any())).thenAnswer(
          (_) async => throw const AlreadyConfirmedException(
            statusCode: 409,
            code: 'CONFLICT',
            message: 'Transaction request is already confirmed',
          ),
        );
        final cubit = SellConfirmCubit(service);

        await cubit.confirmPayment(_stubPaymentInfo());

        expect(cubit.state, isA<SellConfirmSuccess>());
      },
    );

    test('does not emit after close', () async {
      final completer = Completer<void>();
      when(() => service.confirmPayment(any())).thenAnswer((_) => completer.future);

      final cubit = SellConfirmCubit(service);
      unawaited(cubit.confirmPayment(_stubPaymentInfo()));
      await cubit.close();
      completer.complete();

      // If emit fires after close, StateError is thrown by the framework.
    });
  });
}
