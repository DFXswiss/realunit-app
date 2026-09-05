import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/biometric_service.dart';
import 'package:realunit_wallet/screens/pin/verify_pin_page.dart';
import 'package:realunit_wallet/screens/settings_security/cubits/settings_security_cubit.dart';
import 'package:realunit_wallet/screens/settings_security/settings_security_page.dart';
import 'package:realunit_wallet/setup/routing/routes/pin_routes.dart';
import 'package:realunit_wallet/setup/routing/routes/settings_routes.dart';

class _MockSettingsSecurityCubit extends MockCubit<SettingsSecurityState>
    implements SettingsSecurityCubit {}

class _MockBiometricService extends Mock implements BiometricService {}

void main() {
  late SettingsSecurityCubit cubit;
  late List<String> pushedRoutes;
  VerifyPinParams? gateParams;
  ChangePinParams? changePinParams;

  setUpAll(() {
    final getIt = GetIt.instance;
    if (!getIt.isRegistered<BiometricService>()) {
      final service = _MockBiometricService();
      when(() => service.isAvailable()).thenAnswer((_) async => false);
      when(() => service.isEnabled()).thenAnswer((_) async => false);
      getIt.registerSingleton<BiometricService>(service);
    }
  });

  setUp(() {
    cubit = _MockSettingsSecurityCubit();
    when(() => cubit.state).thenReturn(const SettingsSecurityState());
    when(() => cubit.toggleBiometrics(enabled: any(named: 'enabled')))
        .thenAnswer((_) async {});
    pushedRoutes = <String>[];
    gateParams = null;
    changePinParams = null;
  });

  GoRouter buildRouter() => GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => BlocProvider<SettingsSecurityCubit>.value(
          value: cubit,
          child: const SettingsSecurityView(),
        ),
      ),
      GoRoute(
        name: PinRoutes.gate,
        path: '/pinGate',
        builder: (_, state) {
          pushedRoutes.add(PinRoutes.gate);
          gateParams = state.extra as VerifyPinParams;
          return const Scaffold(body: Text('GATE'));
        },
      ),
      GoRoute(
        name: SettingsRoutes.changePin,
        path: '/settings/security/changePin',
        builder: (_, state) {
          pushedRoutes.add(SettingsRoutes.changePin);
          changePinParams = state.extra as ChangePinParams;
          return const Scaffold(body: Text('CHANGE_PIN'));
        },
      ),
    ],
  );

  Future<void> pumpView(WidgetTester tester, {bool settle = true}) async {
    final router = buildRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      // The busy state renders a CupertinoActivityIndicator whose animation
      // never settles, so advance past the initial route without settling.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
    }
  }

  group('$SettingsSecurityPage', () {
    testWidgets('builds $SettingsSecurityView through DI', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: S.delegate.supportedLocales,
          home: const SettingsSecurityPage(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SettingsSecurityView), findsOne);
    });
  });

  group('$SettingsSecurityView biometric tile visibility', () {
    testWidgets('hidden when biometrics are not supported', (tester) async {
      when(() => cubit.state).thenReturn(const SettingsSecurityState());
      await pumpView(tester);

      expect(find.text(S.current.settingsChangePin), findsOneWidget);
      expect(find.text(S.current.settingsBiometricUnlock), findsNothing);
    });

    testWidgets('shown as an on switch when supported and enabled', (tester) async {
      when(() => cubit.state).thenReturn(
        const SettingsSecurityState(biometricSupported: true, biometricEnabled: true),
      );
      await pumpView(tester);

      expect(find.text(S.current.settingsBiometricUnlock), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    });

    testWidgets('shows a spinner instead of the switch while busy', (tester) async {
      when(() => cubit.state).thenReturn(
        const SettingsSecurityState(biometricSupported: true, isBusy: true),
      );
      await pumpView(tester, settle: false);

      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
    });
  });

  group('$SettingsSecurityView biometric toggle', () {
    testWidgets('tap while disabled requests enable', (tester) async {
      when(() => cubit.state).thenReturn(
        const SettingsSecurityState(biometricSupported: true, biometricEnabled: false),
      );
      await pumpView(tester);

      await tester.tap(find.text(S.current.settingsBiometricUnlock));
      await tester.pumpAndSettle();

      verify(() => cubit.toggleBiometrics(enabled: true)).called(1);
    });

    testWidgets('tap while enabled requests disable', (tester) async {
      when(() => cubit.state).thenReturn(
        const SettingsSecurityState(biometricSupported: true, biometricEnabled: true),
      );
      await pumpView(tester);

      await tester.tap(find.text(S.current.settingsBiometricUnlock));
      await tester.pumpAndSettle();

      verify(() => cubit.toggleBiometrics(enabled: false)).called(1);
    });

    testWidgets('surfaces a snackbar when the cubit signals an enable failure', (
      tester,
    ) async {
      whenListen(
        cubit,
        Stream.fromIterable(const [
          SettingsSecurityState(biometricSupported: true, isBusy: true),
          SettingsSecurityState(
            biometricSupported: true,
            error: SettingsSecurityError.biometricEnableFailed,
          ),
        ]),
        initialState: const SettingsSecurityState(biometricSupported: true),
      );
      await pumpView(tester);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text(S.current.settingsBiometricUnlockFailed), findsOneWidget);
    });
  });

  group('$SettingsSecurityView change-PIN flow', () {
    testWidgets(
      'PIN tile → gate; onAuthenticated pushes changePin; onCompleted pops + success snackbar',
      (tester) async {
        when(() => cubit.state).thenReturn(const SettingsSecurityState());
        await pumpView(tester);

        await tester.tap(find.text(S.current.settingsChangePin));
        await tester.pumpAndSettle();

        expect(pushedRoutes, [PinRoutes.gate]);
        expect(gateParams, isNotNull);
        expect(
          gateParams!.description,
          S.current.settingsChangePinVerifyDescription,
        );

        // Simulate a successful PIN/biometric re-auth at the gate.
        gateParams!.onAuthenticated();
        await tester.pumpAndSettle();

        expect(pushedRoutes, [PinRoutes.gate, SettingsRoutes.changePin]);
        expect(changePinParams, isNotNull);

        // Simulate the PIN change completing.
        changePinParams!.onCompleted();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.text(S.current.pinChangeSuccess), findsOneWidget);
        expect(find.text('CHANGE_PIN'), findsNothing);
      },
    );
  });
}
