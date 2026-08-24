import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_referral_service.dart';
import 'package:realunit_wallet/screens/referral/cubit/referral_cubit.dart';
import 'package:realunit_wallet/screens/referral/referral_overview_page.dart';
import 'package:realunit_wallet/screens/referral/referral_terms_page.dart';
import 'package:realunit_wallet/setup/di.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';

/// Entry under `/settings/referral` — loads summary and shows terms or overview.
class ReferralPage extends StatelessWidget {
  const ReferralPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ReferralCubit(getIt<RealUnitReferralService>())..load(),
      child: const ReferralGateView(),
    );
  }
}

class ReferralGateView extends StatelessWidget {
  const ReferralGateView({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ReferralCubit, ReferralState>(
      builder: (context, state) {
        if (state is ReferralLoading || state is ReferralInitial) {
          return Scaffold(
            appBar: AppBar(title: Text(S.of(context).referrals)),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        if (state is ReferralNotEligible) {
          return Scaffold(
            appBar: AppBar(title: Text(S.of(context).referrals)),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  S.of(context).referralNotEligible,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        if (state is ReferralNeedsTerms || state is ReferralTermsAccepting) {
          return const ReferralTermsPage();
        }
        if (state is ReferralOverviewLoaded ||
            state is ReferralCreateReady ||
            state is ReferralCreating ||
            state is ReferralInviteCreated) {
          return const ReferralOverviewPage();
        }
        if (state is ReferralFailure) {
          return Scaffold(
            appBar: AppBar(title: Text(S.of(context).referrals)),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 16,
                  children: [
                    Text(state.message, textAlign: TextAlign.center),
                    AppFilledButton(
                      label: S.of(context).retry,
                      onPressed: () => context.read<ReferralCubit>().load(),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}
