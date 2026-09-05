import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_invite_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_summary_dto.dart';
import 'package:realunit_wallet/screens/referral/cubit/referral_cubit.dart';
import 'package:realunit_wallet/screens/referral/referral_overview_page.dart';
import 'package:realunit_wallet/screens/settings/bloc/settings_bloc.dart';
import 'package:realunit_wallet/setup/routing/routes/settings_routes.dart';
import 'package:realunit_wallet/styles/language.dart';
import 'package:realunit_wallet/styles/themes.dart';

class _MockReferralCubit extends MockCubit<ReferralState> implements ReferralCubit {}

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState> implements SettingsBloc {}

const _summary = ReferralSummaryDto(
  eligible: true,
  termsAccepted: true,
  openCount: 3,
  creditedCount: 2,
  realuSum: 40,
  chfSum: 512.4,
  sharePriceLabel: 'Aktienkurs',
);

final _openInvite = ReferralInviteDto(
  id: 1,
  code: 'AAAA',
  url: 'https://realunit.app/invite/AAAA',
  guestName: 'AliceShouldNotAppear',
  status: 'Open',
  created: DateTime.utc(2026, 8, 1),
);

final _creditedInvite = ReferralInviteDto(
  id: 2,
  code: 'BBBB',
  url: 'https://realunit.app/invite/BBBB',
  guestName: 'BobShouldNotAppear',
  status: 'Credited',
  created: DateTime.utc(2026, 8, 2),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late _MockReferralCubit cubit;
  late _MockSettingsBloc settings;

  setUp(() {
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

  Future<void> pumpOverview(WidgetTester tester) async {
    when(() => cubit.state).thenReturn(
      ReferralOverviewLoaded(
        summary: _summary,
        invites: [_openInvite, _creditedInvite],
      ),
    );
    whenListen(
      cubit,
      const Stream<ReferralState>.empty(),
      initialState: ReferralOverviewLoaded(
        summary: _summary,
        invites: [_openInvite, _creditedInvite],
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
  }

  testWidgets('shows open/credited counts, REALU sum, and Aktienkurs', (tester) async {
    await pumpOverview(tester);

    expect(find.text('Offen'), findsOneWidget);
    expect(find.text('Gutgeschrieben'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('INSGESAMT ERHALTEN'), findsOneWidget);
    expect(find.text('40 REALU'), findsOneWidget);
    expect(find.textContaining('Aktienkurs'), findsOneWidget);
    expect(find.text('Deine Einladung für AliceShouldNotAppear'), findsOneWidget);
    expect(find.text('BobShouldNotAppear'), findsNothing);
  });

  testWidgets('hides received REALU and CHF when amounts are hidden', (tester) async {
    const hidden = SettingsState(language: Language.de, hideAmounts: true);
    when(() => settings.state).thenReturn(hidden);
    whenListen(
      settings,
      const Stream<SettingsState>.empty(),
      initialState: hidden,
    );

    await pumpOverview(tester);

    expect(find.text('*** REALU'), findsOneWidget);
    expect(find.text('40 REALU'), findsNothing);
    expect(find.textContaining('Aktienkurs'), findsOneWidget);
  });
}
