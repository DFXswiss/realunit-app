import 'dart:async';

import 'package:alchemist/alchemist.dart' as alchemist;
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_code_lookup_dto.dart';
import 'package:realunit_wallet/screens/kyc/steps/registration/cubits/registration_step/kyc_registration_step_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/registration/steps/kyc_registration_referral_step.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helper/helper.dart';

class _MockKycRegistrationStepCubit extends MockCubit<KycRegistrationStepState>
    implements KycRegistrationStepCubit {}

void main() {
  late _MockKycRegistrationStepCubit stepCubit;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    stepCubit = _MockKycRegistrationStepCubit();
    when(() => stepCubit.state).thenReturn(
      const KycRegistrationStepState(
        step: KycRegistrationStep.referral,
        steps: [
          KycRegistrationStep.referral,
          KycRegistrationStep.personal,
        ],
      ),
    );
  });

  Widget step({
    required String code,
    required Future<ReferralCodeLookupDto> Function(String) lookup,
  }) {
    return wrapForGolden(
      Scaffold(
        body: BlocProvider<KycRegistrationStepCubit>.value(
          value: stepCubit,
          child: KycRegistrationReferralStep(
            referralCodeCtrl: TextEditingController(text: code),
            lookup: lookup,
          ),
        ),
      ),
    );
  }

  Future<void> pumpLookup(WidgetTester tester) async {
    await alchemist.precacheImages(tester);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
  }

  group('$KycRegistrationReferralStep states', () {
    goldenTest(
      'loading while lookup is in flight',
      fileName: 'kyc_registration_referral_step_loading',
      constraints: phoneConstraints,
      pumpBeforeTest: (tester) async {
        // Hung lookup: do not pumpAndSettle (debounce 400ms starts the GET).
        await tester.pump(const Duration(milliseconds: 500));
      },
      builder: () {
        final hung = Completer<ReferralCodeLookupDto>();
        return step(code: 'AB12CD', lookup: (_) => hung.future);
      },
    );

    goldenTest(
      'spent code after lookup',
      fileName: 'kyc_registration_referral_step_spent',
      constraints: phoneConstraints,
      pumpBeforeTest: pumpLookup,
      builder: () => step(
        code: 'USED1',
        lookup: (_) async => throw const ApiException(
          statusCode: 410,
          code: 'SPENT',
          message: 'invite already bound',
        ),
      ),
    );

    goldenTest(
      'unavailable lookup error',
      fileName: 'kyc_registration_referral_step_unavailable',
      constraints: phoneConstraints,
      pumpBeforeTest: pumpLookup,
      builder: () => step(
        code: 'AB12CD',
        lookup: (_) async => throw const ApiException(
          statusCode: 503,
          code: 'UNAVAILABLE',
          message: 'down',
        ),
      ),
    );
  });
}
