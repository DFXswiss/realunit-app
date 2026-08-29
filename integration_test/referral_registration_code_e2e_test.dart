import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_code_lookup_dto.dart';
import 'package:realunit_wallet/screens/kyc/steps/registration/cubits/registration_step/kyc_registration_step_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/registration/steps/kyc_registration_referral_step.dart';
import 'package:realunit_wallet/setup/routing/referral_pending_code.dart';
import 'package:realunit_wallet/styles/themes.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';
import 'package:realunit_wallet/widgets/buttons/app_text_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockKycRegistrationStepCubit extends MockCubit<KycRegistrationStepState>
    implements KycRegistrationStepCubit {}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late _MockKycRegistrationStepCubit stepCubit;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugSetPendingReferralCodeSync(null);
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

  Future<void> pumpStep(
    WidgetTester tester, {
    required TextEditingController ctrl,
    required Future<ReferralCodeLookupDto> Function(String code) lookup,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        theme: realUnitTheme,
        locale: const Locale('de'),
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        home: Scaffold(
          body: BlocProvider<KycRegistrationStepCubit>.value(
            value: stepCubit,
            child: KycRegistrationReferralStep(
              referralCodeCtrl: ctrl,
              lookup: lookup,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('invite lookup shows Einladung erkannt on the registration step', (
    tester,
  ) async {
    final ctrl = TextEditingController(text: 'AB12');
    await pumpStep(
      tester,
      ctrl: ctrl,
      lookup: (_) async => const ReferralCodeLookupDto(
        kind: 'invite',
        inviterName: 'Björn',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.textContaining('Einladung von Björn erkannt'), findsOneWidget);
    expect(find.text('Überspringen'), findsOneWidget);
    expect(find.text('Weiter'), findsOneWidget);
  });

  testWidgets('promo lookup shows the Aktion campaign dialog', (tester) async {
    final ctrl = TextEditingController(text: 'EVT1');
    await pumpStep(
      tester,
      ctrl: ctrl,
      lookup: (_) async => const ReferralCodeLookupDto(
        kind: 'promo',
        actionText: 'Mit dem Code EVT1 schenken wir dir 20 Token.',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('Aktion'), findsOneWidget);
    expect(
      find.text('Mit dem Code EVT1 schenken wir dir 20 Token.'),
      findsWidgets,
    );
  });

  testWidgets('skip dismisses an open promo dialog', (tester) async {
    final ctrl = TextEditingController(text: 'EVT1');
    await pumpStep(
      tester,
      ctrl: ctrl,
      lookup: (_) async => const ReferralCodeLookupDto(
        kind: 'promo',
        actionText: 'Mit dem Code EVT1 schenken wir dir 20 Token.',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('Aktion'), findsOneWidget);

    tester.widget<AppTextButton>(find.byType(AppTextButton)).onPressed!();
    await tester.pump();
    expect(
      tester.widget<AppFilledButton>(find.byType(AppFilledButton)).state,
      FilledButtonState.idle,
    );
    await tester.pumpAndSettle();

    expect(find.text('Aktion'), findsNothing);
    expect(ctrl.text, isEmpty);
    verify(() => stepCubit.next()).called(1);
  });
}
