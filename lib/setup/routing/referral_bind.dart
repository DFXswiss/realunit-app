import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_bind_result_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_referral_service.dart';
import 'package:realunit_wallet/packages/service/dfx/referral_lookup_status.dart';
import 'package:realunit_wallet/screens/referral/referral_error_message.dart';
import 'package:realunit_wallet/screens/pin/bloc/auth/pin_auth_cubit.dart';
import 'package:realunit_wallet/setup/di.dart';
import 'package:realunit_wallet/setup/routing/referral_pending_code.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';

bool _bindInFlight = false;

@visibleForTesting
void debugResetBindInFlight() {
  _bindInFlight = false;
}

/// Binds a stashed or freshly delivered referral code once the session is unlocked.
/// Shows the API campaign text for promo binds. Invite binds show the same
/// recognition copy as registration (`referralInviteRecognized`) when the
/// payload includes [ReferralBindResultDto.inviterName]. The invitee is not
/// sent to the referrer overview (they are not the host).
///
/// The stash is taken before POST so a dashboard boot bind cannot send the
/// same code in parallel. A second call while that POST is in flight only
/// stashes; it does not take. Transport / 5xx / 401 / 429 and an unmounted
/// NestJS route (`Cannot POST …`) put the code back so the next dashboard
/// landing can retry, without overwriting a newer stashed code, and show
/// the unavailable copy once (Retry binds again on that dialog in the
/// loading state; Close waits for the next landing). 4xx business rejections (invalid,
/// self-referral, already bound, stacking) drop it — retrying those on
/// every unlock would loop forever — and show the invalid-code copy once.
/// If the navigator is not attached yet (dashboard boot bind), that
/// dialog is shown on the next frame instead of dropped.
/// After a finished bind, a leftover stash is
/// taken next so a later deeplink is not stuck behind a spent POST.
Future<void> bindPendingReferralCode(GoRouter router, {String? code}) async {
  if (code != null) {
    await stashPendingReferralCode(code);
  }
  if (_bindInFlight) return;
  _bindInFlight = true;
  try {
    while (true) {
      // Take before POST so a parallel boot bind cannot send the same code twice.
      final resolved = await takePendingReferralCode();
      if (resolved == null || resolved.isEmpty) return;
      final retryLater = await _bindTakenCode(router, resolved);
      if (retryLater) return;
    }
  } finally {
    _bindInFlight = false;
  }
}

Future<bool> _bindTakenCode(GoRouter router, String resolved) async {
  try {
    final result = await getIt<RealUnitReferralService>().bind(code: resolved);
    await _showPromoBindDialog(router, result);
    return false;
  } catch (error) {
    if (_shouldRetryBind(error)) {
      final latest = await peekPendingReferralCode();
      if (latest == null || latest.isEmpty) {
        await stashPendingReferralCode(resolved);
      }
      final popped = await _showUnavailableBindDialog(router, resolved);
      if (popped is ReferralBindResultDto) {
        await _showPromoBindDialog(router, popped);
        return false;
      }
      if (popped != null) {
        await _showInvalidBindDialog(router, popped);
        return false;
      }
      return true;
    }
    await _showInvalidBindDialog(router, error);
    return false;
  }
}

/// Show [show] now, or on the next frame if the navigator is not attached
/// yet. Does not wait for that frame so unit tests that never pump do not
/// hang; a widget tree that pumps afterwards still gets the dialog.
Future<void> _withBindContext(
  GoRouter router,
  Future<void> Function(BuildContext ctx) show,
) async {
  final ctx = router.routerDelegate.navigatorKey.currentContext;
  if (ctx != null && ctx.mounted) {
    await show(ctx);
    return;
  }
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final next = router.routerDelegate.navigatorKey.currentContext;
    if (next == null || !next.mounted) return;
    unawaited(show(next));
  });
}

Future<void> _showPromoBindDialog(
  GoRouter router,
  ReferralBindResultDto result,
) {
  return _withBindContext(router, (ctx) async {
    final s = S.of(ctx);
    final Widget? content;
    final Widget? title;
    if (result.isPromo) {
      final lang = Localizations.localeOf(ctx).languageCode;
      final text = result.campaignTextForLocale(lang);
      if (text == null || text.isEmpty) return;
      final textLang = result.campaignTextLang(lang);
      title = Text(s.referralPromoTitle);
      content = Text(text, locale: Locale(textLang));
    } else if (result.isInvite) {
      final inviter = result.displayInviterName;
      if (inviter == null) return;
      title = null;
      content = Text(s.referralInviteRecognized(inviter));
    } else {
      return;
    }
    await showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: title,
        content: SingleChildScrollView(child: content),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(S.of(dialogContext).close),
          ),
        ],
      ),
    );
  });
}

