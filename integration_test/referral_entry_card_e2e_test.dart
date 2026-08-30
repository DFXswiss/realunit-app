import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_summary_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_referral_service.dart';
import 'package:realunit_wallet/screens/referral/widgets/referral_entry_card.dart';
import 'package:realunit_wallet/setup/routing/routes/settings_routes.dart';
import 'package:realunit_wallet/styles/themes.dart';

class _MockService extends Mock implements RealUnitReferralService {}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late _MockService service;

  setUp(() {
    service = _MockService();
    GetIt.instance.registerSingleton<RealUnitReferralService>(service);
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  Future<void> pumpCard(WidgetTester tester) {
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
        home: const Scaffold(
          body: ReferralEntryCard(unavailablePollInterval: Duration.zero),
        ),
      ),
    );
  }

  testWidgets('hides the Einstiegskarte when the API gate is closed', (tester) async {
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

  testWidgets('shows the Einstiegskarte when the API says eligible', (tester) async {
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
  });

  testWidgets('taps the Einstiegskarte through to the referral route', (tester) async {
    tester.view
      ..physicalSize = const Size(800, 600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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
          path: '/settings/referral',
          name: SettingsRoutes.referral,
          builder: (_, _) => const Scaffold(body: Text('referral-page')),
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
    await tester.pumpAndSettle();

    await tester.tap(find.text('Empfehlungen'));
    await tester.pumpAndSettle();
    expect(find.text('referral-page'), findsOneWidget);
  });
}
