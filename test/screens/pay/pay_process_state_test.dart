import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/screens/pay/cubits/pay_process/pay_process_cubit.dart';

void main() {
  group('PayProcessState equality (Equatable props)', () {
    test('progress states with no fields expose empty props and compare by type', () {
      // Reading `.props` directly evaluates the inherited base getter (const
      // canonicalization would otherwise make `==` short-circuit via identical).
      expect(const PayProcessPreparingSwap().props, isEmpty);
      expect(const PayProcessWaitingForEth().props, isEmpty);
      expect(const PayProcessInitial().props, isEmpty);
      expect(const PayProcessSwapping().props, isEmpty);
      expect(const PayProcessRefreshingQuote().props, isEmpty);
      expect(const PayProcessPaying().props, isEmpty);
      expect(const PayProcessSuccess().props, isEmpty);
      expect(
        const PayProcessPreparingSwap(),
        isNot(equals(const PayProcessWaitingForEth())),
      );
    });

    test('PayProcessAwaitingSettlement is keyed on txId', () {
      expect(
        const PayProcessAwaitingSettlement('0xtx'),
        const PayProcessAwaitingSettlement('0xtx'),
      );
      expect(
        const PayProcessAwaitingSettlement('0xtx'),
        isNot(equals(const PayProcessAwaitingSettlement('0xother'))),
      );
      expect(const PayProcessAwaitingSettlement('0xtx').props, ['0xtx']);
    });

    test('PayProcessFailure is keyed on reason + message', () {
      expect(
        const PayProcessFailure(PayProcessFailureReason.generic),
        const PayProcessFailure(PayProcessFailureReason.generic),
      );
      expect(
        const PayProcessFailure(PayProcessFailureReason.generic),
        isNot(equals(const PayProcessFailure(PayProcessFailureReason.insufficientEth))),
      );
      expect(
        const PayProcessFailure(PayProcessFailureReason.generic, message: 'boom').props,
        [PayProcessFailureReason.generic, 'boom'],
      );
    });

    test('PayProcessPayRetry is keyed on reason + message', () {
      expect(
        const PayProcessPayRetry(PayRetryReason.transient),
        const PayProcessPayRetry(PayRetryReason.transient),
      );
      expect(
        const PayProcessPayRetry(PayRetryReason.transient),
        isNot(equals(const PayProcessPayRetry(PayRetryReason.quoteExpired))),
      );
      expect(
        const PayProcessPayRetry(PayRetryReason.insufficientZchf, message: 'short').props,
        [PayRetryReason.insufficientZchf, 'short'],
      );
    });
  });
}
