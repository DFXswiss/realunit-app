import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/screens/pay/cubits/pay_scan/pay_scan_cubit.dart';

void main() {
  // LUD-01 bech32 of `https://api.dfx.swiss/v1/lnurlp/pl_abc123`.
  const lnurl = 'LNURL1DP68GURN8GHJ7CTSDYHXGENC9EEHW6TNWVHHVVF0D3H82UNVWQHHQMZLV93XXVFJXV5T0E5A';

  group('PayScanCubit', () {
    test('starts in PayScanScanning', () {
      expect(PayScanCubit().state, isA<PayScanScanning>());
    });

    blocTest<PayScanCubit, PayScanState>(
      'a valid LNURL emits PayScanDecoded with the id',
      build: PayScanCubit.new,
      act: (cubit) => cubit.onCodeDetected(lnurl),
      verify: (cubit) {
        final state = cubit.state as PayScanDecoded;
        expect(state.link.id, 'pl_abc123');
      },
    );

    blocTest<PayScanCubit, PayScanState>(
      'an invalid code emits PayScanInvalid',
      build: PayScanCubit.new,
      act: (cubit) => cubit.onCodeDetected('not-a-payment-code'),
      expect: () => [isA<PayScanInvalid>()],
    );

    blocTest<PayScanCubit, PayScanState>(
      'ignores further detections once decoded (no re-emit)',
      build: PayScanCubit.new,
      act: (cubit) {
        cubit.onCodeDetected(lnurl);
        cubit.onCodeDetected(lnurl);
      },
      expect: () => [isA<PayScanDecoded>()],
    );

    blocTest<PayScanCubit, PayScanState>(
      'reset returns to PayScanScanning',
      build: PayScanCubit.new,
      act: (cubit) {
        cubit.onCodeDetected('bad');
        cubit.reset();
      },
      expect: () => [isA<PayScanInvalid>(), isA<PayScanScanning>()],
    );
  });
}
