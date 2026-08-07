import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/screens/send/cubits/send_recipient/send_recipient_cubit.dart';

void main() {
  // A valid EVM address and its EIP-55 checksum form.
  const lowercase = '0x9f5713deacb8e9cab6c2d3fae1afc2715f8d2d71';
  const checksummed = '0x9F5713DEacB8e9CAB6c2d3FaE1AFc2715F8D2D71';

  group('SendRecipientCubit', () {
    test('starts empty', () {
      expect(SendRecipientCubit().state, isA<SendRecipientEmpty>());
    });

    blocTest<SendRecipientCubit, SendRecipientState>(
      'a valid address is normalized to its EIP-55 checksum',
      build: SendRecipientCubit.new,
      act: (cubit) => cubit.submit(lowercase),
      verify: (cubit) {
        final state = cubit.state as SendRecipientValid;
        expect(state.address, checksummed);
      },
    );

    blocTest<SendRecipientCubit, SendRecipientState>(
      'trims surrounding whitespace before validating',
      build: SendRecipientCubit.new,
      act: (cubit) => cubit.submit('  $checksummed  '),
      expect: () => [const SendRecipientValid(checksummed)],
    );

    blocTest<SendRecipientCubit, SendRecipientState>(
      'strips an ethereum: EIP-681 scheme and @chainId / query suffix',
      build: SendRecipientCubit.new,
      act: (cubit) => cubit.submit('ethereum:$lowercase@1?value=0'),
      expect: () => [const SendRecipientValid(checksummed)],
    );

    blocTest<SendRecipientCubit, SendRecipientState>(
      'strips ethereum: pay- EIP-681 payment-request marker before the address',
      build: SendRecipientCubit.new,
      act: (cubit) => cubit.submit('ethereum:pay-$lowercase@1?value=100'),
      expect: () => [const SendRecipientValid(checksummed)],
    );

    blocTest<SendRecipientCubit, SendRecipientState>(
      'strips a query suffix when no @chainId is present (simple form)',
      build: SendRecipientCubit.new,
      act: (cubit) => cubit.submit('ethereum:$lowercase?value=0'),
      expect: () => [const SendRecipientValid(checksummed)],
    );

    blocTest<SendRecipientCubit, SendRecipientState>(
      'EIP-681 ERC-20 transfer URI extracts recipient from address= query param',
      build: SendRecipientCubit.new,
      act: (cubit) => cubit.submit(
        'ethereum:0x1111111111111111111111111111111111111111/transfer'
        '?address=$lowercase&uint256=1000000000000000000',
      ),
      expect: () => [const SendRecipientValid(checksummed)],
    );

    blocTest<SendRecipientCubit, SendRecipientState>(
      'EIP-681 function-call with unrecognized function name fails closed',
      build: SendRecipientCubit.new,
      act: (cubit) => cubit.submit('ethereum:$lowercase/approve?spender=0xSpender&uint256=1'),
      expect: () => [isA<SendRecipientInvalid>()],
    );

    blocTest<SendRecipientCubit, SendRecipientState>(
      'EIP-681 function-call without a query string fails closed',
      build: SendRecipientCubit.new,
      act: (cubit) => cubit.submit('ethereum:$lowercase/transfer'),
      expect: () => [isA<SendRecipientInvalid>()],
    );

    blocTest<SendRecipientCubit, SendRecipientState>(
      'EIP-681 /transfer URI without address query param fails closed',
      build: SendRecipientCubit.new,
      act: (cubit) => cubit.submit('ethereum:$lowercase/transfer?uint256=1'),
      expect: () => [isA<SendRecipientInvalid>()],
    );

    blocTest<SendRecipientCubit, SendRecipientState>(
      'EIP-681 /transfer URI with empty address= query param fails closed',
      build: SendRecipientCubit.new,
      act: (cubit) => cubit.submit('ethereum:$lowercase/transfer?address=&uint256=1'),
      expect: () => [isA<SendRecipientInvalid>()],
    );

    blocTest<SendRecipientCubit, SendRecipientState>(
      'EIP-681 /transfer URI with duplicate address= query keys fails closed',
      build: SendRecipientCubit.new,
      act: (cubit) => cubit.submit(
        'ethereum:0x1111111111111111111111111111111111111111/transfer'
        '?address=$lowercase&address=0x2222222222222222222222222222222222222222',
      ),
      expect: () => [isA<SendRecipientInvalid>()],
    );

    blocTest<SendRecipientCubit, SendRecipientState>(
      'EIP-681 /transfer URI with malformed percent-encoding emits invalid (no throw)',
      build: SendRecipientCubit.new,
      act: (cubit) => cubit.submit(
        'ethereum:0x1111111111111111111111111111111111111111/transfer?address=%ZZ',
      ),
      expect: () => [isA<SendRecipientInvalid>()],
    );

    blocTest<SendRecipientCubit, SendRecipientState>(
      'an invalid address emits SendRecipientInvalid',
      build: SendRecipientCubit.new,
      act: (cubit) => cubit.submit('not-an-address'),
      expect: () => [isA<SendRecipientInvalid>()],
    );

    blocTest<SendRecipientCubit, SendRecipientState>(
      'onCodeDetected decodes a scanned address like submit',
      build: SendRecipientCubit.new,
      act: (cubit) => cubit.onCodeDetected(checksummed),
      expect: () => [const SendRecipientValid(checksummed)],
    );

    blocTest<SendRecipientCubit, SendRecipientState>(
      'onCodeDetected ignores further detections once valid (no re-emit)',
      build: SendRecipientCubit.new,
      act: (cubit) {
        cubit.onCodeDetected(checksummed);
        cubit.onCodeDetected(checksummed);
      },
      expect: () => [const SendRecipientValid(checksummed)],
    );

    blocTest<SendRecipientCubit, SendRecipientState>(
      'reset returns to empty',
      build: SendRecipientCubit.new,
      act: (cubit) {
        cubit.submit(checksummed);
        cubit.reset();
      },
      expect: () => [const SendRecipientValid(checksummed), const SendRecipientEmpty()],
    );
  });
}
