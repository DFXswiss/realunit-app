import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:realunit_wallet/screens/referral/cubit/referral_cubit.dart';
import 'package:realunit_wallet/setup/routing/routes/settings_routes.dart';

bool _openingReferralCreate = false;

/// Pushes the create-invite screen and reloads overview counts if an invite
/// was created. Used after terms accept and from the overview CTA so the
/// first invite is not missing from the open/credited tiles. A second call
/// while the create route is open is ignored. The lock is released when
/// that route pops, and overview refresh is not awaited, so a hung
/// summary GET cannot block Create.
Future<void> openReferralCreateAndRefresh(BuildContext context) async {
  if (_openingReferralCreate) return;
  _openingReferralCreate = true;
  try {
    final created = await context.pushNamed<bool>(SettingsRoutes.referralCreate);
    _openingReferralCreate = false;
    if (created == true && context.mounted) {
      unawaited(context.read<ReferralCubit>().refreshOverview());
    }
  } finally {
    _openingReferralCreate = false;
  }
}

@visibleForTesting
void debugResetOpeningReferralCreate() {
  _openingReferralCreate = false;
}
