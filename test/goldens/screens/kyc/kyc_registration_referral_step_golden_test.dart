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

  group('$KycRegistrationReferralStep', () {
    goldenTest(
      'empty optional code step',
      fileName: 'kyc_registration_referral_step_default',
      constraints: phoneConstraints,
      builder: () => wrapForGolden(
        Scaffold(
          body: BlocProvider<KycRegistrationStepCubit>.value(
            value: stepCubit,
            child: KycRegistrationReferralStep(
              referralCodeCtrl: TextEditingController(),
              lookup: (_) async => const ReferralCodeLookupDto(kind: 'Invite'),
            ),
          ),
        ),
      ),
    );

    goldenTest(
      'invite recognized after lookup',
      fileName: 'kyc_registration_referral_step_recognized',
      constraints: phoneConstraints,
      pumpBeforeTest: (tester) async {
        await alchemist.precacheImages(tester);
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
      },
      builder: () => wrapForGolden(
        Scaffold(
          body: BlocProvider<KycRegistrationStepCubit>.value(
            value: stepCubit,
            child: KycRegistrationReferralStep(
              referralCodeCtrl: TextEditingController(text: 'AB12CD'),
              lookup: (_) async => const ReferralCodeLookupDto(
                kind: 'Invite',
                inviterName: 'Björn',
              ),
            ),
          ),
        ),
      ),
    );

    goldenTest(
      'promo campaign dialog after lookup',
      fileName: 'kyc_registration_referral_step_promo',
      constraints: phoneConstraints,
      pumpBeforeTest: (tester) async {
        await alchemist.precacheImages(tester);
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
      },
      builder: () => wrapForGolden(
        Scaffold(
          body: BlocProvider<KycRegistrationStepCubit>.value(
            value: stepCubit,
            child: KycRegistrationReferralStep(
              referralCodeCtrl: TextEditingController(text: 'EVT1'),
              lookup: (_) async => const ReferralCodeLookupDto(
                kind: 'Promo',
                campaignText:
                    'Mit dem Code EVT1 schenken wir dir bei deinem ersten erfolgreich abgewickelten Kauf von mindestens 200 RealUnit-Aktientoken 20 Token dazu. Die 20 Token werden als Zugabe zum Kauf gewährt und mindern damit den effektiven Kaufpreis. Gültig bis 7.9.2026, einmal je Person, begrenzt auf 100 Einlösungen, nicht kumulierbar mit einer Empfehlungsprämie. Die RealUnit Schweiz AG kann die Aktion jederzeit beenden.',
              ),
            ),
          ),
        ),
      ),
    );

    goldenTest(
      'invalid code after lookup',
      fileName: 'kyc_registration_referral_step_invalid',
      constraints: phoneConstraints,
      pumpBeforeTest: (tester) async {
        await alchemist.precacheImages(tester);
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
      },
      builder: () => wrapForGolden(
        Scaffold(
          body: BlocProvider<KycRegistrationStepCubit>.value(
            value: stepCubit,
            child: KycRegistrationReferralStep(
              referralCodeCtrl: TextEditingController(text: 'NOPE'),
              lookup: (_) async => throw const ApiException(
                statusCode: 404,
                code: 'NOT_FOUND',
                message: 'missing',
              ),
            ),
          ),
        ),
      ),
    );
  });
}
