import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/screens/kyc/cubits/kyc/kyc_cubit.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';
import 'package:realunit_wallet/widgets/scrollable_actions_layout.dart';

/// Waiting screen shown while the backend processes a confirmed account merge
/// (`KycProcessStatus.mergeProcessing`). The user already confirmed; the API is
/// still re-parenting steps / finishing KYC follow-up, so we show progress
/// instead of interpreting the poll as a failure.
class KycMergeProcessingPage extends StatelessWidget {
  const KycMergeProcessingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.of(context).kyc),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0),
        child: SafeArea(
          child: ScrollableActionsLayout(
            centerBody: true,
            body: Column(
              spacing: 8.0,
              children: [
                const CupertinoActivityIndicator(),
                Text(
                  S.of(context).kycMergeProcessingTitle,
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                Text(
                  S.of(context).kycMergeProcessingDescription,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: RealUnitColors.neutral500,
                  ),
                ),
              ],
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
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
