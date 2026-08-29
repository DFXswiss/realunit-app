import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/screens/kyc/steps/registration/cubits/registration_step/kyc_registration_step_cubit.dart';

void main() {
  group('$KycRegistrationStepCubit initial state', () {
    test('starts at the optional referral step with all steps in order', () {
      final cubit = KycRegistrationStepCubit();

      expect(cubit.state.step, KycRegistrationStep.referral);
      expect(cubit.state.steps, [
        KycRegistrationStep.referral,
        KycRegistrationStep.personal,
        KycRegistrationStep.address,
        KycRegistrationStep.taxResidence,
      ]);
      expect(cubit.state.index, 0);
      expect(cubit.state.totalSteps, 4);
      expect(cubit.state.progress, closeTo(1 / 4, 1e-9));
      expect(cubit.state.canGoBack, isFalse);
    });
  });

  group('next', () {
    blocTest<KycRegistrationStepCubit, KycRegistrationStepState>(
      'advances from referral to personal',
      build: KycRegistrationStepCubit.new,
      act: (c) => c.next(),
      verify: (c) {
        expect(c.state.step, KycRegistrationStep.personal);
        expect(c.state.index, 1);
        expect(c.state.progress, closeTo(2 / 4, 1e-9));
        expect(c.state.canGoBack, isTrue);
      },
    );

    test('next() at the last step is a no-op (no emit)', () {
      final cubit = KycRegistrationStepCubit()
        ..next()
        ..next()
        ..next();
      expect(cubit.state.step, KycRegistrationStep.taxResidence);
      final before = cubit.state;
      cubit.next();
      expect(cubit.state, same(before));
    });
  });

  group('previous', () {
    blocTest<KycRegistrationStepCubit, KycRegistrationStepState>(
      'goes from personal back to referral',
      build: KycRegistrationStepCubit.new,
      act: (c) => c
        ..next()
        ..previous(),
      verify: (c) {
        expect(c.state.step, KycRegistrationStep.referral);
        expect(c.state.canGoBack, isFalse);
      },
    );

    test('previous() at the first step is a no-op (no emit)', () {
      final cubit = KycRegistrationStepCubit();
      final before = cubit.state;
      cubit.previous();
      expect(cubit.state, same(before));
    });
  });

  group('$KycRegistrationStepState helpers', () {
    test('progress = (index + 1) / totalSteps', () {
      const state = KycRegistrationStepState(
        steps: [KycRegistrationStep.personal, KycRegistrationStep.address],
        step: KycRegistrationStep.personal,
      );
      expect(state.progress, closeTo(0.5, 1e-9));
    });

    test('canGoBack is false only at the first step', () {
      const personal = KycRegistrationStepState(
        steps: [KycRegistrationStep.personal, KycRegistrationStep.address],
        step: KycRegistrationStep.personal,
      );
      const address = KycRegistrationStepState(
        steps: [KycRegistrationStep.personal, KycRegistrationStep.address],
        step: KycRegistrationStep.address,
      );

      expect(personal.canGoBack, isFalse);
      expect(address.canGoBack, isTrue);
    });
  });
}
