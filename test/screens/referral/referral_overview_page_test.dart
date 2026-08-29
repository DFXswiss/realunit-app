import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_invite_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_summary_dto.dart';
import 'package:realunit_wallet/screens/referral/cubit/referral_cubit.dart';
import 'package:realunit_wallet/screens/referral/open_referral_create.dart';
import 'package:realunit_wallet/screens/referral/referral_error_message.dart';
import 'package:realunit_wallet/screens/referral/referral_overview_page.dart';
import 'package:realunit_wallet/screens/settings/bloc/settings_bloc.dart';
import 'package:realunit_wallet/setup/routing/routes/legal_routes.dart';
import 'package:realunit_wallet/setup/routing/routes/settings_routes.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/styles/language.dart';
import 'package:realunit_wallet/styles/themes.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';

class _MockReferralCubit extends MockCubit<ReferralState>
    implements ReferralCubit {}

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

void main() {
  late _MockReferralCubit cubit;
  late _MockSettingsBloc settings;

  setUp(() {
    debugResetOpeningReferralCreate();
    cubit = _MockReferralCubit();
    settings = _MockSettingsBloc();
    const settingsState = SettingsState(language: Language.de);
    when(() => settings.state).thenReturn(settingsState);
    whenListen(
      settings,
      const Stream<SettingsState>.empty(),
      initialState: settingsState,
    );
  });

  testWidgets(
    'shows counts, Aktienkurs, and copy/share for open invites only',
    (tester) async {
      const summary = ReferralSummaryDto(
        eligible: true,
        termsAccepted: true,
        openCount: 3,
        creditedCount: 2,
        realuSum: 40,
        chfSum: 512.4,
        sharePriceLabel: 'Aktienkurs',
      );
      final invites = [
        ReferralInviteDto(
          id: 1,
          code: 'AAAA',
          url: 'https://realunit.app/invite/AAAA',
          guestName: 'AliceShouldNotAppear',
          status: 'Open',
          created: DateTime.utc(2026, 8, 1),
        ),
        ReferralInviteDto(
          id: 2,
          code: 'BBBB',
          url: 'https://realunit.app/invite/BBBB',
          guestName: 'BobShouldNotAppear',
          status: 'Credited',
          created: DateTime.utc(2026, 8, 2),
        ),
      ];
      when(() => cubit.state).thenReturn(
        ReferralOverviewLoaded(summary: summary, invites: invites),
      );
      whenListen(
        cubit,
        const Stream<ReferralState>.empty(),
        initialState: ReferralOverviewLoaded(summary: summary, invites: invites),
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
              child: const ReferralOverviewPage(),
            ),
            routes: [
              GoRoute(
                name: SettingsRoutes.referralCreate,
                path: 'create',
                builder: (_, _) => const SizedBox.shrink(),
              ),
            ],
          ),
        ],
      );

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

      expect(find.text('3'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('Offen'), findsOneWidget);
      expect(find.text('Gutgeschrieben'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.label == '3 Offen',
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label == '2 Gutgeschrieben',
        ),
        findsOneWidget,
      );
      expect(find.text('Deine Empfehlungen'), findsOneWidget);
      expect(find.text('INSGESAMT ERHALTEN'), findsOneWidget);
      expect(find.textContaining('Aktienkurs'), findsOneWidget);
      expect(find.text('Offene Einladungen verfallen nach 3 Monaten.'), findsOneWidget);
      expect(find.text('Deine Einladung für AliceShouldNotAppear'), findsOneWidget);
      expect(find.text('Persönlicher Einladungslink'), findsOneWidget);
      expect(
        find.text(
          'Hey AliceShouldNotAppear, RealUnit lädt dich ein zu RealUnit: https://realunit.app/invite/AAAA',
        ),
        findsOneWidget,
      );
      expect(find.text('Einladungslink kopieren'), findsOneWidget);
      expect(find.text('Einladungslink versenden'), findsOneWidget);
      expect(
        tester
            .widget<AppFilledButton>(
              find.widgetWithText(AppFilledButton, 'Einladungslink erstellen'),
            )
            .autofocus,
        isFalse,
      );
      expect(find.text('BobShouldNotAppear'), findsNothing);
      expect(find.text('Bound'), findsNothing);
      expect(find.text('Verifiziert'), findsNothing);
    },
  );

  testWidgets(
    'empty or NAV sharePriceLabel shows localized Aktienkurs',
    (tester) async {
      const summary = ReferralSummaryDto(
        eligible: true,
        termsAccepted: true,
        openCount: 0,
        creditedCount: 0,
        realuSum: 20.9,
        chfSum: 246.5,
        sharePriceLabel: 'aktueller NAV',
      );
      when(() => cubit.state).thenReturn(
        const ReferralOverviewLoaded(summary: summary, invites: []),
      );
      whenListen(
        cubit,
        const Stream<ReferralState>.empty(),
        initialState: const ReferralOverviewLoaded(
          summary: summary,
          invites: [],
        ),
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
            child: const ReferralOverviewPage(),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('Aktienkurs'), findsOneWidget);
      expect(find.textContaining('NAV'), findsNothing);
      expect(find.text('20 REALU'), findsOneWidget);
      expect(find.text('21 REALU'), findsNothing);
      expect(
        tester
            .widget<AppFilledButton>(
              find.widgetWithText(AppFilledButton, 'Einladungslink erstellen'),
            )
            .autofocus,
        isTrue,
      );
    },
  );

  testWidgets(
    'API Aktienkurs token localizes to Share price in English',
    (tester) async {
      const enSettings = SettingsState(language: Language.en);
      when(() => settings.state).thenReturn(enSettings);
      whenListen(
        settings,
        const Stream<SettingsState>.empty(),
        initialState: enSettings,
      );
      const summary = ReferralSummaryDto(
        eligible: true,
        termsAccepted: true,
        openCount: 0,
        creditedCount: 0,
        realuSum: 20,
        chfSum: 27.6,
        sharePriceLabel: 'Aktienkurs',
        sharePrice: 1.38,
      );
      when(() => cubit.state).thenReturn(
        const ReferralOverviewLoaded(summary: summary, invites: []),
      );
      whenListen(
        cubit,
        const Stream<ReferralState>.empty(),
        initialState: const ReferralOverviewLoaded(
          summary: summary,
          invites: [],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: realUnitTheme,
          locale: const Locale('en'),
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
            child: const ReferralOverviewPage(),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('Share price'), findsOneWidget);
      expect(find.textContaining('Aktienkurs'), findsNothing);
      expect(find.textContaining('NAV'), findsNothing);
    },
  );

  testWidgets(
    'total tile uses running Aktienkurs when sharePrice is present',
    (tester) async {
      const summary = ReferralSummaryDto(
        eligible: true,
        termsAccepted: true,
        openCount: 0,
        creditedCount: 2,
        realuSum: 40,
        chfSum: 512.4,
        sharePriceLabel: 'Aktienkurs',
        sharePrice: 1.38,
      );
      when(() => cubit.state).thenReturn(
        const ReferralOverviewLoaded(summary: summary, invites: []),
      );
      whenListen(
        cubit,
        const Stream<ReferralState>.empty(),
        initialState: const ReferralOverviewLoaded(
          summary: summary,
          invites: [],
        ),
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
            child: const ReferralOverviewPage(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('40 REALU'), findsOneWidget);
      expect(find.textContaining('Aktienkurs'), findsOneWidget);
      expect(find.textContaining('512'), findsNothing);
      expect(find.textContaining('55'), findsWidgets);
    },
  );

  testWidgets('shows an open invite with a blank guest name for copy/share', (
    tester,
  ) async {
    const summary = ReferralSummaryDto(
      eligible: true,
      termsAccepted: true,
      openCount: 1,
      creditedCount: 0,
      realuSum: 0,
      chfSum: 0,
    );
    final invites = [
      ReferralInviteDto(
        id: 1,
        code: 'AAAA',
        url: 'https://realunit.app/invite/AAAA',
        guestName: '   ',
        status: 'Open',
        created: DateTime.utc(2026, 8, 1),
      ),
    ];
    when(() => cubit.state).thenReturn(
      ReferralOverviewLoaded(summary: summary, invites: invites),
    );
    whenListen(
      cubit,
      const Stream<ReferralState>.empty(),
      initialState: ReferralOverviewLoaded(summary: summary, invites: invites),
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
            child: const ReferralOverviewPage(),
          ),
          routes: [
            GoRoute(
              name: SettingsRoutes.referralCreate,
              path: 'create',
              builder: (_, _) => const SizedBox.shrink(),
            ),
          ],
        ),
      ],
    );

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

    expect(find.text('Deine Einladung'), findsOneWidget);
    expect(find.textContaining('Deine Einladung für'), findsNothing);
    expect(find.text('Einladungslink kopieren'), findsOneWidget);
    expect(find.text('Hey ,'), findsNothing);
    expect(
      find.text('RealUnit lädt dich ein zu RealUnit: https://realunit.app/invite/AAAA'),
      findsOneWidget,
    );
    expect(find.text('Wiederholen'), findsNothing);
  });

  testWidgets(
    'renders two nameless open invites that share a missing id',
    (tester) async {
      const summary = ReferralSummaryDto(
        eligible: true,
        termsAccepted: true,
        openCount: 2,
        creditedCount: 0,
        realuSum: 0,
        chfSum: 0,
      );
      final invites = [
        ReferralInviteDto(
          id: 0,
          code: 'AAAA',
          url: 'https://realunit.app/invite/AAAA',
          guestName: '',
          status: 'Open',
          created: DateTime.utc(2026, 8, 1),
        ),
        ReferralInviteDto(
          id: 0,
          code: 'BBBB',
          url: 'https://realunit.app/invite/BBBB',
          guestName: '',
          status: 'Open',
          created: DateTime.utc(2026, 8, 2),
        ),
      ];
      when(() => cubit.state).thenReturn(
        ReferralOverviewLoaded(summary: summary, invites: invites),
      );
      whenListen(
        cubit,
        const Stream<ReferralState>.empty(),
        initialState: ReferralOverviewLoaded(summary: summary, invites: invites),
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
            child: const ReferralOverviewPage(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Deine Einladung'), findsNWidgets(2));
      expect(find.text('Einladungslink kopieren'), findsNWidgets(2));
    },
  );

  testWidgets('copy writes the open invite URL to the clipboard', (tester) async {
    String? copied;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });

    const summary = ReferralSummaryDto(
      eligible: true,
      termsAccepted: true,
      openCount: 1,
      creditedCount: 0,
      realuSum: 0,
      chfSum: 0,
    );
    final invites = [
      ReferralInviteDto(
        id: 1,
        code: 'AAAA',
        url: 'https://realunit.app/invite/AAAA',
        guestName: 'Alice',
        status: 'Open',
        created: DateTime.utc(2026, 8, 1),
      ),
    ];
    when(() => cubit.state).thenReturn(
      ReferralOverviewLoaded(summary: summary, invites: invites),
    );
    whenListen(
      cubit,
      const Stream<ReferralState>.empty(),
      initialState: ReferralOverviewLoaded(summary: summary, invites: invites),
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
            child: const ReferralOverviewPage(),
          ),
          routes: [
            GoRoute(
              name: SettingsRoutes.referralCreate,
              path: 'create',
              builder: (_, _) => const SizedBox.shrink(),
            ),
          ],
        ),
      ],
    );

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
    expect(
      find.ancestor(
        of: find.text('Einladungslink kopieren'),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.liveRegion == true,
        ),
      ),
      findsNothing,
    );
    await tester.tap(find.text('Einladungslink kopieren'));
    await tester.pump();

    expect(
      copied,
      'Hey Alice, RealUnit lädt dich ein zu RealUnit: https://realunit.app/invite/AAAA',
    );
    expect(find.text('Kopiert'), findsOneWidget);
    expect(find.text('In die Zwischenablage kopiert'), findsNothing);
    expect(
      tester
          .widget<Semantics>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is Semantics &&
                  widget.properties.liveRegion == true &&
                  (widget.properties.label ?? '').contains('AAAA'),
            ),
          )
          .properties
          .label,
      contains('https://realunit.app/invite/AAAA'),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Einladungslink kopieren'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('Einladungslink kopieren'),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.liveRegion == true,
        ),
      ),
      findsNothing,
    );
  });

  testWidgets('copy fallback names the Empfehler from inviterName', (
    tester,
  ) async {
    String? copied;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });

    const summary = ReferralSummaryDto(
      eligible: true,
      termsAccepted: true,
      openCount: 1,
      creditedCount: 0,
      realuSum: 0,
      chfSum: 0,
    );
    final invites = [
      ReferralInviteDto(
        id: 1,
        code: 'AAAA',
        url: 'https://realunit.app/invite/AAAA',
        guestName: 'Alice',
        status: 'Open',
        created: DateTime.utc(2026, 8, 1),
        inviterName: 'Björn',
      ),
    ];
    when(() => cubit.state).thenReturn(
      ReferralOverviewLoaded(summary: summary, invites: invites),
    );
    whenListen(
      cubit,
      const Stream<ReferralState>.empty(),
      initialState: ReferralOverviewLoaded(summary: summary, invites: invites),
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
            child: const ReferralOverviewPage(),
          ),
          routes: [
            GoRoute(
              name: SettingsRoutes.referralCreate,
              path: 'create',
              builder: (_, _) => const SizedBox.shrink(),
            ),
          ],
        ),
      ],
    );

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
    await tester.tap(find.text('Einladungslink kopieren'));
    await tester.pump();

    expect(
      copied,
      'Hey Alice, Björn lädt dich ein zu RealUnit: https://realunit.app/invite/AAAA',
    );
  });

  testWidgets('overview title opens the Teilnahmebedingungen after accept', (
    tester,
  ) async {
    const summary = ReferralSummaryDto(
      eligible: true,
      termsAccepted: true,
      openCount: 0,
      creditedCount: 0,
      realuSum: 0,
      chfSum: 0,
    );
    when(() => cubit.state).thenReturn(
      ReferralOverviewLoaded(summary: summary, invites: const []),
    );
    whenListen(
      cubit,
      const Stream<ReferralState>.empty(),
      initialState: ReferralOverviewLoaded(
        summary: summary,
        invites: const [],
      ),
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
            child: const ReferralOverviewPage(),
          ),
          routes: [
            GoRoute(
              name: SettingsRoutes.referralCreate,
              path: 'create',
              builder: (_, _) => const SizedBox.shrink(),
            ),
          ],
        ),
        GoRoute(
          name: LegalRoutes.referralTerms,
          path: '/referralTerms',
          builder: (_, _) => const Text('tb'),
        ),
      ],
    );

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
    await tester.tap(find.text('Deine Empfehlungen'));
    await tester.pumpAndSettle();
    expect(find.text('tb'), findsOneWidget);
  });

  testWidgets('share uses the API copyText 1:1', (tester) async {
    String? shared;
    String? subject;
    String? title;
    const channel = MethodChannel('dev.fluttercommunity.plus/share');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        if (call.method == 'share') {
          final args = call.arguments;
          if (args is Map) {
            shared = args['text'] as String?;
            subject = args['subject'] as String?;
            title = args['title'] as String?;
          }
        }
        return '';
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    });

    const summary = ReferralSummaryDto(
      eligible: true,
      termsAccepted: true,
      openCount: 1,
      creditedCount: 0,
      realuSum: 0,
      chfSum: 0,
    );
    final invites = [
      ReferralInviteDto(
        id: 1,
        code: 'AAAA',
        url: 'https://realunit.app/invite/AAAA',
        guestName: 'Alice',
        status: 'Open',
        created: DateTime.utc(2026, 8, 1),
        copyText: 'Hey Alice, Björn lädt dich ein: https://realunit.app/invite/AAAA',
      ),
    ];
    when(() => cubit.state).thenReturn(
      ReferralOverviewLoaded(summary: summary, invites: invites),
    );
    whenListen(
      cubit,
      const Stream<ReferralState>.empty(),
      initialState: ReferralOverviewLoaded(summary: summary, invites: invites),
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
            child: const ReferralOverviewPage(),
          ),
          routes: [
            GoRoute(
              name: SettingsRoutes.referralCreate,
              path: 'create',
              builder: (_, _) => const SizedBox.shrink(),
            ),
          ],
        ),
      ],
    );

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
    expect(
      find.text(
        'Hey Alice, Björn lädt dich ein: https://realunit.app/invite/AAAA',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Einladungslink versenden'));
    await tester.pump();

    expect(
      shared,
      'Hey Alice, Björn lädt dich ein: https://realunit.app/invite/AAAA',
    );
    expect(subject, 'Persönlicher Einladungslink');
    expect(title, 'Persönlicher Einladungslink');
  });

  testWidgets('hides received REALU and CHF when amounts are hidden', (tester) async {
    const hidden = SettingsState(language: Language.de, hideAmounts: true);
    when(() => settings.state).thenReturn(hidden);
    whenListen(
      settings,
      const Stream<SettingsState>.empty(),
      initialState: hidden,
    );

    const summary = ReferralSummaryDto(
      eligible: true,
      termsAccepted: true,
      openCount: 0,
      creditedCount: 0,
      realuSum: 40,
      chfSum: 512.4,
      sharePriceLabel: 'Aktienkurs',
    );
    when(() => cubit.state).thenReturn(
      const ReferralOverviewLoaded(summary: summary, invites: []),
    );
    whenListen(
      cubit,
      const Stream<ReferralState>.empty(),
      initialState: const ReferralOverviewLoaded(summary: summary, invites: []),
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
            child: const ReferralOverviewPage(),
          ),
          routes: [
            GoRoute(
              name: SettingsRoutes.referralCreate,
              path: 'create',
              builder: (_, _) => const SizedBox.shrink(),
            ),
          ],
        ),
      ],
    );

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

    expect(find.text('40 REALU'), findsNothing);
    expect(find.text('*** REALU'), findsOneWidget);
    expect(find.textContaining('512'), findsNothing);
    expect(find.textContaining('***.**'), findsOneWidget);
  });

  testWidgets(
    'offers retry when openCount is set but no open-invite rows loaded',
    (tester) async {
      const summary = ReferralSummaryDto(
        eligible: true,
        termsAccepted: true,
        openCount: 2,
        creditedCount: 0,
        realuSum: 0,
        chfSum: 0,
      );
      when(() => cubit.state).thenReturn(
        const ReferralOverviewLoaded(
          summary: summary,
          invites: [],
          invitesError: referralUnavailableMessage,
        ),
      );
      whenListen(
        cubit,
        const Stream<ReferralState>.empty(),
        initialState: const ReferralOverviewLoaded(
          summary: summary,
          invites: [],
          invitesError: referralUnavailableMessage,
        ),
      );
      when(() => cubit.reloadInvites()).thenAnswer((_) async {});

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
              child: const ReferralOverviewPage(),
            ),
            routes: [
              GoRoute(
                name: SettingsRoutes.referralCreate,
                path: 'create',
                builder: (_, _) => const SizedBox.shrink(),
              ),
            ],
          ),
        ],
      );

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

      expect(
        find.text(
          'Wir konnten den Code gerade nicht prüfen. Bitte versuche es später erneut.',
        ),
        findsOneWidget,
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
      expect(find.text('Wiederholen'), findsOneWidget);
      expect(
        tester
            .widget<AppFilledButton>(
              find.widgetWithText(AppFilledButton, 'Wiederholen'),
            )
            .autofocus,
        isTrue,
      );
      await tester.tap(find.text('Wiederholen'));
      await tester.pump();
      verify(() => cubit.reloadInvites()).called(1);
    },
  );

  testWidgets(
    'offers retry when a list error is shown beside existing open invites',
    (tester) async {
      const summary = ReferralSummaryDto(
        eligible: true,
        termsAccepted: true,
        openCount: 1,
        creditedCount: 0,
        realuSum: 0,
        chfSum: 0,
      );
      final invites = [
        ReferralInviteDto(
          id: 1,
          code: 'AAAA',
          url: 'https://realunit.app/invite/AAAA',
          guestName: 'Alice',
          status: 'Open',
          created: DateTime.utc(2026, 8, 1),
        ),
      ];
      when(() => cubit.state).thenReturn(
        ReferralOverviewLoaded(
          summary: summary,
          invites: invites,
          invitesError: referralUnavailableMessage,
        ),
      );
      whenListen(
        cubit,
        const Stream<ReferralState>.empty(),
        initialState: ReferralOverviewLoaded(
          summary: summary,
          invites: invites,
          invitesError: referralUnavailableMessage,
        ),
      );
      when(() => cubit.reloadInvites()).thenAnswer((_) async {});

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
            child: const ReferralOverviewPage(),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.text(
          'Wir konnten den Code gerade nicht prüfen. Bitte versuche es später erneut.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Deine Einladung für Alice'), findsOneWidget);
      expect(find.text('Wiederholen'), findsOneWidget);
      expect(
        tester
            .widget<AppFilledButton>(
              find.widgetWithText(AppFilledButton, 'Wiederholen'),
            )
            .autofocus,
        isFalse,
      );
      await tester.ensureVisible(find.text('Wiederholen'));
      await tester.tap(find.text('Wiederholen'));
      await tester.pump();
      verify(() => cubit.reloadInvites()).called(1);
    },
  );

  testWidgets(
    'offers retry when the invite list errors and openCount is zero',
    (tester) async {
      const summary = ReferralSummaryDto(
        eligible: true,
        termsAccepted: true,
        openCount: 0,
        creditedCount: 2,
        realuSum: 0,
        chfSum: 0,
      );
      when(() => cubit.state).thenReturn(
        const ReferralOverviewLoaded(
          summary: summary,
          invites: [],
          invitesError: referralUnavailableMessage,
        ),
      );
      whenListen(
        cubit,
        const Stream<ReferralState>.empty(),
        initialState: const ReferralOverviewLoaded(
          summary: summary,
          invites: [],
          invitesError: referralUnavailableMessage,
        ),
      );
      when(() => cubit.reloadInvites()).thenAnswer((_) async {});

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
            child: const ReferralOverviewPage(),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.text(
          'Wir konnten den Code gerade nicht prüfen. Bitte versuche es später erneut.',
        ),
        findsOneWidget,
      );
      expect(find.text('Wiederholen'), findsOneWidget);
      expect(
        tester
            .widget<AppFilledButton>(
              find.widgetWithText(AppFilledButton, 'Wiederholen'),
            )
            .autofocus,
        isTrue,
      );
      expect(
        tester
            .widget<AppFilledButton>(
              find.widgetWithText(AppFilledButton, 'Einladungslink erstellen'),
            )
            .autofocus,
        isFalse,
      );
      await tester.tap(find.text('Wiederholen'));
      await tester.pump();
      verify(() => cubit.reloadInvites()).called(1);
    },
  );

  testWidgets(
    'keeps the invites error while the list reload is in flight',
    (tester) async {
      const summary = ReferralSummaryDto(
        eligible: true,
        termsAccepted: true,
        openCount: 2,
        creditedCount: 0,
        realuSum: 0,
        chfSum: 0,
      );
      when(() => cubit.state).thenReturn(
        const ReferralOverviewLoaded(
          summary: summary,
          invites: [],
          invitesError: referralUnavailableMessage,
          invitesLoading: true,
        ),
      );
      whenListen(
        cubit,
        const Stream<ReferralState>.empty(),
        initialState: const ReferralOverviewLoaded(
          summary: summary,
          invites: [],
          invitesError: referralUnavailableMessage,
          invitesLoading: true,
        ),
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
            child: const ReferralOverviewPage(),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.text(
          'Wir konnten den Code gerade nicht prüfen. Bitte versuche es später erneut.',
        ),
        findsOneWidget,
      );
      expect(find.text('Offene Einladungen werden geladen…'), findsNothing);
      expect(
        tester
            .widget<AppFilledButton>(
              find.widgetWithText(AppFilledButton, 'Wiederholen'),
            )
            .state,
        FilledButtonState.loading,
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
    },
  );

  testWidgets('failure announces a live region and offers retry', (tester) async {
    when(() => cubit.state).thenReturn(
      const ReferralFailure(message: referralUnavailableMessage),
    );
    whenListen(
      cubit,
      const Stream<ReferralState>.empty(),
      initialState: const ReferralFailure(message: referralUnavailableMessage),
    );
    when(() => cubit.load()).thenAnswer((_) async {});

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
          child: const ReferralOverviewPage(),
        ),
      ),
    );
    await tester.pump();

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
    await tester.tap(find.text('Wiederholen'));
    await tester.pump();
    verify(() => cubit.load()).called(1);
  });

  testWidgets('failure retry stays on the error copy while loading', (
    tester,
  ) async {
    when(
      () => cubit.state,
    ).thenReturn(
      const ReferralFailure(message: referralUnavailableMessage, retrying: true),
    );
    whenListen(
      cubit,
      const Stream<ReferralState>.empty(),
      initialState: const ReferralFailure(
        message: referralUnavailableMessage,
        retrying: true,
      ),
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
          child: const ReferralOverviewPage(),
        ),
      ),
    );
    await tester.pump();

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

  testWidgets(
    'announces invite-list loading without dropping the overview tiles',
    (tester) async {
      const summary = ReferralSummaryDto(
        eligible: true,
        termsAccepted: true,
        openCount: 2,
        creditedCount: 1,
        realuSum: 20,
        chfSum: 246.5,
      );
      when(() => cubit.state).thenReturn(
        const ReferralOverviewLoaded(
          summary: summary,
          invites: [],
          invitesLoading: true,
        ),
      );
      whenListen(
        cubit,
        const Stream<ReferralState>.empty(),
        initialState: const ReferralOverviewLoaded(
          summary: summary,
          invites: [],
          invitesLoading: true,
        ),
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
            child: const ReferralOverviewPage(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Offene Einladungen werden geladen…'), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text('Offene Einladungen werden geladen…'),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && widget.properties.liveRegion == true,
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('2'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('Einladungslink erstellen'), findsOneWidget);
    },
  );

  testWidgets(
    'create CTA pushes the invite form and refreshes after a created invite',
    (tester) async {
      const summary = ReferralSummaryDto(
        eligible: true,
        termsAccepted: true,
        openCount: 0,
        creditedCount: 0,
        realuSum: 0,
        chfSum: 0,
      );
      when(() => cubit.state).thenReturn(
        const ReferralOverviewLoaded(summary: summary, invites: []),
      );
      whenListen(
        cubit,
        const Stream<ReferralState>.empty(),
        initialState: const ReferralOverviewLoaded(
          summary: summary,
          invites: [],
        ),
      );
      when(() => cubit.refreshOverview()).thenAnswer((_) async {});

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
              child: const ReferralOverviewPage(),
            ),
            routes: [
              GoRoute(
                name: SettingsRoutes.referralCreate,
                path: 'create',
                builder: (context, _) => TextButton(
                  onPressed: () => context.pop(true),
                  child: const Text('created'),
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
      await tester.pump();
      await tester.tap(find.text('Einladungslink erstellen'));
      await tester.pumpAndSettle();
      expect(find.text('created'), findsOneWidget);
      await tester.tap(find.text('created'));
      await tester.pumpAndSettle();
      verify(() => cubit.refreshOverview()).called(1);
    },
  );

  testWidgets(
    'create CTA ignores a second tap while the create route is opening',
    (tester) async {
      const summary = ReferralSummaryDto(
        eligible: true,
        termsAccepted: true,
        openCount: 0,
        creditedCount: 0,
        realuSum: 0,
        chfSum: 0,
      );
      when(() => cubit.state).thenReturn(
        const ReferralOverviewLoaded(summary: summary, invites: []),
      );
      whenListen(
        cubit,
        const Stream<ReferralState>.empty(),
        initialState: const ReferralOverviewLoaded(
          summary: summary,
          invites: [],
        ),
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
              child: const ReferralOverviewPage(),
            ),
            routes: [
              GoRoute(
                name: SettingsRoutes.referralCreate,
                path: 'create',
                builder: (_, _) => const Text('create-form'),
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
      final button = tester.widget<AppFilledButton>(
        find.widgetWithText(AppFilledButton, 'Einladungslink erstellen'),
      );
      button.onPressed?.call();
      button.onPressed?.call();
      await tester.pumpAndSettle();
      expect(find.text('create-form'), findsOneWidget);
    },
  );
}
