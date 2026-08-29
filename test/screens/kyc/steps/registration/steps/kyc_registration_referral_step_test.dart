import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_code_lookup_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/screens/kyc/steps/registration/cubits/registration_step/kyc_registration_step_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/registration/steps/kyc_registration_referral_step.dart';
import 'package:realunit_wallet/setup/routing/referral_pending_code.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';
import 'package:realunit_wallet/widgets/buttons/app_text_button.dart';
import 'package:realunit_wallet/styles/themes.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockKycRegistrationStepCubit extends MockCubit<KycRegistrationStepState>
    implements KycRegistrationStepCubit {}

void main() {
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

  testWidgets('skip and next both advance the registration cubit', (tester) async {
    final ctrl = TextEditingController();
    await tester.pumpWidget(
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
              lookup: (_) async =>
                  const ReferralCodeLookupDto(kind: 'invite'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Überspringen'), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.autofocus, isTrue);

    ctrl.text = 'NOPE';
    await tester.tap(find.byType(AppTextButton));
    await tester.pump();
    expect(ctrl.text, isEmpty);
    verify(() => stepCubit.next()).called(1);
    clearInteractions(stepCubit);

    ctrl.text = 'AB12';
    await tester.pump();
    tester.widget<AppFilledButton>(find.byType(AppFilledButton)).onPressed!();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(ctrl.text, 'AB12');
    verify(() => stepCubit.next()).called(1);
  });

  testWidgets(
    'Next captures a pasted invite URL as the extracted code immediately',
    (tester) async {
      String? resolved = 'sentinel';
      final ctrl = TextEditingController();
      await tester.pumpWidget(
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
                onResolved: (code) => resolved = code,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      ctrl.text = 'https://realunit.app/invite/AB12CD';
      await tester.tap(find.text('Weiter'));
      await tester.pumpAndSettle();
      expect(resolved, 'AB12CD');
      verify(() => stepCubit.next()).called(1);
    },
  );

  testWidgets('Next does not stash a spent 4xx code', (tester) async {
    String? resolved = 'sentinel';
    final ctrl = TextEditingController();
    await tester.pumpWidget(
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
              onResolved: (code) => resolved = code,
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
    await tester.pump();

    ctrl.text = 'NOPE';
    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();
    expect(resolved, isNull);
    verify(() => stepCubit.next()).called(1);
  });

  testWidgets('Next ignores a second tap while lookup is in flight', (
    tester,
  ) async {
    final gate = Completer<ReferralCodeLookupDto>();
    final ctrl = TextEditingController();
    await tester.pumpWidget(
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
              lookup: (_) => gate.future,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    ctrl.text = 'AB12';
    await tester.tap(find.text('Weiter'));
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.enabled, isFalse);
    expect(find.byTooltip('Einfügen'), findsNothing);
    expect(
      tester.widget<AppFilledButton>(find.byType(AppFilledButton)).state,
      FilledButtonState.loading,
    );
    await tester.tap(find.text('Weiter'));
    gate.complete(const ReferralCodeLookupDto(kind: 'invite', inviterName: 'Björn'));
    await tester.pumpAndSettle();
    verify(() => stepCubit.next()).called(1);
  });

  testWidgets(
    'Skip during Next lookup discards the code and advances once',
    (tester) async {
      final gate = Completer<ReferralCodeLookupDto>();
      String? resolved = 'sentinel';
      final ctrl = TextEditingController(text: 'AB12');
      await tester.pumpWidget(
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
                lookup: (_) => gate.future,
                onResolved: (code) => resolved = code,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(resolved, 'AB12');

      await tester.tap(find.byType(AppFilledButton));
      await tester.pump();
      expect(
        tester.widget<AppFilledButton>(find.byType(AppFilledButton)).state,
        FilledButtonState.loading,
      );

      await tester.tap(find.byType(AppTextButton));
      await tester.pump();
      expect(ctrl.text, isEmpty);
      expect(resolved, isNull);
      verify(() => stepCubit.next()).called(1);

      gate.complete(
        const ReferralCodeLookupDto(kind: 'invite', inviterName: 'Björn'),
      );
      await tester.pump();
      expect(resolved, isNull);
    },
  );

  testWidgets(
    'skip clears the field but leaves a deeplink stash for automatic takeover',
    (tester) async {
      await stashPendingReferralCode('AB12CD');
      String? resolved = 'sentinel';
      final ctrl = TextEditingController(text: 'TYPED');
      await tester.pumpWidget(
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
                onResolved: (code) => resolved = code,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Überspringen'));
      expect(ctrl.text, isEmpty);
      expect(resolved, isNull);
      expect(await peekPendingReferralCode(), 'AB12CD');
    },
  );

  testWidgets(
    'skip discards an in-flight lookup so a late 200 is not stashed',
    (tester) async {
      final lookup = Completer<ReferralCodeLookupDto>();
      String? resolved = 'sentinel';
      final ctrl = TextEditingController(text: 'AB12');
      await tester.pumpWidget(
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
                lookup: (_) => lookup.future,
                onResolved: (code) => resolved = code,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(resolved, 'AB12');

      await tester.tap(find.text('Überspringen'));
      expect(ctrl.text, isEmpty);
      expect(resolved, isNull);

      lookup.complete(
        const ReferralCodeLookupDto(kind: 'invite', inviterName: 'Björn'),
      );
      await tester.pump();
      expect(resolved, isNull);
      expect(find.textContaining('Einladung von Björn erkannt'), findsNothing);
      verify(() => stepCubit.next()).called(1);
    },
  );

  testWidgets(
    'skip discards an in-flight paste so a late clipboard write is not stashed',
    (tester) async {
      final release = Completer<String?>();
      String? resolved = 'sentinel';
      final ctrl = TextEditingController();
      await tester.pumpWidget(
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
                readClipboard: () => release.future,
                lookup: (_) async => const ReferralCodeLookupDto(
                  kind: 'invite',
                  inviterName: 'Björn',
                ),
                onResolved: (code) => resolved = code,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Einfügen'));
      await tester.pump();

      await tester.tap(find.text('Überspringen'));
      expect(ctrl.text, isEmpty);
      expect(resolved, isNull);

      release.complete('AB12');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(ctrl.text, isEmpty);
      expect(resolved, isNull);
      expect(find.textContaining('Einladung von Björn erkannt'), findsNothing);
      verify(() => stepCubit.next()).called(1);
    },
  );

  testWidgets('skip dismisses an open promo dialog', (tester) async {
    final ctrl = TextEditingController(text: 'EVT1');
    await tester.pumpWidget(
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
              lookup: (_) async => const ReferralCodeLookupDto(
                kind: 'promo',
                actionText: 'Mit dem Code EVT1 schenken wir dir 20 Token.',
              ),
            ),
          ),
        ),
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
