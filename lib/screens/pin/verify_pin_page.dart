import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/biometric_service.dart';
import 'package:realunit_wallet/packages/storage/secure_storage.dart';
import 'package:realunit_wallet/screens/home/bloc/home_bloc.dart';
import 'package:realunit_wallet/screens/pin/bloc/auth/pin_auth_cubit.dart';
import 'package:realunit_wallet/screens/pin/bloc/verify_pin/verify_pin_cubit.dart';
import 'package:realunit_wallet/screens/pin/constants/pin_constants.dart';
import 'package:realunit_wallet/screens/pin/widgets/forgot_pin_bottom_sheet.dart';
import 'package:realunit_wallet/screens/pin/widgets/pin_indicator.dart';
import 'package:realunit_wallet/screens/pin/widgets/verifying_indicator.dart';
import 'package:realunit_wallet/setup/di.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/buttons/app_text_button.dart';
import 'package:realunit_wallet/widgets/number_pad.dart';
import 'package:realunit_wallet/widgets/scrollable_actions_layout.dart';

class VerifyPinParams {
  final String? description;
  final VoidCallback onAuthenticated;

  const VerifyPinParams({required this.onAuthenticated, this.description});
}

class VerifyPinPage extends StatelessWidget {
  final String? description;
  final VoidCallback onAuthenticated;
  final Widget? bottom;
  final bool enableLockout;

  /// Used to verify PIN before showing specific feature
  const VerifyPinPage({
    super.key,
    this.description,
    required this.onAuthenticated,
    this.bottom,
    this.enableLockout = true,
  });

  /// Used for initial app lock check on app start
  factory VerifyPinPage.appLock() => VerifyPinPage(
    onAuthenticated: () => getIt<PinAuthCubit>().onPinVerified(),
    bottom: const _ForgotPinButton(),
    enableLockout: true,
  );

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => VerifyPinCubit(
      getIt<SecureStorage>(),
      getIt<BiometricService>(),
      enableLockout: enableLockout,
    ),
    child: VerifyPinView(
      description: description,
      onAuthenticated: onAuthenticated,
      bottom: bottom,
    ),
  );
}

class VerifyPinView extends StatefulWidget {
  final String? description;
  final VoidCallback onAuthenticated;
  final Widget? bottom;

  const VerifyPinView({
    super.key,
    this.description,
    required this.onAuthenticated,
    this.bottom,
  });

  @override
  State<VerifyPinView> createState() => _VerifyPinViewState();
}

