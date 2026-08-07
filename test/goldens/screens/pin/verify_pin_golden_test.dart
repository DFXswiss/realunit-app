import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/screens/pin/bloc/verify_pin/verify_pin_cubit.dart';
import 'package:realunit_wallet/screens/pin/verify_pin_page.dart';
import 'package:realunit_wallet/widgets/buttons/app_text_button.dart';

import '../../../helper/helper.dart';

class _MockVerifyPinCubit extends MockCubit<VerifyPinState> implements VerifyPinCubit {}

/// Mirrors the private `_ForgotPinButton` that `VerifyPinPage.appLock()` slots
/// into `VerifyPinView.bottom`. The production widget is file-private (and its
/// onPressed reads `PinAuthCubit`/`HomeBloc` only when tapped), so the golden
/// reproduces the wrapper here while still rendering the real `AppTextButton`.
/// Passing any non-null `bottom` also flips the `VerifyPinUnverifiable` copy
/// from the gate variant to the app-lock variant (`pinVerifyUnverifiable`).
class _ForgotPinButton extends StatelessWidget {
  const _ForgotPinButton();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8.0),
    child: SizedBox(
      height: 52.0,
      child: AppTextButton(
        fullWidth: false,
        onPressed: () {},
        label: S.of(context).pinForgotten,
      ),
    ),
  );
}

