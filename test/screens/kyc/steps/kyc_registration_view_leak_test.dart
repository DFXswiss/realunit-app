import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_country_service.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_kyc_service.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_registration_service.dart';
import 'package:realunit_wallet/screens/kyc/cubits/kyc/kyc_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/registration/cubits/registration_step/kyc_registration_step_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/registration/cubits/registration_submit/kyc_registration_submit_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/registration/kyc_registration_page.dart';

import '../../../helper/helper.dart';

class MockRegistrationStepCubit extends MockCubit<KycRegistrationStepState>
    implements KycRegistrationStepCubit {}

class MockRegistrationSubmitCubit extends MockCubit<KycRegistrationSubmitState>
    implements KycRegistrationSubmitCubit {}

class MockKycCubit extends MockCubit<KycState> implements KycCubit {}

class MockRealUnitRegistrationService extends Mock implements RealUnitRegistrationService {}

class MockDfxCountryService extends Mock implements DfxCountryService {}

class MockDfxKycService extends Mock implements DfxKycService {}

/// Audit #657 P5 F5: `_KycRegistrationViewState.dispose()` disposed every
/// controller except `birthdayCtrl` — that ValueNotifier leaked on every
/// mount/unmount of the KYC registration form.
///
/// A disposed ChangeNotifier throws a FlutterError from `addListener` in
/// debug builds; a leaked (undisposed) one accepts the listener silently.
/// The state class is private but its controller fields are public, so the
/// test reaches them via `dynamic` on `tester.state(...)`.
void main() {
  late KycRegistrationStepCubit registrationStepCubit;
  late KycRegistrationSubmitCubit registrationSubmitCubit;
  late KycCubit kycCubit;

  setUp(() {
    registrationStepCubit = MockRegistrationStepCubit();
    registrationSubmitCubit = MockRegistrationSubmitCubit();
    kycCubit = MockKycCubit();

    when(() => registrationStepCubit.state).thenReturn(
      const KycRegistrationStepState(
        step: KycRegistrationStep.personal,
        steps: [
          KycRegistrationStep.personal,
          KycRegistrationStep.address,
        ],
      ),
    );
    when(() => registrationSubmitCubit.state).thenReturn(KycRegistrationSubmitInitial());
    when(() => kycCubit.state).thenReturn(const KycInitial());
    when(() => kycCubit.checkKyc()).thenAnswer((_) => Future.value());
  });

  setUpAll(() {
    final getIt = GetIt.instance;
    getIt.registerSingleton<RealUnitRegistrationService>(MockRealUnitRegistrationService());
    getIt.registerSingleton<DfxCountryService>(MockDfxCountryService());
    getIt.registerSingleton<DfxKycService>(MockDfxKycService());
  });

  tearDownAll(() async => await GetIt.instance.reset());

  Widget buildSubject(Widget child) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: kycCubit),
        BlocProvider.value(value: registrationStepCubit),
        BlocProvider.value(value: registrationSubmitCubit),
      ],
      child: child,
    );
  }

  testWidgets(
    'unmounting $KycRegistrationView disposes every controller it created '
    '(audit #657 P5 F5)',
    (tester) async {
      await tester.pumpApp(buildSubject(const KycRegistrationView()));
      await tester.pump();

      // The state class is private; its controller fields are public.
      final dynamic state = tester.state(find.byType(KycRegistrationView));
      final controllers = <String, ChangeNotifier>{
        'typeCtrl': state.typeCtrl as ChangeNotifier,
        'phoneCtrl': state.phoneCtrl as ChangeNotifier,
        'nationalityCtrl': state.nationalityCtrl as ChangeNotifier,
        'birthdayCtrl': state.birthdayCtrl as ChangeNotifier,
        'countryCtrl': state.countryCtrl as ChangeNotifier,
      };

      // Unmount the view — dispose() must run for the state.
      await tester.pumpWidget(const SizedBox.shrink());

      for (final entry in controllers.entries) {
        expect(
          () => entry.value.addListener(() {}),
          throwsFlutterError,
          reason: '${entry.key} was not disposed when the view unmounted',
        );
      }
    },
  );
}
