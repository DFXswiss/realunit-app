import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';
import 'package:realunit_wallet/screens/home/bloc/home_bloc.dart';
import 'package:realunit_wallet/screens/settings/bloc/settings_bloc.dart';
import 'package:realunit_wallet/screens/settings/settings_page.dart';
import 'package:realunit_wallet/setup/routing/routes/migration_routes.dart';

class MockHomeBloc extends MockBloc<HomeEvent, HomeState> implements HomeBloc {}

class MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

class _MockSoftwareWallet extends Mock implements SoftwareWallet {}

class _MockBitboxWallet extends Mock implements BitboxWallet {}

void main() {
  late MockHomeBloc homeBloc;
  late MockSettingsBloc settingsBloc;

  setUp(() {
    homeBloc = MockHomeBloc();
    settingsBloc = MockSettingsBloc();
    when(() => settingsBloc.state).thenReturn(const SettingsState());
    whenListen(
      settingsBloc,
      const Stream<SettingsState>.empty(),
      initialState: const SettingsState(),
    );
    GetIt.instance.registerSingleton<SettingsBloc>(settingsBloc);
  });

  tearDown(() async => GetIt.instance.reset());

  Future<List<String>> pumpSettings(WidgetTester tester, AWallet wallet) async {
    when(() => homeBloc.state).thenReturn(HomeState(openWallet: wallet));
    whenListen(
      homeBloc,
      const Stream<HomeState>.empty(),
      initialState: HomeState(openWallet: wallet),
    );
    final pushedRoutes = <String>[];
    final router = GoRouter(
      initialLocation: '/settings',
      routes: [
        GoRoute(
          path: '/settings',
          builder: (_, _) => BlocProvider<HomeBloc>.value(
            value: homeBloc,
            child: const SettingsPage(),
          ),
        ),
        GoRoute(
          name: MigrationRoutes.migrateBitbox,
          path: '/migrate-bitbox',
          builder: (_, _) {
            pushedRoutes.add(MigrationRoutes.migrateBitbox);
            return const Scaffold(body: Text('migration-destination'));
          },
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
      ),
    );
    await tester.pumpAndSettle();
    return pushedRoutes;
  }

  testWidgets('migration tile is visible for a software wallet', (
    tester,
  ) async {
    final wallet = _MockSoftwareWallet();
    when(() => wallet.walletType).thenReturn(WalletType.software);

    await pumpSettings(tester, wallet);

    expect(find.text(S.current.migrateBitbox), findsOneWidget);
  });

  testWidgets('migration tile is hidden for a BitBox wallet', (tester) async {
    final wallet = _MockBitboxWallet();
    when(() => wallet.walletType).thenReturn(WalletType.bitbox);

    await pumpSettings(tester, wallet);

    expect(find.text(S.current.migrateBitbox), findsNothing);
  });

  testWidgets('migration tile is hidden for a debug wallet', (tester) async {
    final wallet = DebugWallet(
      7,
      'Debug',
      '0x0000000000000000000000000000000000000001',
    );

    await pumpSettings(tester, wallet);

    expect(find.text(S.current.migrateBitbox), findsNothing);
  });

  testWidgets('tapping the software-wallet tile pushes the named migration route', (
    tester,
  ) async {
    final wallet = _MockSoftwareWallet();
    when(() => wallet.walletType).thenReturn(WalletType.software);
    final pushedRoutes = await pumpSettings(tester, wallet);
    final tile = find.text(S.current.migrateBitbox);
    await tester.ensureVisible(tile);

    await tester.tap(tile);
    await tester.pumpAndSettle();

    expect(pushedRoutes, [MigrationRoutes.migrateBitbox]);
    expect(find.text('migration-destination'), findsOneWidget);
  });
}
