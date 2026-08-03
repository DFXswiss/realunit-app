import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/screens/kyc/cubits/kyc/kyc_cubit.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/setup/routing/routes/support_routes.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';
import 'package:realunit_wallet/widgets/buttons/app_text_button.dart';
import 'package:realunit_wallet/widgets/scrollable_actions_layout.dart';

/// Shown when the API asks for a KYC step this app has no screen for.
///
/// The app renders a subset of the step names the API can return, so this is reachable whenever
/// verification routes an account down a branch the app does not implement. It used to render the
/// generic failure page — no actions, and the raw wire identifier of the step printed into the
/// message — which left the user with nothing to do and nothing to tell support.
///
/// Deliberately does not name the step: the identifier is an internal enum value, not something a
/// user can act on. Offering a retry matters because the state is not always terminal — the API can
/// move the account on by itself (an internal review completing, a step expiring), and the retry
/// re-reads it rather than stranding the user on a screen that will never change on its own.
class KycUnsupportedStepPage extends StatelessWidget {
  const KycUnsupportedStepPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.of(context).kyc)),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0),
        child: SafeArea(
          child: ScrollableActionsLayout(
            centerBody: true,
            body: Column(
              spacing: 8.0,
              children: [
                Text(
                  S.of(context).kycUnsupportedStepTitle,
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                Text(
                  S.of(context).kycUnsupportedStepDescription,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: RealUnitColors.neutral500,
                  ),
                ),
              ],
            ),
            actions: [
              AppFilledButton(
                onPressed: () => context.read<KycCubit>().checkKyc(),
                label: S.of(context).refresh,
              ),
              AppTextButton(
                onPressed: () => context.pushNamed(SupportRoutes.support),
                label: S.of(context).contactSupport,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
