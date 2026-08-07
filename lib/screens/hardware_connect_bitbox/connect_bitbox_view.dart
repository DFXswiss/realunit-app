import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/utils/device_info.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';
import 'package:realunit_wallet/screens/hardware_connect_bitbox/bloc/connect_bitbox_cubit.dart';
import 'package:realunit_wallet/screens/hardware_connect_bitbox/widgets/connect_content.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/handlebars.dart';

class ConnectBitboxView extends StatelessWidget {
  const ConnectBitboxView({super.key, required this.onFinish, this.onCancel});

  final void Function(AWallet wallet) onFinish;

  /// Overrides the default cancel handler. Bottom-sheet hosts leave this null so
  /// cancelling pops the sheet (`context.pop`). Full-page hosts reached via
  /// `goNamed` (e.g. [BitboxAddressRecoveryPage]) must pass a safe callback —
  /// there `context.pop` throws `GoError` because the recovery route is the only
  /// stack entry and `canPop()` is false.
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    // Fix the sheet height at 90% of screen height (clamped by the host, e.g.
    // SafeArea) — this is not a cap, the sheet is always exactly this tall.
    // The body still scrolls inside [ConnectContent] / [ScrollableActionsLayout]
    // so long DE copy + accessibility text never pushes CTAs off-screen
    // (pairing regression).
    final maxHeight = MediaQuery.sizeOf(context).height * 0.9;

    return SafeArea(
      child: SizedBox(
        height: maxHeight,
        width: .infinity,
        child: BlocListener<ConnectBitboxCubit, BitboxConnectionState>(
          listener: (context, state) async {
            if (state is BitboxFinishSetup) {
              onFinish(state.wallet);
            }
            if (state is BitboxNotConnected) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(S.of(context).connectBitboxFailed),
                  ),
                );
              }
            }
          },
          child: Padding(
            padding: const .symmetric(horizontal: 20.0),
            child: Column(
              children: [
                Handlebars.horizontal(context, margin: const .only(top: 5), width: 36),
                Expanded(
                  child: BlocBuilder<ConnectBitboxCubit, BitboxConnectionState>(
                    builder: (context, state) => switch (state) {
                  BitboxConnecting() => ConnectContent(
                    title: S.of(context).connectBitboxTitle,
                    imagePath: 'assets/images/illustrations/bitbox_connect.svg',
                    child: Column(
                      spacing: 40,
                      children: [
                        Text(
                          S.of(context).connectBitboxConnecting,
                          textAlign: .center,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: RealUnitColors.neutral500,
                          ),
                        ),
                        const CupertinoActivityIndicator(),
                      ],
                    ),
                  ),
                  BitboxCheckHash(:final channelHash) => ConnectContent(
                    title: S.of(context).connectBitboxTitle,
                    imagePath: 'assets/images/illustrations/bitbox_connected.svg',
                    onConfirm: context.read<ConnectBitboxCubit>().confirmPairing,
                    onCancel: onCancel ?? context.pop,
                    child: Column(
                      spacing: 16,
                      children: [
                        Text(
                          S.of(context).connectBitboxCheckPairingCode,
                          textAlign: .center,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: RealUnitColors.neutral500,
                          ),
                        ),
                        Container(
                          padding: const .all(16),
                          decoration: BoxDecoration(
                            color: RealUnitColors.realUnitBlue.withValues(alpha: 0.1),
                            borderRadius: .circular(12),
                          ),
                          child: Text(
                            channelHash,
                            textAlign: .center,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ),
                        Text(
                          S.of(context).connectBitboxSignInHint,
                          textAlign: .center,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: RealUnitColors.neutral500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  BitboxPairing() => ConnectContent(
                    title: S.of(context).connectBitboxTitle,
                    imagePath: 'assets/images/illustrations/bitbox_connected.svg',
                    child: Column(
                      spacing: 40,
                      children: [
                        Text(
                          S.of(context).connectBitboxCheckPairingCode,
                          textAlign: .center,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: RealUnitColors.neutral500,
                          ),
                        ),
                        const CupertinoActivityIndicator(),
                      ],
                    ),
                  ),
                  BitboxNotInitialized() => ConnectContent(
                    title: S.of(context).connectBitboxNotInitializedTitle,
                    imagePath: 'assets/images/illustrations/bitbox_connect.svg',
                    onConfirm: () => context.read<ConnectBitboxCubit>().recheckDeviceStatus(),
                    onCancel: onCancel ?? context.pop,
                    confirmLabel: S.of(context).retry,
                    child: Text(
                      S.of(context).connectBitboxNotInitialized,
                      textAlign: .center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: RealUnitColors.neutral500,
                      ),
                    ),
                  ),
                  BitboxCapturingSignature() => ConnectContent(
                    title: S.of(context).connectBitboxSignatureCapturingTitle,
                    imagePath: 'assets/images/illustrations/bitbox_connected.svg',
                    child: Column(
                      spacing: 40,
                      children: [
                        Text(
                          S.of(context).connectBitboxSignatureCapturing,
                          textAlign: .center,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: RealUnitColors.neutral500,
                          ),
                        ),
                        const CupertinoActivityIndicator(),
                      ],
                    ),
                  ),
                  BitboxSignatureFailed() => ConnectContent(
                    title: S.of(context).connectBitboxSignatureFailedTitle,
                    imagePath: 'assets/images/illustrations/bitbox_connected.svg',
                    onConfirm: () => context.read<ConnectBitboxCubit>().retrySignatureCapture(),
                    onCancel: () =>
                        context.read<ConnectBitboxCubit>().continueWithoutSignature(),
                    confirmLabel: S.of(context).retry,
                    cancelLabel: S.of(context).continueAnyway,
                    child: Text(
                      S.of(context).connectBitboxSignatureFailed,
                      textAlign: .center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: RealUnitColors.neutral500,
                      ),
                    ),
                  ),
                  BitboxConnected() => ConnectContent(
                    title: S.of(context).connected,
                    imagePath: 'assets/images/illustrations/bitbox_connected.svg',
                    onConfirm: () => context.read<ConnectBitboxCubit>().finishSetup(),
                    child: Text(
                      S.of(context).connectedBitboxContent,
                      textAlign: .center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: RealUnitColors.neutral500,
                      ),
                    ),
                  ),
                  _ => ConnectContent(
                    title: S.of(context).connectBitboxTitle,
                    imagePath: 'assets/images/illustrations/bitbox_connect.svg',
                    onCancel: onCancel ?? context.pop,
                    child: Text(
                      DeviceInfo.instance.isIOS
                          ? S.of(context).connectBitboxContentIos
                          : S.of(context).connectBitboxContent,
                      textAlign: .center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: RealUnitColors.neutral500,
                      ),
                    ),
                  ),
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
