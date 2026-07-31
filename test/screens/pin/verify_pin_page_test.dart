import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/biometric_service.dart';
import 'package:realunit_wallet/packages/storage/secure_storage.dart';
import 'package:realunit_wallet/screens/pin/bloc/auth/pin_auth_cubit.dart';
import 'package:realunit_wallet/screens/pin/bloc/verify_pin/verify_pin_cubit.dart';
import 'package:realunit_wallet/screens/pin/constants/pin_constants.dart';
import 'package:realunit_wallet/screens/pin/verify_pin_page.dart';
import 'package:realunit_wallet/screens/pin/widgets/pin_indicator.dart';
import 'package:realunit_wallet/setup/di.dart';
import 'package:realunit_wallet/widgets/buttons/app_text_button.dart';
import 'package:realunit_wallet/widgets/number_pad.dart';

import '../../helper/pump_app.dart';

class MockVerifyPinCubit extends MockCubit<VerifyPinState> implements VerifyPinCubit {}

class MockPinAuthCubit extends MockCubit<PinAuthState> implements PinAuthCubit {}

class MockSecureStorage extends Mock implements SecureStorage {}

class MockBiometricService extends Mock implements BiometricService {}

void main() {
  late VerifyPinCubit verifyPinCubit;
  late PinAuthCubit pinAuthCubit;
  void onAuthenticated() => {};

  setUp(() {
    verifyPinCubit = MockVerifyPinCubit();

    when(() => verifyPinCubit.state).thenReturn(const VerifyPinState());
    when(() => verifyPinCubit.checkBiometricAvailability()).thenAnswer((_) => Future.value());
  });

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

  Widget buildSubject(Widget child) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: verifyPinCubit),
      ],
      child: child,
    );
  }

  group('$VerifyPinPage', () {
    testWidgets('renders $VerifyPinView', (tester) async {
      await tester.pumpApp(VerifyPinPage(onAuthenticated: onAuthenticated));

      expect(find.byType(VerifyPinView), findsOne);
    });
  });

  group('${VerifyPinPage.appLock()}', () {
    testWidgets('renders $VerifyPinView with AppTextButton', (tester) async {
      await tester.pumpApp(VerifyPinPage.appLock());

      expect(find.byType(VerifyPinView), findsOne);
      expect(find.byType(AppTextButton), findsOne);
    });
  });

  group('$VerifyPinView', () {
    testWidgets('is initially correctly rendered', (tester) async {
      when(() => verifyPinCubit.state).thenReturn(const VerifyPinState());

      await tester.pumpApp(
        buildSubject(VerifyPinView(onAuthenticated: onAuthenticated)),
      );

      expect(find.text(S.current.pinVerify), findsOne);
      expect(find.text(S.current.pinVerifyDescription), findsOne);

      expect(find.byType(PinIndicator), findsOne);
      expect((tester.widget(find.byType(Visibility)) as Visibility).visible, isFalse);
      expect(find.byType(NumberPad), findsOne);
    });

    testWidgets('shows error message when pin is incorrect', (tester) async {
      when(() => verifyPinCubit.state).thenReturn(const VerifyPinFailure(failedAttempts: 1));

      await tester.pumpApp(
        buildSubject(VerifyPinView(onAuthenticated: onAuthenticated)),
      );

      expect((tester.widget(find.byType(Visibility)) as Visibility).visible, isTrue);
    });

    testWidgets('shows error message and locks temporarily when pin is reaches threshold', (
      tester,
    ) async {
      when(() => verifyPinCubit.state).thenReturn(
        VerifyPinTemporarilyLocked(
          failedAttempts: 9,
          lockedUntil: DateTime.now().add(const Duration(minutes: 1)),
        ),
      );

      await tester.pumpApp(
        buildSubject(VerifyPinView(onAuthenticated: onAuthenticated)),
      );
      expect(find.text(S.current.pinVerifyLockedTemporarily('59s')), findsOne);
      expect(tester.widget<NumberPad>(find.byType(NumberPad)).inputEnabled, isFalse);
    });

    testWidgets('permanently locked in a gate flow shows the button-free lockout message', (
      tester,
    ) async {
      when(() => verifyPinCubit.state).thenReturn(const VerifyPinLocked(failedAttempts: 9));

      await tester.pumpApp(
        buildSubject(VerifyPinView(onAuthenticated: onAuthenticated)),
      );

      // No `bottom` (no Forgot-PIN button) → the gate-variant text is shown,
      // not the one pointing at a button that isn't there.
      expect(find.text(S.current.pinVerifyLockedGate), findsOne);
      expect(find.text(S.current.pinVerifyLocked), findsNothing);
      expect(tester.widget<NumberPad>(find.byType(NumberPad)).inputEnabled, isFalse);
    });

    testWidgets('permanently locked in the app-lock flow references the forgot-PIN reset', (
      tester,
    ) async {
      when(() => verifyPinCubit.state).thenReturn(const VerifyPinLocked(failedAttempts: 9));

      await tester.pumpApp(
        buildSubject(
          VerifyPinView(
            onAuthenticated: onAuthenticated,
            bottom: const SizedBox(),
          ),
        ),
      );

      // A `bottom` widget (the Forgot-PIN button lives here) → the text that
      // points at it is valid.
      expect(find.text(S.current.pinVerifyLocked), findsOne);
    });

    testWidgets('shows a loading indicator and hides the number pad while verifying', (
      tester,
    ) async {
      when(() => verifyPinCubit.state).thenReturn(const VerifyPinVerifying(pin: '123456'));

      await tester.pumpApp(
        buildSubject(VerifyPinView(onAuthenticated: onAuthenticated)),
      );

      expect(find.byType(CupertinoActivityIndicator), findsOne);
      expect(find.text(S.current.pinVerifying), findsOne);
      expect(find.byType(NumberPad), findsNothing);
      // Dots stay filled during the wait so the screen does not look reset.
      expect(
        (tester.widget(find.byType(PinIndicator)) as PinIndicator).pinLength,
        pinLength,
      );
    });

    testWidgets('keeps the loading indicator after success while the wallet loads', (
      tester,
    ) async {
      when(() => verifyPinCubit.state).thenReturn(const VerifyPinSuccess());

      await tester.pumpApp(
        buildSubject(VerifyPinView(onAuthenticated: onAuthenticated)),
      );

      expect(find.byType(CupertinoActivityIndicator), findsOne);
      expect(find.byType(NumberPad), findsNothing);
    });

    testWidgets('shows the biometric button when biometrics are available', (tester) async {
      when(() => verifyPinCubit.state).thenReturn(
        const VerifyPinState(biometricStatus: BiometricStatus.available),
      );

      await tester.pumpApp(
        buildSubject(VerifyPinView(onAuthenticated: onAuthenticated)),
      );

      expect(find.byIcon(Icons.fingerprint), findsOne);
      expect(tester.widget<NumberPad>(find.byType(NumberPad)).inputEnabled, isTrue);
    });

    testWidgets('hides the biometric button when biometrics are not available', (tester) async {
      when(() => verifyPinCubit.state).thenReturn(const VerifyPinState());

      await tester.pumpApp(
        buildSubject(VerifyPinView(onAuthenticated: onAuthenticated)),
      );

      expect(find.byIcon(Icons.fingerprint), findsNothing);
    });

    testWidgets('the biometric button carries a screen-reader accessibility label', (
      tester,
    ) async {
      when(() => verifyPinCubit.state).thenReturn(
        const VerifyPinState(biometricStatus: BiometricStatus.available),
      );

      await tester.pumpApp(
        buildSubject(VerifyPinView(onAuthenticated: onAuthenticated)),
      );

      // The glyph is visible and the unlock shortcut is announced to a screen
      // reader via the icon's semanticLabel.
      final icon = tester.widget<Icon>(find.byIcon(Icons.fingerprint));
      expect(icon.semanticLabel, S.current.pinVerifyBiometricButton);
    });

    testWidgets('exposes no biometric accessibility label when the button is hidden', (
      tester,
    ) async {
      when(() => verifyPinCubit.state).thenReturn(const VerifyPinState());

      await tester.pumpApp(
        buildSubject(VerifyPinView(onAuthenticated: onAuthenticated)),
      );

      // With biometrics unavailable no glyph is built, so there is no icon to
      // carry the accessibility label (neither the fingerprint nor Face-ID one).
      expect(find.byIcon(Icons.fingerprint), findsNothing);
      expect(find.byIcon(Icons.face), findsNothing);
    });

    testWidgets('keeps the biometric button active while temporarily locked', (tester) async {
      when(() => verifyPinCubit.state).thenReturn(
        VerifyPinTemporarilyLocked(
          failedAttempts: 5,
          lockedUntil: DateTime.now().add(const Duration(minutes: 1)),
          biometricStatus: BiometricStatus.available,
        ),
      );

      await tester.pumpApp(
        buildSubject(VerifyPinView(onAuthenticated: onAuthenticated)),
      );

      final numberPad = tester.widget<NumberPad>(find.byType(NumberPad));
      // Pad disabled, yet the biometric shortcut is still offered.
      expect(numberPad.inputEnabled, isFalse);
      expect(find.byIcon(Icons.fingerprint), findsOne);
    });

    testWidgets('tapping the biometric button triggers promptBiometric', (tester) async {
      when(() => verifyPinCubit.state).thenReturn(
        const VerifyPinState(biometricStatus: BiometricStatus.available),
      );
      when(() => verifyPinCubit.promptBiometric()).thenAnswer((_) async {});

      await tester.pumpApp(
        buildSubject(VerifyPinView(onAuthenticated: onAuthenticated)),
      );

      await tester.ensureVisible(find.byIcon(Icons.fingerprint));
      await tester.tap(find.byIcon(Icons.fingerprint));
      await tester.pump();

      verify(() => verifyPinCubit.promptBiometric()).called(1);
    });

    testWidgets('the biometric button fires even while temporarily locked', (tester) async {
      when(() => verifyPinCubit.state).thenReturn(
        VerifyPinTemporarilyLocked(
          failedAttempts: 5,
          lockedUntil: DateTime.now().add(const Duration(minutes: 1)),
          biometricStatus: BiometricStatus.available,
        ),
      );
      when(() => verifyPinCubit.promptBiometric()).thenAnswer((_) async {});

      await tester.pumpApp(
        buildSubject(VerifyPinView(onAuthenticated: onAuthenticated)),
      );

      // The pad is inert but the escape-hatch button must still reach the cubit.
      expect(tester.widget<NumberPad>(find.byType(NumberPad)).inputEnabled, isFalse);
      await tester.ensureVisible(find.byIcon(Icons.fingerprint));
      await tester.tap(find.byIcon(Icons.fingerprint));
      await tester.pump();

      verify(() => verifyPinCubit.promptBiometric()).called(1);
    });

    testWidgets('uses the face icon on iOS', (tester) async {
      when(() => verifyPinCubit.state).thenReturn(
        const VerifyPinState(biometricStatus: BiometricStatus.available),
      );

      // Must be cleared before the test body returns (the framework asserts all
      // foundation debug vars are unset), so reset it in a finally.
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await tester.pumpApp(
          buildSubject(VerifyPinView(onAuthenticated: onAuthenticated)),
        );

        expect(find.byIcon(Icons.face), findsOne);
        expect(find.byIcon(Icons.fingerprint), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('shows the locked hint when biometrics are temporarily locked', (tester) async {
      when(() => verifyPinCubit.state).thenReturn(
        const VerifyPinState(biometricStatus: BiometricStatus.temporarilyLocked),
      );

      await tester.pumpApp(
        buildSubject(VerifyPinView(onAuthenticated: onAuthenticated)),
      );

      expect(find.text(S.current.pinVerifyBiometricHintLocked), findsOne);
    });

    testWidgets('shows the not-enrolled hint', (tester) async {
      when(() => verifyPinCubit.state).thenReturn(
        const VerifyPinState(biometricStatus: BiometricStatus.notEnrolled),
      );

      await tester.pumpApp(
        buildSubject(VerifyPinView(onAuthenticated: onAuthenticated)),
      );

      expect(find.text(S.current.pinVerifyBiometricHintNotEnrolled), findsOne);
    });

    testWidgets('shows the unavailable hint', (tester) async {
      when(() => verifyPinCubit.state).thenReturn(
        const VerifyPinState(biometricStatus: BiometricStatus.unavailable),
      );

      await tester.pumpApp(
        buildSubject(VerifyPinView(onAuthenticated: onAuthenticated)),
      );

      expect(find.text(S.current.pinVerifyBiometricHintUnavailable), findsOne);
    });

    testWidgets('unverifiable in a gate flow shows the button-free recovery message', (
      tester,
    ) async {
      when(() => verifyPinCubit.state).thenReturn(const VerifyPinUnverifiable());

      await tester.pumpApp(
        buildSubject(VerifyPinView(onAuthenticated: onAuthenticated)),
      );

      // No `bottom` (no Forgot-PIN button) → the gate-variant text is shown.
      expect(find.text(S.current.pinVerifyUnverifiableGate), findsOne);
      expect(tester.widget<NumberPad>(find.byType(NumberPad)).inputEnabled, isFalse);
    });

    testWidgets('unverifiable in the app-lock flow references the forgot-PIN reset', (
      tester,
    ) async {
      when(() => verifyPinCubit.state).thenReturn(const VerifyPinUnverifiable());

      await tester.pumpApp(
        buildSubject(
          VerifyPinView(
            onAuthenticated: onAuthenticated,
            bottom: const SizedBox(),
          ),
        ),
      );

      // A `bottom` widget (the Forgot-PIN button lives here) → the text that
      // points at it is valid.
      expect(find.text(S.current.pinVerifyUnverifiable), findsOne);
    });

    group('$BlocListener', () {
      testWidgets('triggers onPinVerified if verification is successful', (tester) async {
        whenListen(
          verifyPinCubit,
          Stream.fromIterable([
            const VerifyPinSuccess(),
          ]),
          initialState: const VerifyPinState(),
        );

        await tester.pumpApp(
          buildSubject(VerifyPinView(onAuthenticated: getIt<PinAuthCubit>().onPinVerified)),
        );
        await tester.pump();

        verify(() => pinAuthCubit.onPinVerified()).called(1);
      });
    });
  });
}
