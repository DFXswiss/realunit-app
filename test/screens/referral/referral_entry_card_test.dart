import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_summary_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_referral_service.dart';
import 'package:realunit_wallet/screens/referral/widgets/referral_entry_card.dart';
import 'package:realunit_wallet/styles/themes.dart';

class _MockService extends Mock implements RealUnitReferralService {}

void main() {
  late _MockService service;

  setUp(() {
    service = _MockService();
    GetIt.instance.registerSingleton<RealUnitReferralService>(service);
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  Future<void> pumpCard(
    WidgetTester tester, {
    Duration poll = Duration.zero,
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
          body: ReferralEntryCard(unavailablePollInterval: poll),
        ),
      ),
    );
  }

  testWidgets('hides the dashboard card when the API gate is closed', (tester) async {
    when(() => service.getSummary()).thenAnswer(
      (_) async => const ReferralSummaryDto(
        eligible: false,
        termsAccepted: false,
        openCount: 0,
        creditedCount: 0,
        realuSum: 0,
        chfSum: 0,
      ),
    );

    await pumpCard(tester);
    await tester.pumpAndSettle();

    expect(find.text('Empfehlungen'), findsNothing);
  });

  testWidgets('hides the dashboard card when summary is unmounted', (tester) async {
    when(() => service.getSummary()).thenThrow(
      const ApiException(
        statusCode: 404,
        code: 'NOT_FOUND',
        message: 'Cannot GET /v1/realunit/referral/summary',
      ),
    );

    await pumpCard(tester);
    await tester.pump();
    await tester.pump();

    expect(find.text('Empfehlungen'), findsNothing);
    expect(find.text('Erhalte 20 REALU pro Weiterempfehlung'), findsNothing);
  });

  testWidgets('resume reloads the gate and can open the card', (tester) async {
    var calls = 0;
    when(() => service.getSummary()).thenAnswer((_) async {
      calls++;
      if (calls <= 2) {
        throw const ApiException(
          statusCode: 404,
          code: 'NOT_FOUND',
          message: 'Cannot GET /v1/realunit/referral/summary',
        );
      }
      return const ReferralSummaryDto(
        eligible: true,
        termsAccepted: true,
        openCount: 0,
        creditedCount: 0,
        realuSum: 0,
        chfSum: 0,
      );
    });

    await pumpCard(tester);
    await tester.pump();
    await tester.pump();
    expect(find.text('Empfehlungen'), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('Empfehlungen'), findsOneWidget);
    expect(find.text('Erhalte 20 REALU pro Weiterempfehlung'), findsOneWidget);
  });

  testWidgets('popping back to this route reloads the gate', (tester) async {
    var calls = 0;
    when(() => service.getSummary()).thenAnswer((_) async {
      calls++;
      if (calls <= 2) {
        throw const ApiException(
          statusCode: 404,
          code: 'NOT_FOUND',
          message: 'Cannot GET /v1/realunit/referral/summary',
        );
      }
      return const ReferralSummaryDto(
        eligible: true,
        termsAccepted: true,
        openCount: 0,
        creditedCount: 0,
        realuSum: 0,
        chfSum: 0,
      );
    });

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(
            body: ReferralEntryCard(unavailablePollInterval: Duration.zero),
          ),
        ),
        GoRoute(
          path: '/s',
          builder: (_, _) => const Scaffold(body: Text('settings')),
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
    expect(find.text('Empfehlungen'), findsNothing);

    router.push('/s');
    await tester.pump();
    await tester.pump();
    expect(find.text('settings'), findsOneWidget);

    router.pop();
    await tester.pump();
    await tester.pump();
    expect(find.text('Empfehlungen'), findsOneWidget);
  });

  testWidgets('polls while summary is unmounted and can open the card', (
    tester,
  ) async {
    var calls = 0;
    when(() => service.getSummary()).thenAnswer((_) async {
      calls++;
      if (calls <= 2) {
        throw const ApiException(
          statusCode: 404,
          code: 'NOT_FOUND',
          message: 'Cannot GET /v1/realunit/referral/summary',
        );
      }
      return const ReferralSummaryDto(
        eligible: true,
        termsAccepted: true,
        openCount: 0,
        creditedCount: 0,
        realuSum: 0,
        chfSum: 0,
      );
    });

    await pumpCard(tester, poll: const Duration(milliseconds: 20));
    await tester.pump();
    await tester.pump();
    expect(find.text('Empfehlungen'), findsNothing);

    await tester.pump(const Duration(milliseconds: 25));
    await tester.pump();
    expect(find.text('Empfehlungen'), findsOneWidget);
    expect(find.text('Erhalte 20 REALU pro Weiterempfehlung'), findsOneWidget);
  });

  testWidgets('does not poll when the API gate is closed', (tester) async {
    when(() => service.getSummary()).thenAnswer(
      (_) async => const ReferralSummaryDto(
        eligible: false,
        termsAccepted: false,
        openCount: 0,
        creditedCount: 0,
        realuSum: 0,
        chfSum: 0,
      ),
    );

    await pumpCard(tester, poll: const Duration(milliseconds: 20));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    verify(() => service.getSummary()).called(1);
    expect(find.text('Empfehlungen'), findsNothing);
  });

  testWidgets('does not poll while another route is on top', (tester) async {
    var calls = 0;
    when(() => service.getSummary()).thenAnswer((_) async {
      calls++;
      throw const ApiException(
        statusCode: 404,
        code: 'NOT_FOUND',
        message: 'Cannot GET /v1/realunit/referral/summary',
      );
    });

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: ReferralEntryCard(
              unavailablePollInterval: const Duration(milliseconds: 20),
            ),
          ),
        ),
        GoRoute(
          path: '/s',
          builder: (_, _) => const Scaffold(body: Text('settings')),
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
    expect(calls, greaterThanOrEqualTo(1));

    router.push('/s');
    await tester.pump();
    await tester.pump();
    expect(find.text('settings'), findsOneWidget);
    final afterPush = calls;
    await tester.pump(const Duration(milliseconds: 80));
    expect(calls, afterPush);
  });

  testWidgets('does not poll while the app is paused', (tester) async {
    var calls = 0;
    when(() => service.getSummary()).thenAnswer((_) async {
      calls++;
      throw const ApiException(
        statusCode: 404,
        code: 'NOT_FOUND',
        message: 'Cannot GET /v1/realunit/referral/summary',
      );
    });

    await pumpCard(tester, poll: const Duration(milliseconds: 20));
    await tester.pump();
    await tester.pump();
    final afterLoad = calls;
    expect(afterLoad, greaterThanOrEqualTo(1));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(calls, afterLoad);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('shows the dashboard card when the API says eligible', (tester) async {
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

    await pumpCard(tester);
    await tester.pumpAndSettle();

    expect(find.text('Empfehlungen'), findsOneWidget);
    expect(find.text('Erhalte 20 REALU pro Weiterempfehlung'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ReferralEntryCard),
        matching: find.byType(ExcludeSemantics),
      ),
      findsAtLeastNWidgets(1),
    );
  });
}
