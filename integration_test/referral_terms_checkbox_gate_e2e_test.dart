import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_summary_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_terms_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_referral_service.dart';
import 'package:realunit_wallet/screens/referral/cubit/referral_cubit.dart';
import 'package:realunit_wallet/screens/referral/referral_terms_page.dart';
import 'package:realunit_wallet/styles/themes.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';

class _MockReferralCubit extends MockCubit<ReferralState> implements ReferralCubit {}

class _MockService extends Mock implements RealUnitReferralService {}

const _summary = ReferralSummaryDto(
  eligible: true,
  termsAccepted: false,
  openCount: 0,
  creditedCount: 0,
  realuSum: 0,
  chfSum: 0,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late _MockReferralCubit cubit;

  setUp(() {
    cubit = _MockReferralCubit();
    when(() => cubit.state).thenReturn(const ReferralNeedsTerms(summary: _summary));
    whenListen(
      cubit,
      const Stream<ReferralState>.empty(),
      initialState: const ReferralNeedsTerms(summary: _summary),
    );
    when(() => cubit.acceptTerms()).thenAnswer((_) async {});
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  Future<void> pumpTerms(
    WidgetTester tester, {
    required Widget home,
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
        home: home,
      ),
    );
  }

  testWidgets(
    'create-invite CTA stays disabled until the accepted-terms checkbox is on',
    (tester) async {
      await pumpTerms(
        tester,
        home: BlocProvider<ReferralCubit>.value(
          value: cubit,
          child: const ReferralTermsPage(
            initialMarkdownContent: '# Teilnahmebedingungen',
          ),
        ),
      );
      await tester.pump();

      expect(
        find.text('Teilnahmebedingungen Referral-Programm'),
        findsOneWidget,
      );
      expect(
        find.text('Ich habe die Teilnahmebedingungen gelesen und akzeptiert'),
        findsOneWidget,
      );

      final button = tester.widget<AppFilledButton>(find.byType(AppFilledButton));
      expect(button.onPressed, isNull);

      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();

      final enabled = tester.widget<AppFilledButton>(find.byType(AppFilledButton));
      expect(enabled.onPressed, isNotNull);

      await tester.tap(find.byType(AppFilledButton));
      await tester.pump();
      verify(() => cubit.acceptTerms()).called(1);
    },
  );

  testWidgets(
    'read-only after accept hides the checkbox and create CTA',
    (tester) async {
      await pumpTerms(
        tester,
        home: const ReferralTermsPage(
          readOnly: true,
          initialMarkdownContent: '# Teilnahmebedingungen',
        ),
      );
      await tester.pump();

      expect(find.textContaining('Teilnahmebedingungen'), findsWidgets);
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(find.byType(AppFilledButton), findsNothing);
    },
  );

  testWidgets('checkbox is hidden until the TB markdown has loaded', (tester) async {
    final service = _MockService();
    when(() => service.getTerms()).thenAnswer(
      (_) => Completer<ReferralTermsDto>().future,
    );
    GetIt.instance.registerSingleton<RealUnitReferralService>(service);

    await pumpTerms(
      tester,
      home: BlocProvider<ReferralCubit>.value(
        value: cubit,
        child: const ReferralTermsPage(),
      ),
    );
    await tester.pump();

    expect(find.byType(CheckboxListTile), findsNothing);
    final button = tester.widget<AppFilledButton>(find.byType(AppFilledButton));
    expect(button.onPressed, isNull);
    expect(find.text('Teilnahmebedingungen werden geladen…'), findsOneWidget);
  });
}