class _VerifyPinViewState extends State<VerifyPinView> {
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<VerifyPinCubit>().checkBiometricAvailability();
    });
  }

  @override
  Widget build(BuildContext context) => BlocConsumer<VerifyPinCubit, VerifyPinState>(
    listener: (context, state) {
      if (state is VerifyPinSuccess) {
        // Stop the lockout countdown so it cannot fire onLockExpired over the
        // success state while the wallet loads (spurious re-prompt / re-lock).
        _countdownTimer?.cancel();
        widget.onAuthenticated();
      } else if (state is VerifyPinTemporarilyLocked) {
        _startCountdown(state.lockedUntil);
      }
    },
    builder: (context, state) {
      final isLocked = state is VerifyPinTemporarilyLocked || state is VerifyPinLocked;
      final isUnverifiable = state is VerifyPinUnverifiable;
      final showsError = state is VerifyPinFailure || isLocked || isUnverifiable;
      // Covers both the PIN-hash check (VerifyPinVerifying) and the subsequent
      // wallet load that runs after success while this screen is still on top.
      final isVerifying = state is VerifyPinVerifying || state is VerifyPinSuccess;
      // Biometrics are OS-bound, so the shortcut stays offered even behind an
      // active lockout — a successful scan is the way out.
      final biometricAvailable = state.biometricStatus == BiometricStatus.available;
      final biometricHint = _biometricHint(context, state.biometricStatus);

      return Scaffold(
        appBar: AppBar(),
        backgroundColor: RealUnitColors.brand700,
        body: SafeArea(
          child: ScrollableActionsLayout(
            centerBody: true,
            body: Column(
              spacing: 4.0,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: Column(
                    children: [
                      Column(
                        spacing: 8.0,
                        children: [
                          Text(
                            S.of(context).pinVerify,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          Text(
                            widget.description ?? S.of(context).pinVerifyDescription,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: RealUnitColors.neutral500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                      Column(
                        spacing: 16.0,
                        children: [
                          PinIndicator(
                            pinLength: isVerifying ? pinLength : state.pin.length,
                            expectedPinLength: pinLength,
                            wrongPin: state is VerifyPinFailure || isLocked || isUnverifiable,
                          ),
                          Visibility(
                            visible: showsError,
                            maintainSize: true,
                            maintainAnimation: true,
                            maintainState: true,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 40.0),
                              child: Text(
                                switch (state) {
                                  VerifyPinTemporarilyLocked s =>
                                    S
                                        .of(context)
                                        .pinVerifyLockedTemporarily(
                                          _formatRemaining(s.lockedUntil),
                                        ),
                                  // The 'Forgot PIN?' button only exists in
                                  // the appLock variant (bottom != null); gate
                                  // flows get a text without that dangling
                                  // button reference — both the permanent-lock
                                  // and the unverifiable messages branch on it.
                                  VerifyPinLocked _ => widget.bottom != null
                                      ? S.of(context).pinVerifyLocked
                                      : S.of(context).pinVerifyLockedGate,
                                  VerifyPinUnverifiable _ => widget.bottom != null
                                      ? S.of(context).pinVerifyUnverifiable
                                      : S.of(context).pinVerifyUnverifiableGate,
                                  _ => S.of(context).pinVerifyFailed,
                                },
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: RealUnitColors.status.red600,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                          if (biometricHint != null)
                            Text(
                              biometricHint,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: RealUnitColors.neutral500,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              // Sticky primary surface: NumberPad must stay fully visible at
              // high text scales (shape 2 — not inside the scrollable body).
              if (isVerifying)
                const VerifyingIndicator()
              else
                NumberPad(
                  onNumberPressed: context.read<VerifyPinCubit>().addDigit,
                  onDeletePressed: context.read<VerifyPinCubit>().deleteDigit,
                  inputEnabled: !(isLocked || isUnverifiable),
                  onBiometricPressed: biometricAvailable
                      ? context.read<VerifyPinCubit>().promptBiometric
                      : null,
                  biometricIcon: biometricAvailable
                      ? Icon(
                          // Face-ID phones expect a face glyph; everything
                          // else keeps the fingerprint affordance.
                          Theme.of(context).platform == TargetPlatform.iOS
                              ? Icons.face
                              : Icons.fingerprint,
                          size: 28,
                          color: RealUnitColors.realUnitBlack,
                          semanticLabel: S.of(context).pinVerifyBiometricButton,
                        )
                      : null,
                ),
              widget.bottom ?? const SizedBox(height: 60.0),
            ],
          ),
        ),
      );
    },
  );

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown(DateTime lockedUntil) {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (DateTime.now().isAfter(lockedUntil)) {
        _countdownTimer?.cancel();
        context.read<VerifyPinCubit>().onLockExpired();
      } else {
        setState(() {});
      }
    });
  }

  /// Explanatory line shown when biometrics are enabled but currently unusable,
  /// so the missing Face-ID/biometrics button is not left unexplained.
  String? _biometricHint(BuildContext context, BiometricStatus status) => switch (status) {
    BiometricStatus.temporarilyLocked ||
    BiometricStatus.permanentlyLocked => S.of(context).pinVerifyBiometricHintLocked,
    BiometricStatus.notEnrolled => S.of(context).pinVerifyBiometricHintNotEnrolled,
    BiometricStatus.unavailable => S.of(context).pinVerifyBiometricHintUnavailable,
    _ => null,
  };

  String _formatRemaining(DateTime lockedUntil) {
    final remaining = lockedUntil.difference(DateTime.now());
    if (remaining.inHours >= 1) {
      final minutes = remaining.inMinutes.remainder(60);
      return '${remaining.inHours}h ${minutes}m';
    } else if (remaining.inMinutes >= 1) {
      final seconds = remaining.inSeconds.remainder(60);
      return '${remaining.inMinutes}m ${seconds}s';
    } else {
      return '${remaining.inSeconds}s';
    }
  }
}

class _ForgotPinButton extends StatelessWidget {
  const _ForgotPinButton();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8.0),
    child: SizedBox(
      height: 52.0,
      child: AppTextButton(
        fullWidth: false,
        onPressed: () async {
          final isReset = await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            builder: (_) => const ForgotPinBottomSheet(),
          );
          if (isReset == true) {
            await Future.delayed(const Duration(milliseconds: 300));
            if (context.mounted) {
              await context.read<PinAuthCubit>().reset();
              if (context.mounted) {
                context.read<HomeBloc>().add(const DeleteCurrentWalletEvent());
              }
            }
          }
        },
        label: S.of(context).pinForgotten,
      ),
    ),
  );
}
