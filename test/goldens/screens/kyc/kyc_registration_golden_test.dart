import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_country_service.dart';
import 'package:realunit_wallet/screens/kyc/cubits/kyc/kyc_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/registration/cubits/registration_step/kyc_registration_step_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/registration/cubits/registration_submit/kyc_registration_submit_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/registration/kyc_registration_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helper/helper.dart';

class _MockKycRegistrationStepCubit extends MockCubit<KycRegistrationStepState>
    implements KycRegistrationStepCubit {}

class _MockKycRegistrationSubmitCubit
    extends MockCubit<KycRegistrationSubmitState>
    implements KycRegistrationSubmitCubit {}

class _MockKycCubit extends MockCubit<KycState> implements KycCubit {}

void main() {

  late _MockKycRegistrationStepCubit registrationStepCubit;
  late _MockKycRegistrationSubmitCubit registrationSubmitCubit;
  late _MockKycCubit kycCubit;

  setUp(() {
    registrationStepCubit = _MockKycRegistrationStepCubit();
    registrationSubmitCubit = _MockKycRegistrationSubmitCubit();
    kycCubit = _MockKycCubit();

    when(() => registrationStepCubit.state).thenReturn(
      const KycRegistrationStepState(
        step: KycRegistrationStep.personal,
        steps: [
          KycRegistrationStep.personal,
          KycRegistrationStep.address,
        ],
      ),
    );
    when(() => registrationSubmitCubit.state)
        .thenReturn(KycRegistrationSubmitInitial());
    when(() => kycCubit.state).thenReturn(const KycInitial());
  });

  // The page no longer reads `RealUnitRegistrationService` directly — the parent
  // `KycCubit` passes the (possibly null) `RealUnitUserDataDto` via
  // constructor. The default golden uses `initialUserData: null` so it asserts
  // on the empty-form render, which is the first-time-registration path.
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    GetIt.instance.registerSingleton<DfxCountryService>(fixtureCountryService());
  });

  tearDownAll(() async => GetIt.instance.reset());

  group('$KycRegistrationView', () {
    goldenTest(
      'initial personal step',
      fileName: 'kyc_registration_page_default',
      constraints: phoneConstraints,
      builder: () => wrapForGolden(
        MultiBlocProvider(
          providers: [
            BlocProvider<KycCubit>.value(value: kycCubit),
            BlocProvider<KycRegistrationStepCubit>.value(
              value: registrationStepCubit,
            ),
            BlocProvider<KycRegistrationSubmitCubit>.value(
              value: registrationSubmitCubit,
            ),
          ],
          child: const KycRegistrationView(),
        ),
      ),
    );
  });
}
