import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_country_service.dart';
import 'package:realunit_wallet/packages/service/dfx/models/country/country.dart';
import 'package:realunit_wallet/screens/kyc/steps/registration/cubits/registration_step/kyc_registration_step_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/registration/steps/kyc_registration_address_step.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';

import '../../../helper/helper.dart';

class _MockKycRegistrationStepCubit extends MockCubit<KycRegistrationStepState>
    implements KycRegistrationStepCubit {}

void main() {
  late _MockKycRegistrationStepCubit stepCubit;

  setUpAll(() {
    GetIt.instance.registerSingleton<DfxCountryService>(fixtureCountryService());
  });

  tearDownAll(() async => GetIt.instance.reset());

  setUp(() {
    stepCubit = _MockKycRegistrationStepCubit();
    when(() => stepCubit.state).thenReturn(
      const KycRegistrationStepState(
        step: KycRegistrationStep.address,
        steps: [
          KycRegistrationStep.personal,
          KycRegistrationStep.address,
          KycRegistrationStep.taxResidence,
        ],
      ),
    );
  });

  Widget buildSubject() => wrapForGolden(
        BlocProvider<KycRegistrationStepCubit>.value(
          value: stepCubit,
          child: Scaffold(
            body: KycRegistrationAddressStep(
              addressStreetCtrl: TextEditingController(),
              addressNumberCtrl: TextEditingController(),
              postalCodeCtrl: TextEditingController(),
              cityCtrl: TextEditingController(),
              countryCtrl: ValueNotifier<Country?>(null),
            ),
          ),
        ),
      );

  group('$KycRegistrationAddressStep', () {
    goldenTest(
      'validation error after Next — red error borders on every field + country',
      fileName: 'kyc_registration_address_step_validation_error',
      constraints: phoneConstraints,
      // Tapping 'Next' with empty controllers runs Form.validate(): every text
      // field returns the empty sentinel and the residence CountryField reports
      // its "no country picked" error, so all four inputs plus the country
      // dropdown flip to red (hideErrorText keeps them frame-only).
      pumpBeforeTest: (tester) async {
        await tester.pumpAndSettle();
        final next = find.byType(AppFilledButton);
        await tester.ensureVisible(next);
        await tester.tap(next);
        await tester.pumpAndSettle();
      },
      builder: buildSubject,
    );
  });
}
