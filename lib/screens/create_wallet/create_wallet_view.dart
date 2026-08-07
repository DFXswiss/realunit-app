import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:go_router/go_router.dart';
import 'package:realunit_wallet/packages/utils/screenshot_guard.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/screens/create_wallet/bloc/create_wallet_cubit.dart';
import 'package:realunit_wallet/setup/routing/routes/onboarding_routes.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';
import 'package:realunit_wallet/widgets/scrollable_actions_layout.dart';
import 'package:realunit_wallet/widgets/seed_blur_card.dart';

class CreateWalletView extends StatefulWidget {
  const CreateWalletView({super.key});

  @override
  State<CreateWalletView> createState() => _CreateWalletViewState();
}

class _CreateWalletViewState extends State<CreateWalletView> {
  @override
  void initState() {
    ScreenshotGuard.acquire();
    super.initState();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: RealUnitColors.brand700,
    appBar: AppBar(),
    body: SafeArea(
      child: Padding(
        padding: const .symmetric(horizontal: 20),
        child: BlocBuilder<CreateWalletCubit, CreateWalletState>(
          builder: (context, state) {
            if (state.wallet != null) {
              return ScrollableActionsLayout(
                centerBody: false,
                body: Column(
                  mainAxisAlignment: .start,
                  spacing: 28.0,
                  children: [
                    SvgPicture.asset(
                      'assets/images/illustrations/backup_wallet.svg',
                      width: 124,
                    ),
                    Column(
                      spacing: 8.0,
                      children: [
                        Text(
                          S.of(context).createWalletTitle,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: .bold,
                          ),
                        ),
                        Text(
                          S.of(context).createWalletSubtitle,
                          textAlign: .center,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: RealUnitColors.neutral500,
                          ),
                        ),
                      ],
                    ),
                    SeedBlurCard(
                      seed: state.wallet!.seed,
                      onTap: context.read<CreateWalletCubit>().toggleShowSeed,
                      blur: state.hideSeed,
                    ),
                  ],
                ),
                actions: [
                  Padding(
                    padding: const .symmetric(vertical: 20),
                    child: AppFilledButton(
                      label: S.of(context).createWalletConfirm,
                      onPressed: () => context.pushNamed(
                        OnboardingRoutes.verifySeed,
                        extra: state.wallet,
                      ),
                    ),
                  ),
                ],
              );
            }
            return const Center(
              child: CupertinoActivityIndicator(),
            );
          },
        ),
      ),
    ),
  );

  @override
  void dispose() {
    ScreenshotGuard.release();
    super.dispose();
  }
}
