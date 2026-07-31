import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/screens/send/cubits/send_amount/send_amount_cubit.dart';

void main() {
  group('SendAmountCubit', () {
    test('starts empty and not valid', () {
      final cubit = SendAmountCubit(availableShares: BigInt.from(10));
      expect(cubit.state.status, SendAmountStatus.empty);
      expect(cubit.state.isValid, isFalse);
    });

    blocTest<SendAmountCubit, SendAmountState>(
      'empty text → empty status',
      build: () => SendAmountCubit(availableShares: BigInt.from(10)),
      act: (cubit) => cubit.amountChanged('   '),
      verify: (cubit) => expect(cubit.state.status, SendAmountStatus.empty),
    );

    blocTest<SendAmountCubit, SendAmountState>(
      'a whole number within balance is valid',
      build: () => SendAmountCubit(availableShares: BigInt.from(10)),
      act: (cubit) => cubit.amountChanged('5'),
      verify: (cubit) {
        expect(cubit.state.status, SendAmountStatus.valid);
        expect(cubit.state.amount, 5);
        expect(cubit.state.isValid, isTrue);
      },
    );

    blocTest<SendAmountCubit, SendAmountState>(
      'zero is invalid',
      build: () => SendAmountCubit(availableShares: BigInt.from(10)),
      act: (cubit) => cubit.amountChanged('0'),
      verify: (cubit) => expect(cubit.state.status, SendAmountStatus.invalid),
    );

    blocTest<SendAmountCubit, SendAmountState>(
      'a non-integer is invalid',
      build: () => SendAmountCubit(availableShares: BigInt.from(10)),
      act: (cubit) => cubit.amountChanged('1.5'),
      verify: (cubit) => expect(cubit.state.status, SendAmountStatus.invalid),
    );

    blocTest<SendAmountCubit, SendAmountState>(
      'more than the available balance → insufficientBalance',
      build: () => SendAmountCubit(availableShares: BigInt.from(10)),
      act: (cubit) => cubit.amountChanged('11'),
      verify: (cubit) {
        expect(cubit.state.status, SendAmountStatus.insufficientBalance);
        expect(cubit.state.isValid, isFalse);
      },
    );

    blocTest<SendAmountCubit, SendAmountState>(
      'with unknown balance the over-balance guard is skipped (API validates)',
      build: SendAmountCubit.new,
      act: (cubit) => cubit.amountChanged('999999'),
      verify: (cubit) => expect(cubit.state.status, SendAmountStatus.valid),
    );

    blocTest<SendAmountCubit, SendAmountState>(
      'useMax fills the full available balance',
      build: () => SendAmountCubit(availableShares: BigInt.from(42)),
      act: (cubit) => cubit.useMax(),
      verify: (cubit) {
        expect(cubit.state.text, '42');
        expect(cubit.state.amount, 42);
        expect(cubit.state.status, SendAmountStatus.valid);
      },
    );

    blocTest<SendAmountCubit, SendAmountState>(
      'useMax is a no-op when the balance is zero',
      build: () => SendAmountCubit(availableShares: BigInt.zero),
      act: (cubit) => cubit.useMax(),
      expect: () => <SendAmountState>[],
    );

    blocTest<SendAmountCubit, SendAmountState>(
      'useMax is a no-op when the balance is unknown',
      build: SendAmountCubit.new,
      act: (cubit) => cubit.useMax(),
      expect: () => <SendAmountState>[],
    );
  });
}
