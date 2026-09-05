import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_summary_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_referral_service.dart';
import 'package:realunit_wallet/screens/referral/cubit/referral_cubit.dart';
import 'package:realunit_wallet/screens/referral/open_referral_create.dart';
import 'package:realunit_wallet/screens/referral/referral_error_message.dart';
import 'package:realunit_wallet/screens/referral/referral_page.dart';
import 'package:realunit_wallet/screens/settings/bloc/settings_bloc.dart';
import 'package:realunit_wallet/setup/routing/routes/settings_routes.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/styles/language.dart';
import 'package:realunit_wallet/styles/themes.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';

class _MockReferralCubit extends MockCubit<ReferralState>
    implements ReferralCubit {}

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _MockService extends Mock implements RealUnitReferralService {}

void main() {
  late _MockReferralCubit cubit;
  late _MockSettingsBloc settings;

  setUp(() {
    debugResetOpeningReferralCreate();
    cubit = _MockReferralCubit();
    when(() => cubit.load()).thenAnswer((_) async {});
    settings = _MockSettingsBloc();
    const settingsState = SettingsState(language: Language.de);
    when(() => settings.state).thenReturn(settingsState);
    whenListen(
      settings,
      const Stream<SettingsState>.empty(),
      initialState: settingsState,
    );
  });

  Future<void> pumpGate(WidgetTester tester, ReferralState state) async {
    when(() => cubit.state).thenReturn(state);
    whenListen(
      cubit,
      const Stream<ReferralState>.empty(),
      initialState: state,
    );
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
        home: MultiBlocProvider(
          providers: [
            BlocProvider<ReferralCubit>.value(value: cubit),
            BlocProvider<SettingsBloc>.value(value: settings),
          ],
          child: const ReferralGateView(),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('loading announces a live region', (tester) async {
    await pumpGate(tester, const ReferralLoading());

    expect(find.text('Empfehlungen werden geladen…'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('Empfehlungen werden geladen…'),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.liveRegion == true,
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('hides the programme when the API gate is closed', (tester) async {
    await pumpGate(tester, const ReferralNotEligible());

    expect(
      find.text(
        'Das Empfehlungsprogramm steht verifizierten Aktionären mit dem erforderlichen Bestand zur Verfügung.',
      ),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.text(
          'Das Empfehlungsprogramm steht verifizierten Aktionären mit dem erforderlichen Bestand zur Verfügung.',
        ),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.liveRegion == true,
        ),
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<AppFilledButton>(find.byType(AppFilledButton)).autofocus,
      isTrue,
    );
    expect(
      tester.widget<AppFilledButton>(find.byType(AppFilledButton)).label,
      'Schließen',
    );
  });

  testWidgets('not-eligible Close pops the gate', (tester) async {
    when(() => cubit.state).thenReturn(const ReferralNotEligible());
    whenListen(
      cubit,
      const Stream<ReferralState>.empty(),
      initialState: const ReferralNotEligible(),
    );

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => TextButton(
            onPressed: () => context.push('/referral'),
            child: const Text('go'),
          ),
          routes: [
            GoRoute(
              path: 'referral',
              builder: (_, _) => MultiBlocProvider(
                providers: [
                  BlocProvider<ReferralCubit>.value(value: cubit),
                  BlocProvider<SettingsBloc>.value(value: settings),
                ],
                child: const ReferralGateView(),
              ),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(
        theme: realUnitTheme,
        locale: const Locale('de'),
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        routerConfig: router,
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Schließen'), findsOneWidget);
    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();
    expect(find.text('go'), findsOneWidget);
    expect(find.text('Schließen'), findsNothing);
  });

  testWidgets('failure offers retry that reloads the summary', (tester) async {
    await pumpGate(
      tester,
      const ReferralFailure(message: referralUnavailableMessage),
    );

    expect(
      find.text(
        'Wir konnten den Code gerade nicht prüfen. Bitte versuche es später erneut.',
      ),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(
            find.text(
              'Wir konnten den Code gerade nicht prüfen. Bitte versuche es später erneut.',
            ),
          )
          .style
          ?.color,
      RealUnitColors.status.red600,
    );
    expect(
      find.ancestor(
        of: find.text(
          'Wir konnten den Code gerade nicht prüfen. Bitte versuche es später erneut.',
        ),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.liveRegion == true,
        ),
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<AppFilledButton>(find.byType(AppFilledButton)).autofocus,
      isTrue,
    );
    await tester.tap(find.byType(AppFilledButton));
    await tester.pump();
    verify(() => cubit.load()).called(1);
  });

  testWidgets('failure retry stays on the error copy while loading', (
    tester,
  ) async {
    await pumpGate(
      tester,
      const ReferralFailure(
        message: referralUnavailableMessage,
        retrying: true,
      ),
    );

    expect(
      find.text(
        'Wir konnten den Code gerade nicht prüfen. Bitte versuche es später erneut.',
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<AppFilledButton>(find.byType(AppFilledButton)).state,
      FilledButtonState.loading,
    );
    expect(
      tester.widget<AppFilledButton>(find.byType(AppFilledButton)).onPressed,
      isNull,
    );
  });

  testWidgets('leftover engine English is shown as unavailable copy', (
    tester,
  ) async {
    await pumpGate(tester, const ReferralFailure(message: 'nope'));

    expect(find.text('nope'), findsNothing);
    expect(
      find.text(
        'Wir konnten den Code gerade nicht prüfen. Bitte versuche es später erneut.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('overview is shown for an eligible, terms-accepted summary', (
    tester,
  ) async {
    await pumpGate(
      tester,
      const ReferralOverviewLoaded(
        summary: ReferralSummaryDto(
          eligible: true,
          termsAccepted: true,
          openCount: 0,
          creditedCount: 0,
          realuSum: 0,
          chfSum: 0,
        ),
        invites: [],
      ),
    );

    expect(find.text('Deine Empfehlungen'), findsOneWidget);
    expect(find.text('Einladungslink erstellen'), findsOneWidget);
  });

  testWidgets('accepting terms opens the create-invite screen', (tester) async {
    const needs = ReferralSummaryDto(
      eligible: true,
      termsAccepted: false,
      openCount: 0,
      creditedCount: 0,
      realuSum: 0,
      chfSum: 0,
    );
    const eligible = ReferralSummaryDto(
      eligible: true,
      termsAccepted: true,
      openCount: 0,
      creditedCount: 0,
      realuSum: 0,
      chfSum: 0,
    );
    when(() => cubit.state).thenReturn(const ReferralNeedsTerms(summary: needs));
    when(() => cubit.refreshOverview()).thenAnswer((_) async {});
    whenListen(
      cubit,
      Stream.fromIterable([
        const ReferralOverviewLoaded(summary: eligible, invites: []),
      ]),
      initialState: const ReferralNeedsTerms(summary: needs),
    );

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => MultiBlocProvider(
            providers: [
              BlocProvider<ReferralCubit>.value(value: cubit),
              BlocProvider<SettingsBloc>.value(value: settings),
            ],
            child: const ReferralGate(),
          ),
          routes: [
            GoRoute(
              name: SettingsRoutes.referralCreate,
              path: 'create',
              builder: (_, _) => const Text('create-invite'),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(
        theme: realUnitTheme,
        locale: const Locale('de'),
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        routerConfig: router,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('create-invite'), findsOneWidget);
  });

  testWidgets('ReferralPage loads summary through the live service', (
    tester,
  ) async {
    final service = _MockService();
    GetIt.instance.registerSingleton<RealUnitReferralService>(service);
    addTearDown(GetIt.instance.reset);
    when(() => service.getSummary()).thenAnswer(
      (_) async => const ReferralSummaryDto(
        eligible: true,
        termsAccepted: true,
        openCount: 0,
        creditedCount: 0,
        realuSum: 0,
        chfSum: 0,
      ),
    );
    when(() => service.getInvites()).thenAnswer((_) async => []);

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
        home: BlocProvider<SettingsBloc>.value(
          value: settings,
          child: const ReferralPage(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Deine Empfehlungen'), findsOneWidget);
  });

  testWidgets('accepting terms from the accepting state opens create-invite', (
    tester,
  ) async {
    const needs = ReferralSummaryDto(
      eligible: true,
      termsAccepted: false,
      openCount: 0,
      creditedCount: 0,
      realuSum: 0,
      chfSum: 0,
    );
    const eligible = ReferralSummaryDto(
      eligible: true,
      termsAccepted: true,
      openCount: 0,
      creditedCount: 0,
      realuSum: 0,
      chfSum: 0,
    );
    when(() => cubit.state).thenReturn(
      const ReferralTermsAccepting(summary: needs),
    );
    when(() => cubit.refreshOverview()).thenAnswer((_) async {});
    whenListen(
      cubit,
      Stream.fromIterable([
        const ReferralOverviewLoaded(summary: eligible, invites: []),
      ]),
      initialState: const ReferralTermsAccepting(summary: needs),
    );

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => MultiBlocProvider(
            providers: [
              BlocProvider<ReferralCubit>.value(value: cubit),
              BlocProvider<SettingsBloc>.value(value: settings),
            ],
            child: const ReferralGate(),
          ),
          routes: [
            GoRoute(
              name: SettingsRoutes.referralCreate,
              path: 'create',
              builder: (_, _) => const Text('create-invite'),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(
        theme: realUnitTheme,
        locale: const Locale('de'),
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        routerConfig: router,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('create-invite'), findsOneWidget);
  });
}
