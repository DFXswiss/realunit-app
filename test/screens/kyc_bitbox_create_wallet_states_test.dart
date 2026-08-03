import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/packages/service/dfx/models/kyc/kyc_level.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';
import 'package:realunit_wallet/screens/create_wallet/bloc/create_wallet_cubit.dart';
import 'package:realunit_wallet/screens/kyc/cubits/kyc/kyc_cubit.dart';

const _testSeed =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

void main() {
  group('$KycState', () {
    test('KycStep enum has all 11 documented variants', () {
      // The KycCubit advances through these steps in order; pin the set so a
      // refactor that drops one surfaces here.
      expect(KycStep.values.toSet(), {
        KycStep.email,
        KycStep.confirmEmail,
        KycStep.registration,
        KycStep.personalData,
        KycStep.linkWallet,
        KycStep.legalDisclaimer,
        KycStep.nationality,
        KycStep.twoFa,
        KycStep.ident,
        KycStep.financialData,
        KycStep.dfxApproval,
      });
    });

    test('KycPending props pin the pendingStep', () {
      expect(
        const KycPending(KycStep.email),
        const KycPending(KycStep.email),
      );
      expect(
        const KycPending(KycStep.email),
        isNot(const KycPending(KycStep.financialData)),
      );
    });

    test('KycSuccess props pin (currentStep, urlOrToken)', () {
      const a = KycSuccess(currentStep: KycStep.email, urlOrToken: 'https://k/1');
      const b = KycSuccess(currentStep: KycStep.email, urlOrToken: 'https://k/1');
      const c = KycSuccess(currentStep: KycStep.email, urlOrToken: 'https://k/2');
      expect(a, b);
      expect(a, isNot(c));
    });

    test('KycUnsupportedStepFailure props pin the stepName', () {
      expect(
        const KycUnsupportedStepFailure(KycStepName.contactData),
        const KycUnsupportedStepFailure(KycStepName.contactData),
      );
      expect(
        const KycUnsupportedStepFailure(KycStepName.contactData),
        isNot(const KycUnsupportedStepFailure(KycStepName.nationalityData)),
      );
    });

    test('KycFailure props pin the message', () {
      expect(const KycFailure('boom'), const KycFailure('boom'));
      expect(const KycFailure('boom'), isNot(const KycFailure('other')));
    });

    test('KycCompleted vs KycAccountMergeRequested are distinct singletons', () {
      expect(const KycCompleted(), const KycCompleted());
      expect(const KycAccountMergeRequested(), const KycAccountMergeRequested());
      expect(const KycCompleted(), isNot(const KycAccountMergeRequested()));
    });
  });

  group('$CreateWalletState defaults + copyWith', () {
    test('defaults: hideSeed=true, wallet=null', () {
      const state = CreateWalletState();
      expect(state.hideSeed, isTrue);
      expect(state.wallet, isNull);
    });

    test('copyWith preserves untouched fields', () {
      final wallet = SoftwareWallet(1, 'test', _testSeed);
      final base = CreateWalletState(wallet: wallet);
      final next = base.copyWith(hideSeed: false);
      expect(next.hideSeed, isFalse);
      expect(next.wallet, wallet);
    });
  });
}
