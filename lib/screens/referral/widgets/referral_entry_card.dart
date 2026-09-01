import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_referral_service.dart';
import 'package:realunit_wallet/screens/referral/cubit/referral_eligibility_cubit.dart';
import 'package:realunit_wallet/setup/di.dart';
import 'package:realunit_wallet/setup/routing/routes/settings_routes.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/outlined_tile.dart';

/// Full-width dashboard card gated by `summary.eligible` from the API.
class ReferralEntryCard extends StatelessWidget {
  const ReferralEntryCard({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          ReferralEligibilityCubit(getIt<RealUnitReferralService>())..load(),
      child: const _ReferralEntryCardView(),
    );
  }
}

class _ReferralEntryCardView extends StatelessWidget {
  const _ReferralEntryCardView();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ReferralEligibilityCubit, ReferralEligibilityState>(
      builder: (context, state) {
        final eligible = state is ReferralEligibilityLoaded && state.eligible;
        if (!eligible) return const SizedBox.shrink();

        final s = S.of(context);
        return OutlinedTile(
          leading: const Icon(
            Icons.people_outline,
            color: RealUnitColors.realUnitBlue,
            size: 24,
          ),
          title: s.referrals,
          subtitle: s.referralsSubtitle,
          trailingIcon: Icons.chevron_right_rounded,
          onTap: () => context.pushNamed(SettingsRoutes.referral),
        );
      },
    );
  }
}
