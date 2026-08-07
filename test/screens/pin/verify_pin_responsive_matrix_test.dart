// Responsive matrix gate for VerifyPinView keypad + Forgot-PIN CTA.
//
// Proves digit keys and the Forgot-PIN action stay fully tappable across the
// full device × text-scale matrix (see test/helper/responsive_matrix.dart).
// Regression lock for the IntrinsicHeight + Spacer collapse that pushed the
// NumberPad / Forgot-PIN control below the viewport on first frame.
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/biometric_service.dart';
import 'package:realunit_wallet/packages/storage/secure_storage.dart';
import 'package:realunit_wallet/screens/pin/bloc/auth/pin_auth_cubit.dart';
import 'package:realunit_wallet/screens/pin/bloc/verify_pin/verify_pin_cubit.dart';
import 'package:realunit_wallet/screens/pin/verify_pin_page.dart';
import 'package:realunit_wallet/widgets/buttons/app_text_button.dart';
import 'package:realunit_wallet/widgets/number_pad.dart';

import '../../helper/helper.dart';

class MockVerifyPinCubit extends MockCubit<VerifyPinState>
    implements VerifyPinCubit {}

class MockPinAuthCubit extends MockCubit<PinAuthState> implements PinAuthCubit {}

class MockSecureStorage extends Mock implements SecureStorage {}

class MockBiometricService extends Mock implements BiometricService {}

void main() {
  late VerifyPinCubit verifyPinCubit;
  late PinAuthCubit pinAuthCubit;

  void setupDependencyInjection() {
    final getIt = GetIt.instance;
    final secureStorage = MockSecureStorage();
    when(() => secureStorage.getPinLockedUntil()).thenAnswer((_) => Future.value(null));
    when(() => secureStorage.getPinFailedAttempts()).thenAnswer((_) => Future.value(0));
    getIt.registerSingleton<SecureStorage>(secureStorage);
    final biometricService = MockBiometricService();
    when(() => biometricService.isEnabled()).thenAnswer((_) => Future.value(false));
    when(() => biometricService.isAvailable()).thenAnswer((_) => Future.value(false));
    getIt.registerSingleton<BiometricService>(biometricService);
    getIt.registerSingleton<PinAuthCubit>(pinAuthCubit);
  }

  setUpAll(() {
    pinAuthCubit = MockPinAuthCubit();
    when(() => pinAuthCubit.state).thenReturn(const PinAuthState());
    when(() => pinAuthCubit.onPinVerified()).thenAnswer((_) => Future.value());
    setupDependencyInjection();
  });

  tearDownAll(() async => await GetIt.instance.reset());

  setUp(() {
    verifyPinCubit = MockVerifyPinCubit();
    when(() => verifyPinCubit.state).thenReturn(const VerifyPinState());
    when(() => verifyPinCubit.checkBiometricAvailability()).thenAnswer((_) => Future.value());
    whenListen(
      verifyPinCubit,
      const Stream<VerifyPinState>.empty(),
      initialState: const VerifyPinState(),
    );
  });

  Future<void> pumpScreen(
    WidgetTester tester,
    MatrixCell cell, {
    required Widget page,
  }) async {
    await tester.binding.setSurfaceSize(cell.mediaQuery.size);
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      MediaQuery(
        data: cell.mediaQuery,
        child: MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: const [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: S.delegate.supportedLocales,
          home: page,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// [VerifyPinPage] builds its own cubit; for matrix layout we host
  /// [VerifyPinView] under a mock cubit so state is deterministic.
  Widget appLockView() => MultiBlocProvider(
    providers: [
      BlocProvider.value(value: verifyPinCubit),
      BlocProvider.value(value: pinAuthCubit),
    ],
    child: VerifyPinView(
      onAuthenticated: () {},
      // Mirrors VerifyPinPage.appLock()'s bottom so Forgot-PIN is present.
      bottom: Builder(
        builder: (context) => Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: SizedBox(
            height: 52.0,
            child: AppTextButton(
              fullWidth: false,
              onPressed: () async {
                await showModalBottomSheet<bool>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const SizedBox(
                    height: 200,
                    child: Center(child: Text('forgot-pin-sheet')),
                  ),
                );
              },
              label: S.of(context).pinForgotten,
            ),
          ),
        ),
      ),
    ),
  );

  Widget gateView() => BlocProvider.value(
    value: verifyPinCubit,
    child: VerifyPinView(onAuthenticated: () {}),
  );

  group('VerifyPinView.appLock responsive matrix (keypad + Forgot-PIN)', () {
    for (final cell in kFullResponsiveMatrix) {
      testWidgets('appLock · ${cell.id}', (tester) async {
        await withTargetPlatform(cell.device.platform, () async {
          await expectNoLayoutOverflow(
            tester,
            () async {
              await pumpScreen(tester, cell, page: appLockView());
            },
            reason: 'overflow on appLock / ${cell.label}',
          );

          expect(find.byType(NumberPad), findsOneWidget);

          await expectFullyTappable(
            tester,
            find.text('1'),
            within: find.byType(VerifyPinView),
            reason: 'appLock / ${cell.label}: digit key not tappable',
          );

          // Forgot-PIN last: opens a modal that would obscure further asserts.
          await expectFullyTappable(
            tester,
            find.byType(AppTextButton),
            within: find.byType(VerifyPinView),
            reason: 'appLock / ${cell.label}: Forgot-PIN not tappable',
          );
        });
      });
    }
  });

  group('VerifyPinView gate responsive matrix (no Forgot-PIN)', () {
    for (final cell in kFullResponsiveMatrix) {
      testWidgets('gate · ${cell.id}', (tester) async {
        await withTargetPlatform(cell.device.platform, () async {
          await expectNoLayoutOverflow(
            tester,
            () async {
              await pumpScreen(tester, cell, page: gateView());
            },
            reason: 'overflow on gate / ${cell.label}',
          );

          expect(find.byType(NumberPad), findsOneWidget);
          expect(find.byType(AppTextButton), findsNothing);

          await expectFullyTappable(
            tester,
            find.text('1'),
            within: find.byType(VerifyPinView),
            reason: 'gate / ${cell.label}: digit key not tappable',
          );
        });
      });
    }
  });
}