Future<Object?> _showUnavailableBindDialog(
  GoRouter router,
  String code,
) async {
  Object? popped;
  Future<void> present(BuildContext ctx, {required bool awaited}) async {
    popped = await showDialog<Object>(
      context: ctx,
      barrierDismissible: false,
      builder: (dialogContext) => _UnavailableBindDialog(
        code: code,
        router: router,
        awaited: awaited,
      ),
    );
  }

  final ctx = router.routerDelegate.navigatorKey.currentContext;
  if (ctx != null && ctx.mounted) {
    await present(ctx, awaited: true);
    return popped;
  }
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final next = router.routerDelegate.navigatorKey.currentContext;
    if (next == null || !next.mounted) return;
    unawaited(present(next, awaited: false));
  });
  return null;
}

class _UnavailableBindDialog extends StatefulWidget {
  final String code;
  final GoRouter router;
  final bool awaited;

  const _UnavailableBindDialog({
    required this.code,
    required this.router,
    required this.awaited,
  });

  @override
  State<_UnavailableBindDialog> createState() => _UnavailableBindDialogState();
}

class _UnavailableBindDialogState extends State<_UnavailableBindDialog> {
  bool _retrying = false;

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    Object? popped;
    var code = await takePendingReferralCode();
    if (code == null || code.isEmpty) code = widget.code;
    try {
      popped = await getIt<RealUnitReferralService>().bind(code: code);
    } catch (error) {
      if (_shouldRetryBind(error)) {
        final latest = await peekPendingReferralCode();
        if (latest == null || latest.isEmpty) {
          await stashPendingReferralCode(code);
        }
        if (mounted) setState(() => _retrying = false);
        return;
      }
      popped = error;
    }
    if (!mounted) return;
    Navigator.of(context).pop(popped);
    if (widget.awaited) return;
    if (popped is ReferralBindResultDto) {
      final result = popped;
      unawaited(() async {
        await _showPromoBindDialog(widget.router, result);
        await bindPendingReferralCode(widget.router);
      }());
    } else {
      unawaited(_showInvalidBindDialog(widget.router, popped));
    }

  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: Text(S.of(context).referralCodeUnavailable),
      actions: [
        AppFilledButton(
          label: S.of(context).retry,
          autofocus: !_retrying,
          fullWidth: false,
          variant: FilledButtonVariant.secondary,
          state: _retrying
              ? FilledButtonState.loading
              : FilledButtonState.idle,
          onPressed: _retrying ? null : _retry,
        ),
        TextButton(
          onPressed: _retrying
              ? null
              : () => Navigator.of(context).pop(),
          child: Text(S.of(context).close),
        ),
      ],
    );
  }
}

Future<void> _showInvalidBindDialog(GoRouter router, Object error) {
  final token = referralErrorMessage(error);
  return _withBindContext(router, (ctx) async {
    await showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          localizedReferralErrorTitle(dialogContext, token),
          style: TextStyle(color: RealUnitColors.status.red600),
        ),
        content: Text(
          localizedReferralError(dialogContext, token),
          style: TextStyle(color: RealUnitColors.status.red600),
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(S.of(dialogContext).close),
          ),
        ],
      ),
    );
  });
}

bool _shouldRetryBind(Object error) {
  if (error is! ApiException) return true;
  if (isReferralRouteMissing(error.message)) return true;
  final status = error.statusCode;
  if (status == null) return true;
  return status >= 500 || status == 401 || status == 408 || status == 429;
}

/// Deferred bind used from redirects — re-checks PIN unlock at execution time.
void scheduleReferralBind(GoRouter router, String code) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(() async {
      await stashPendingReferralCode(code);
      final pinState = getIt<PinAuthCubit>().state;
      if (!(pinState.isPinVerified && pinState.isPinSetup)) {
        return;
      }
      await bindPendingReferralCode(router);
    }());
  });
}
