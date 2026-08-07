import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/biometric_service.dart';
import 'package:realunit_wallet/packages/storage/secure_storage.dart';
import 'package:realunit_wallet/screens/pin/bloc/auth/pin_auth_cubit.dart';
import 'package:realunit_wallet/screens/pin/bloc/setup_pin/setup_pin_cubit.dart';
import 'package:realunit_wallet/screens/pin/constants/pin_constants.dart';
import 'package:realunit_wallet/screens/pin/widgets/enable_biometric_bottom_sheet.dart';
import 'package:realunit_wallet/screens/pin/widgets/pin_indicator.dart';
import 'package:realunit_wallet/screens/pin/widgets/verifying_indicator.dart';
import 'package:realunit_wallet/setup/di.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/number_pad.dart';
import 'package:realunit_wallet/widgets/scrollable_actions_layout.dart';

class SetupPinPage extends StatelessWidget {
  /// Invoked once the PIN is stored instead of the default onboarding
  /// completion. The PIN-change flow passes its own navigation here.
  final VoidCallback? onCompleted;

  /// Whether to offer the biometric-enable sheet after storing the PIN. The
  /// onboarding flow keeps this on; the PIN-change flow turns it off.
  final bool promptBiometrics;

  const SetupPinPage({
    super.key,
    this.onCompleted,
    this.promptBiometrics = true,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => SetupPinCubit(
        getIt<SecureStorage>(),
        getIt<BiometricService>(),
      ),
      child: SetupPinView(
        onCompleted: onCompleted,
        promptBiometrics: promptBiometrics,
      ),
    );
  }
}

class SetupPinView extends StatelessWidget {
  final VoidCallback? onCompleted;
  final bool promptBiometrics;

  const SetupPinView({
    super.key,
    this.onCompleted,
    this.promptBiometrics = true,
  });

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<SetupPinCubit, SetupPinState>(
      listener: (context, state) async {
        if (!state.isComplete) return;
        if (promptBiometrics) {
          await _promptBiometricSetup(context);
        }
        if (!context.mounted) return;
        // Change flow supplies its own follow-up (pop + feedback); onboarding
        // falls back to the shared auth completion.
        final completion = onCompleted;
        if (completion != null) {
          completion();
        } else {
          getIt<PinAuthCubit>().onPinSetupComplete();
        }
      },
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            leading: switch (state.mode) {
              .create => null,
              .confirm => IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: context.read<SetupPinCubit>().reset,
              ),
            },
          ),
          backgroundColor: RealUnitColors.brand700,
          body: SafeArea(
            child: ScrollableActionsLayout(
              centerBody: true,
              body: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Column(
                      spacing: 8.0,
                      children: [
                        Text(
                          switch (state.mode) {
                            .create => S.of(context).pinCreate,
                            .confirm => S.of(context).pinConfirm,
                          },
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        Text(
                          switch (state.mode) {
                            .create => S.of(context).pinCreateDescription('$pinLength'),
                            .confirm => S.of(context).pinConfirmDescription,
                          },
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
                          pinLength: state.currentPin.length,
                          expectedPinLength: pinLength,
                          wrongPin: state.mismatch,
                        ),
                        Visibility(
                          visible: state.mismatch || state.storeFailed,
                          maintainSize: true,
                          maintainAnimation: true,
                          maintainState: true,
                          child: Text(
                            state.storeFailed
                                ? S.of(context).pinSaveFailed
                                : S.of(context).pinConfirmFailed,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: RealUnitColors.status.red600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                if (state.isSubmitting)
                  VerifyingIndicator(label: S.of(context).pinSaving)
                else
                  NumberPad(
                    onNumberPressed: (digit) => context.read<SetupPinCubit>().addDigit(digit),
                    onDeletePressed: context.read<SetupPinCubit>().deleteDigit,
                  ),
                const SizedBox(height: 60.0),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _promptBiometricSetup(BuildContext context) async {
    final cubit = context.read<SetupPinCubit>();
    final isAvailable = await cubit.isBiometricAvailable();
    if (!isAvailable || !context.mounted) return;

    final shouldEnable = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const EnableBiometricBottomSheet(),
    );
    if (shouldEnable == true) {
      await cubit.enableBiometrics();
    }
  }
}
