import 'package:realunit_wallet/setup/routing/referral_pending_code.dart';

/// Persist a looked-up invite/promo code after KYC submit.
///
/// Null means skip or invalid lookup: leave any deeplink stash in place so
/// automatic takeover still binds. Only a resolved (empty-cleared or valid)
/// code is written.
Future<void> stashResolvedReferralCode(String? resolved) async {
  if (resolved == null) return;
  await stashPendingReferralCode(resolved);
}
