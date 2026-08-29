import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:realunit_wallet/packages/io/install_referrer_port.dart';
import 'package:realunit_wallet/packages/io/parse_install_referrer.dart';
import 'package:realunit_wallet/setup/routing/referral_pending_code.dart';

/// SharedPreferences flag: the Play referrer has been read for this install.
const String installReferrerConsumedKey = 'install_referrer_consumed';

/// Reads the Play install referrer once per install and stashes an invite
/// or promo code for post-unlock bind. Failures and a null read (Play not
/// ready / timeout) do not set the consumed flag, so the next cold start
/// can retry. A hung native read is timed out in Dart so [finishSetup]
/// cannot stall.
Future<void> captureInstallReferrer({
  required SharedPreferences prefs,
  required InstallReferrerPort port,
}) async {
  if (prefs.getBool(installReferrerConsumedKey) == true) return;

  final String? raw;
  try {
    // Native already replies null after 3s. A Dart budget slightly above
    // that unsticks finishSetup if the channel never returns.
    raw = await port.readInstallReferrer().timeout(
      const Duration(seconds: 4),
    );
  } catch (_) {
    return;
  }

  // Native replies null on timeout / Play not ready. Do not consume — the
  // next cold start must retry or a late referrer is lost forever.
  if (raw == null) return;

  await prefs.setBool(installReferrerConsumedKey, true);
  final code = parseInviteCodeFromReferrer(raw);
  if (code != null) {
    await stashPendingReferralCode(code);
  }
}
