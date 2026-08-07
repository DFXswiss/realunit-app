import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/screens/kyc/cubits/kyc/kyc_cubit.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';
import 'package:realunit_wallet/widgets/scrollable_actions_layout.dart';
import 'package:realunit_wallet/widgets/text_substring_highlighting.dart';

class KycPendingPage extends StatelessWidget {
  final KycStep pendingStep;

  const KycPendingPage({super.key, required this.pendingStep});

  @override
  Widget build(BuildContext context) {
    return KycPendingView(pendingStep: pendingStep);
  }
}

class KycPendingView extends StatelessWidget {
  final KycStep pendingStep;

  const KycPendingView({super.key, required this.pendingStep});

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
                  S.of(context).kycPending,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    height: 30 / 26,
                    letterSpacing: -0.52,
                  ),
                ),
                TextSubstringHighlighting(
                  text: S.of(context).kycPendingDescription(pendingStep.name.toUpperCase()),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: RealUnitColors.neutral500,
                    fontSize: 14,
                    height: 18 / 14,
                    letterSpacing: 0.0,
                  ),
                  highlightedText: pendingStep.name.toUpperCase(),
                  highlightedStyle: const TextStyle(
                    color: RealUnitColors.neutral500,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    height: 18 / 14,
                    letterSpacing: 0.0,
                  ),
                ),
              ],
            ),
            actions: [
              Padding(
                padding: const .symmetric(vertical: 16.0),
                child: AppFilledButton(
                  onPressed: () => context.read<KycCubit>().checkKyc(),
                  label: S.of(context).refresh,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
