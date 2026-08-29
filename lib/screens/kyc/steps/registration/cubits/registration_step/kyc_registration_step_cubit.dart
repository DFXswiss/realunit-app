import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/generated/i18n.dart';

part 'kyc_registration_step_state.dart';

class KycRegistrationStepCubit extends Cubit<KycRegistrationStepState> {
  KycRegistrationStepCubit()
    : super(
        const KycRegistrationStepState(
          step: KycRegistrationStep.referral,
          steps: [
            KycRegistrationStep.referral,
            KycRegistrationStep.personal,
            KycRegistrationStep.address,
            KycRegistrationStep.taxResidence,
          ],
        ),
      );

  void next() {
    final currentIndex = state.index;
    if (currentIndex >= 0 && currentIndex < state.steps.length - 1) {
      emit(
        KycRegistrationStepState(
          step: state.steps.elementAt(currentIndex + 1),
          steps: state.steps,
        ),
      );
    }
  }

  void previous() {
    final currentIndex = state.index;
    if (currentIndex > 0 && currentIndex <= state.steps.length - 1) {
      emit(
        KycRegistrationStepState(
          step: state.steps.elementAt(currentIndex - 1),
          steps: state.steps,
        ),
      );
    }
  }
}
