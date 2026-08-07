import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_country_service.dart';
import 'package:realunit_wallet/packages/service/dfx/models/country/country.dart';
import 'package:realunit_wallet/packages/service/dfx/models/registration/registration_user_type.dart';
import 'package:realunit_wallet/screens/kyc/steps/registration/cubits/registration_step/kyc_registration_step_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/registration/steps/kyc_registration_personal_step.dart';
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
        step: KycRegistrationStep.personal,
        steps: [
          KycRegistrationStep.personal,
          KycRegistrationStep.address,
        ],
      ),
    );
  });

  // Empty controllers so `_formKey.currentState.validate()` fails on every
  // required field once 'Next' is tapped (empty first/last name, no birthday, no
  // nationality). The account-type dropdown pre-selects `human` so it stays
  // valid; the phone prefix defaults to '+41'.
  Widget buildSubject() => wrapForGolden(
        BlocProvider<KycRegistrationStepCubit>.value(
          value: stepCubit,
          child: Scaffold(
            body: KycRegistrationPersonalStep(
              typeCtrl: ValueNotifier<RegistrationUserType>(
                RegistrationUserType.human,
              ),
              firstNameCtrl: TextEditingController(),
              lastNameCtrl: TextEditingController(),
              phoneCtrl: ValueNotifier<String?>(null),
              nationalityCtrl: ValueNotifier<Country?>(null),
              birthdayCtrl: ValueNotifier<String?>(null),
            ),
          ),
        ),
      );

  group('$KycRegistrationPersonalStep', () {
    goldenTest(
      'validation error after Next — red error borders on the empty fields',
      fileName: 'kyc_registration_personal_step_validation_error',
      constraints: phoneConstraints,
      // The 'Next' tap runs Form.validate(); the empty first/last-name, birthday
      // and nationality validators return the empty sentinel, flipping their
      // borders red. hideErrorText suppresses the message on all but the phone
      // number field (phone_number_field.dart:89), so most fields show a bare
      // red frame.
      pumpBeforeTest: (tester) async {
        await tester.pumpAndSettle();
        final next = find.byType(AppFilledButton);
        await tester.ensureVisible(next);
        await tester.tap(next);
        await tester.pumpAndSettle();
      },
      builder: buildSubject,
    );

    goldenTest(
      'account-type dropdown open — the single-item overlay menu',
      fileName: 'kyc_registration_personal_step_account_type_open',
      constraints: phoneConstraints,
      pumpBeforeTest: (tester) async {
        await tester.pumpAndSettle();
        final field = find.byType(DropdownButtonFormField<RegistrationUserType>);
        await tester.ensureVisible(field);
        await tester.tap(field);
        await tester.pumpAndSettle();
      },
      builder: buildSubject,
    );

    goldenTest(
      'phone-prefix dropdown open — the +41 / +49 overlay menu',
      fileName: 'kyc_registration_personal_step_phone_prefix_open',
      constraints: phoneConstraints,
      pumpBeforeTest: (tester) async {
        await tester.pumpAndSettle();
        // The prefix dropdown renders its selected value '+41'; the birthday
        // String dropdowns show day/month/year hints instead, so this is unique.
        final field = find.widgetWithText(
          DropdownButtonFormField<String>,
          '+41',
        );
        await tester.ensureVisible(field);
        await tester.tap(field);
        await tester.pumpAndSettle();
      },
      builder: buildSubject,
    );
  });
}