void main() {
  late _MockVerifyPinCubit verifyPinCubit;

  setUp(() {
    verifyPinCubit = _MockVerifyPinCubit();
    when(() => verifyPinCubit.state).thenReturn(const VerifyPinState());
    when(() => verifyPinCubit.checkBiometricAvailability()).thenAnswer((_) async {});
  });

  Widget buildSubject({String? description}) => BlocProvider<VerifyPinCubit>.value(
    value: verifyPinCubit,
    child: VerifyPinView(
      onAuthenticated: () {},
      description: description,
    ),
  );

  group('$VerifyPinView', () {
    goldenTest(
      'default state',
      fileName: 'verify_pin_page_default',
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      builder: () => wrapForGolden(buildSubject()),
    );

    // The seed-backup flow passes a custom `description` via VerifyPinParams
    // when navigating from Settings -> Wallet Backup (see settings_page.dart
    // calling pinVerifySeedDescription). Resolve the string via S so the
    // golden tracks i18n changes instead of hardcoding the German copy.
    goldenTest(
      'seed backup context with custom subtitle',
      fileName: 'verify_pin_page_seed_backup',
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      builder: () => wrapForGolden(
        Builder(
          builder: (context) => buildSubject(description: S.of(context).pinVerifySeedDescription),
        ),
      ),
    );

    goldenTest(
      'verifying state replaces the number pad with a spinner',
      fileName: 'verify_pin_page_verifying',
      // CupertinoActivityIndicator never settles; pump once to capture the
      // initial frame instead of letting pumpAndSettle hang.
      pumpBeforeTest: pumpOnce,
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      builder: () {
        final cubit = _MockVerifyPinCubit();
        when(() => cubit.state).thenReturn(const VerifyPinVerifying(pin: '123456'));
        when(() => cubit.checkBiometricAvailability()).thenAnswer((_) async {});
        return wrapForGolden(
          BlocProvider<VerifyPinCubit>.value(
            value: cubit,
            child: VerifyPinView(onAuthenticated: () {}),
          ),
        );
      },
    );

    goldenTest(
      'biometric button shown in the number pad when biometrics are available',
      fileName: 'verify_pin_page_biometric_button',
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      builder: () {
        final cubit = _MockVerifyPinCubit();
        when(() => cubit.state).thenReturn(
          const VerifyPinState(biometricStatus: BiometricStatus.available),
        );
        when(() => cubit.checkBiometricAvailability()).thenAnswer((_) async {});
        return wrapForGolden(
          BlocProvider<VerifyPinCubit>.value(
            value: cubit,
            child: VerifyPinView(onAuthenticated: () {}),
          ),
        );
      },
    );

    goldenTest(
      'biometric hint shown when biometrics are enabled but temporarily locked',
      fileName: 'verify_pin_page_biometric_hint',
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      builder: () {
        final cubit = _MockVerifyPinCubit();
        when(() => cubit.state).thenReturn(
          const VerifyPinState(biometricStatus: BiometricStatus.temporarilyLocked),
        );
        when(() => cubit.checkBiometricAvailability()).thenAnswer((_) async {});
        return wrapForGolden(
          BlocProvider<VerifyPinCubit>.value(
            value: cubit,
            child: VerifyPinView(onAuthenticated: () {}),
          ),
        );
      },
    );

    goldenTest(
      'unverifiable state disables the pad and shows the recovery message',
      fileName: 'verify_pin_page_unverifiable',
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      builder: () {
        final cubit = _MockVerifyPinCubit();
        when(() => cubit.state).thenReturn(const VerifyPinUnverifiable());
        when(() => cubit.checkBiometricAvailability()).thenAnswer((_) async {});
        return wrapForGolden(
          BlocProvider<VerifyPinCubit>.value(
            value: cubit,
            child: VerifyPinView(onAuthenticated: () {}),
          ),
        );
      },
    );

    // App-lock entry point (VerifyPinPage.appLock): the only variant that
    // renders the 'Forgot PIN?' action beneath the number pad.
    goldenTest(
      'app lock variant shows the forgot-pin action below the pad',
      fileName: 'verify_pin_page_app_lock',
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      builder: () => wrapForGolden(
        BlocProvider<VerifyPinCubit>.value(
          value: verifyPinCubit,
          child: VerifyPinView(
            onAuthenticated: () {},
            bottom: const _ForgotPinButton(),
          ),
        ),
      ),
    );

    goldenTest(
      'failure state marks the dots red and shows the retry message',
      fileName: 'verify_pin_page_failure',
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      builder: () {
        final cubit = _MockVerifyPinCubit();
        when(() => cubit.state).thenReturn(const VerifyPinFailure(failedAttempts: 3));
        when(() => cubit.checkBiometricAvailability()).thenAnswer((_) async {});
        return wrapForGolden(
          BlocProvider<VerifyPinCubit>.value(
            value: cubit,
            child: VerifyPinView(onAuthenticated: () {}),
          ),
        );
      },
    );

    goldenTest(
      'temporarily locked disables the pad and shows the countdown',
      fileName: 'verify_pin_page_temporarily_locked',
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      builder: () {
        final cubit = _MockVerifyPinCubit();
        // Lock more than an hour out so `_formatRemaining` renders the stable
        // 'Xh Ym' form; the sub-hour form appends a live seconds counter that
        // would differ between the two determinism runs. The mocked cubit emits
        // no state change, so the view's countdown timer never starts.
        when(() => cubit.state).thenReturn(
          VerifyPinTemporarilyLocked(
            failedAttempts: 5,
            lockedUntil:
                DateTime.now().add(const Duration(hours: 1, minutes: 5, seconds: 30)),
          ),
        );
        when(() => cubit.checkBiometricAvailability()).thenAnswer((_) async {});
        return wrapForGolden(
          BlocProvider<VerifyPinCubit>.value(
            value: cubit,
            child: VerifyPinView(onAuthenticated: () {}),
          ),
        );
      },
    );

    // Gate flow (no `bottom`): the button-free lockout copy, since there is no
    // Forgot-PIN button to point at.
    goldenTest(
      'permanently locked in a gate flow disables the pad and shows the button-free message',
      fileName: 'verify_pin_page_locked',
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      builder: () {
        final cubit = _MockVerifyPinCubit();
        when(() => cubit.state).thenReturn(const VerifyPinLocked(failedAttempts: 10));
        when(() => cubit.checkBiometricAvailability()).thenAnswer((_) async {});
        return wrapForGolden(
          BlocProvider<VerifyPinCubit>.value(
            value: cubit,
            child: VerifyPinView(onAuthenticated: () {}),
          ),
        );
      },
    );

    // App-lock entry point (`bottom` present): the copy points at the
    // Forgot-PIN button, which is rendered below the pad.
    goldenTest(
      'permanently locked in the app-lock flow offers recovery via the forgot-pin action',
      fileName: 'verify_pin_page_locked_app_lock',
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      builder: () {
        final cubit = _MockVerifyPinCubit();
        when(() => cubit.state).thenReturn(const VerifyPinLocked(failedAttempts: 10));
        when(() => cubit.checkBiometricAvailability()).thenAnswer((_) async {});
        return wrapForGolden(
          BlocProvider<VerifyPinCubit>.value(
            value: cubit,
            child: VerifyPinView(
              onAuthenticated: () {},
              bottom: const _ForgotPinButton(),
            ),
          ),
        );
      },
    );

    goldenTest(
      'unverifiable app lock offers recovery via the forgot-pin action',
      fileName: 'verify_pin_page_unverifiable_app_lock',
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      builder: () {
        final cubit = _MockVerifyPinCubit();
        when(() => cubit.state).thenReturn(const VerifyPinUnverifiable());
        when(() => cubit.checkBiometricAvailability()).thenAnswer((_) async {});
        return wrapForGolden(
          BlocProvider<VerifyPinCubit>.value(
            value: cubit,
            child: VerifyPinView(
              onAuthenticated: () {},
              bottom: const _ForgotPinButton(),
            ),
          ),
        );
      },
    );

    goldenTest(
      'biometric hint shown when nothing is enrolled anymore',
      fileName: 'verify_pin_page_biometric_hint_not_enrolled',
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      builder: () {
        final cubit = _MockVerifyPinCubit();
        when(() => cubit.state).thenReturn(
          const VerifyPinState(biometricStatus: BiometricStatus.notEnrolled),
        );
        when(() => cubit.checkBiometricAvailability()).thenAnswer((_) async {});
        return wrapForGolden(
          BlocProvider<VerifyPinCubit>.value(
            value: cubit,
            child: VerifyPinView(onAuthenticated: () {}),
          ),
        );
      },
    );

    goldenTest(
      'biometric hint shown when biometrics are momentarily unavailable',
      fileName: 'verify_pin_page_biometric_hint_unavailable',
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      builder: () {
        final cubit = _MockVerifyPinCubit();
        when(() => cubit.state).thenReturn(
          const VerifyPinState(biometricStatus: BiometricStatus.unavailable),
        );
        when(() => cubit.checkBiometricAvailability()).thenAnswer((_) async {});
        return wrapForGolden(
          BlocProvider<VerifyPinCubit>.value(
            value: cubit,
            child: VerifyPinView(onAuthenticated: () {}),
          ),
        );
      },
    );
  });
}
