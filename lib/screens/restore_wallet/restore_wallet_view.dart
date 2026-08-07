import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:realunit_wallet/packages/utils/screenshot_guard.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/screens/home/bloc/home_bloc.dart';
import 'package:realunit_wallet/screens/restore_wallet/cubit/restore_wallet/restore_wallet_cubit.dart';
import 'package:realunit_wallet/screens/restore_wallet/cubit/validate_seed/validate_seed_cubit.dart';
import 'package:realunit_wallet/screens/restore_wallet/widgets/restore_wallet_button.dart';
import 'package:realunit_wallet/screens/restore_wallet/widgets/restore_wallet_input_field.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/styles/icons.dart';
import 'package:realunit_wallet/widgets/mnemonic_field.dart';
import 'package:realunit_wallet/widgets/scrollable_actions_layout.dart';
import 'package:realunit_wallet/widgets/text_substring_highlighting.dart';

class RestoreWalletView extends StatefulWidget {
  const RestoreWalletView({super.key});

  @override
  State<RestoreWalletView> createState() => _RestoreWalletViewState();
}

class _RestoreWalletViewState extends State<RestoreWalletView> {
  final _controllers = List.generate(12, (_) => MnemonicInputFieldController());
  final _focusNodes = List.generate(12, (_) => FocusNode());

  @override
  void initState() {
    // The user types their existing 12-word recovery phrase here — block
    // screenshots and the app-switcher snapshot. Released on dispose;
    // screenshots re-enable only when the last protected screen leaves
    // (see ScreenshotGuard).
    ScreenshotGuard.acquire();
    super.initState();
  }

  @override
  Widget build(BuildContext context) => MultiBlocListener(
    listeners: [
      BlocListener<RestoreWalletCubit, RestoreWalletState>(
        listenWhen: (previous, current) => previous.wallet != current.wallet,
        listener: (context, state) async {
          if (state.wallet != null) {
            await Future.delayed(const Duration(seconds: 2));
            if (context.mounted) context.read<HomeBloc>().add(LoadWalletEvent(state.wallet!));
          }
        },
      ),
      BlocListener<ValidateSeedCubit, ValidateSeedState>(
        listener: (context, seedState) {
          if (seedState == ValidateSeedState.valid) {
            context.read<RestoreWalletCubit>().restoreWallet(_controllers.seed);
          }
        },
      ),
    ],
    child: Scaffold(
      backgroundColor: RealUnitColors.brand700,
      appBar: AppBar(),
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: ScrollableActionsLayout(
              centerBody: false,
              body: Column(
                mainAxisAlignment: .start,
                children: <Widget>[
                  SvgPicture.asset(
                    'assets/images/illustrations/restore_wallet.svg',
                    height: 124,
                  ),
                  const SizedBox(
                    height: 20,
                  ),
                  Text(
                    S.of(context).restoreWallet,
                    style: const TextStyle(
                      fontSize: 26,
                      color: RealUnitColors.realUnitBlack,
                      fontWeight: FontWeight.bold,
                      height: 30 / 26,
                      letterSpacing: -0.52,
                    ),
                  ),
                  const SizedBox(
                    height: 40,
                  ),
                  Row(
                    spacing: 8.0,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const RecoveryKeyIcon(size: 20, color: RealUnitColors.realUnitBlue),
                      Expanded(
                        child: TextSubstringHighlighting(
                          text: S.of(context).restoreWalletFromSeedDescription,
                          style: const TextStyle(
                            fontSize: 15,
                            color: RealUnitColors.neutral500,
                          ),
                          highlightedText: '12 ${S.of(context).recoveryWords}',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  RestoreWalletInputField(
                    controllers: _controllers,
                    focusNodes: _focusNodes,
                  ),
                ],
              ),
              actions: [
                RestoreWalletButton(
                  controllers: _controllers,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  @override
  void dispose() {
    ScreenshotGuard.release();
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }
}
