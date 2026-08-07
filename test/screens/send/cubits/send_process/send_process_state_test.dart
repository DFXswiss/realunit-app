import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/screens/send/cubits/send_process/send_process_cubit.dart';

/// Equatable-`props` surface tests for `SendProcessState`.
void main() {
  group('SendProcessState equality (Equatable props)', () {
    test('payload-less states expose empty props and compare by type', () {
      // Reading `.props` directly evaluates the inherited base getter; const
      // canonicalization would otherwise let `==` short-circuit via identical
      // and skip the getter line in the coverage report.
      expect(const SendProcessInitial().props, isEmpty);
      expect(const SendProcessPreparing().props, isEmpty);
      expect(const SendProcessSigning().props, isEmpty);

      // Same type compares equal (base `props => []`).
      expect(const SendProcessInitial(), const SendProcessInitial());
      expect(const SendProcessPreparing(), const SendProcessPreparing());
      expect(const SendProcessSigning(), const SendProcessSigning());

      // Different payload-less subclasses are unequal.
      expect(
        const SendProcessInitial(),
        isNot(equals(const SendProcessPreparing())),
      );
      expect(
        const SendProcessPreparing(),
        isNot(equals(const SendProcessSigning())),
      );
      expect(
        const SendProcessSigning(),
        isNot(equals(const SendProcessInitial())),
      );
    });

    test('SendProcessSuccess is keyed on txHash', () {
      expect(const SendProcessSuccess('h'), const SendProcessSuccess('h'));
      expect(
        const SendProcessSuccess('h'),
        isNot(equals(const SendProcessSuccess('g'))),
      );
      expect(const SendProcessSuccess('h').props, ['h']);
    });

    test('SendProcessFailure is keyed on reason + message + canRetry', () {
      // Equal when reason, message, and canRetry match.
      expect(
        const SendProcessFailure(
          SendProcessFailureReason.invalidRequest,
          message: 'm',
        ),
        const SendProcessFailure(
          SendProcessFailureReason.invalidRequest,
          message: 'm',
        ),
      );

      // Unequal when the reason differs.
      expect(
        const SendProcessFailure(
          SendProcessFailureReason.invalidRequest,
          message: 'm',
        ),
        isNot(
          equals(
            const SendProcessFailure(
              SendProcessFailureReason.generic,
              message: 'm',
            ),
          ),
        ),
      );

      // Unequal when the message differs.
      expect(
        const SendProcessFailure(
          SendProcessFailureReason.invalidRequest,
          message: 'm',
        ),
        isNot(
          equals(
            const SendProcessFailure(
              SendProcessFailureReason.invalidRequest,
              message: 'n',
            ),
          ),
        ),
      );

      // Unequal when canRetry differs (same reason + message).
      expect(
        const SendProcessFailure(
          SendProcessFailureReason.generic,
          message: 'm',
          canRetry: true,
        ),
        isNot(
          equals(
            const SendProcessFailure(
              SendProcessFailureReason.generic,
              message: 'm',
            ),
          ),
        ),
      );
      expect(
        const SendProcessFailure(
          SendProcessFailureReason.generic,
          message: 'm',
          canRetry: true,
        ),
        const SendProcessFailure(
          SendProcessFailureReason.generic,
          message: 'm',
          canRetry: true,
        ),
      );

      // The default (no `message`, canRetry false) variant is equal to itself
      // and unequal to the same reason carrying a message — both evaluate `props`.
      expect(
        const SendProcessFailure(SendProcessFailureReason.signatureCancelled),
        const SendProcessFailure(SendProcessFailureReason.signatureCancelled),
      );
      expect(
        const SendProcessFailure(SendProcessFailureReason.signatureCancelled),
        isNot(
          equals(
            const SendProcessFailure(
              SendProcessFailureReason.signatureCancelled,
              message: 'm',
            ),
          ),
        ),
      );

      expect(
        const SendProcessFailure(
          SendProcessFailureReason.invalidRequest,
          message: 'm',
        ).props,
        [SendProcessFailureReason.invalidRequest, 'm', false],
      );
      expect(
        const SendProcessFailure(SendProcessFailureReason.signatureCancelled).props,
        [SendProcessFailureReason.signatureCancelled, null, false],
      );
      expect(
        const SendProcessFailure(
          SendProcessFailureReason.generic,
          message: 'x',
          canRetry: true,
        ).props,
        [SendProcessFailureReason.generic, 'x', true],
      );
      expect(
        const SendProcessFailure(SendProcessFailureReason.confirmMismatch).props,
        [SendProcessFailureReason.confirmMismatch, null, false],
      );
    });
  });
}
