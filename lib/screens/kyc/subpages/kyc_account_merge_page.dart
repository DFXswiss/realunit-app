import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/screens/kyc/cubits/kyc/kyc_cubit.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';
import 'package:realunit_wallet/widgets/scrollable_actions_layout.dart';

class KycAccountMergePage extends StatelessWidget {
  const KycAccountMergePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.of(context).kyc),
      ),
      body: Padding(
        padding: const .symmetric(horizontal: 20.0),
        child: SafeArea(
          child: ScrollableActionsLayout(
            centerBody: true,
            body: Column(
              spacing: 8.0,
              children: [
                Text(
                  S.of(context).kycAccountMergeTitle,
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: .center,
                ),
                Text(
                  S.of(context).kycAccountMergeDescription,
                  textAlign: .center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: RealUnitColors.neutral500,
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
