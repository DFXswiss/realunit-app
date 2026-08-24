import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_referral_service.dart';
import 'package:realunit_wallet/screens/pin/bloc/auth/pin_auth_cubit.dart';
import 'package:realunit_wallet/screens/settings/bloc/settings_bloc.dart';
import 'package:realunit_wallet/setup/di.dart';
import 'package:realunit_wallet/setup/routing/referral_pending_code.dart';
import 'package:realunit_wallet/setup/routing/routes/settings_routes.dart';

/// Binds a stashed or freshly delivered referral code once the session is unlocked.
/// Shows the API campaign text for promo binds; navigates to referral overview for invites.
Future<void> bindPendingReferralCode(GoRouter router, {String? code}) async {
  final resolved = code ?? await takePendingReferralCode();
  if (resolved == null || resolved.isEmpty) return;

  try {
    final result = await getIt<RealUnitReferralService>().bind(code: resolved);
    final ctx = router.routerDelegate.navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;

    if (result.isPromo) {
      final lang = getIt<SettingsBloc>().state.language.code;
      final text = result.campaignTextForLocale(lang);
      if (text != null && text.isNotEmpty) {
        await showDialog<void>(
          context: ctx,
          builder: (dialogContext) => AlertDialog(
            title: Text(S.of(dialogContext).referralPromoTitle),
            content: SingleChildScrollView(child: Text(text)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(S.of(dialogContext).close),
              ),
            ],
          ),
        );
      }
    } else {
      unawaited(router.pushNamed(SettingsRoutes.referral));
    }
  } on ApiException {
    // Deeplink bind failures must not crash boot; the user can retry via settings.
  } catch (_) {
    // Transport failures stay silent on the deeplink path.
  }
}

/// Deferred bind used from redirects — re-checks PIN unlock at execution time.
void scheduleReferralBind(GoRouter router, String code) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final pinState = getIt<PinAuthCubit>().state;
    if (!(pinState.isPinVerified && pinState.isPinSetup)) {
      unawaited(stashPendingReferralCode(code));
      return;
    }
    unawaited(bindPendingReferralCode(router, code: code));
  });
}
