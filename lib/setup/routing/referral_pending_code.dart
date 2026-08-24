import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences key for a referral/promo invite code delivered via
/// deeplink before the user is authenticated.
const String pendingReferralCodeKey = 'pending_referral_code';

/// In-process stash mirroring [stashPendingPaymentDeeplink]: last-write-wins,
/// no queue. Survives warm-locked PIN screens within the same process.
String? _pendingReferralCode;

/// Persist [code] for post-unlock / post-KYC bind.
///
/// Play Store install referrer is handled on the website (`&referrer=`); the
/// app only needs the code when a custom-scheme or https App Link delivers it
/// after install. If the OS drops the first open, the user re-taps the invite
/// link and this stash is filled again — that re-tap path is intentional.
Future<void> stashPendingReferralCode(String code) async {
  final trimmed = code.trim();
  if (trimmed.isEmpty) return;
  final capped = trimmed.length > 256 ? trimmed.substring(0, 256) : trimmed;
  _pendingReferralCode = capped;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(pendingReferralCodeKey, capped);
}

/// Returns and clears the pending code (memory + SharedPreferences).
Future<String?> takePendingReferralCode() async {
  final inMemory = _pendingReferralCode;
  _pendingReferralCode = null;
  final prefs = await SharedPreferences.getInstance();
  final stored = prefs.getString(pendingReferralCodeKey);
  await prefs.remove(pendingReferralCodeKey);
  final code = inMemory ?? stored;
  if (code == null || code.isEmpty) return null;
  return code;
}

/// Clears any stashed code without returning it.
Future<void> clearPendingReferralCode() async {
  _pendingReferralCode = null;
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(pendingReferralCodeKey);
}

/// Read-only peek (memory first, then SharedPreferences). Does not clear.
Future<String?> peekPendingReferralCode() async {
  if (_pendingReferralCode != null) return _pendingReferralCode;
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(pendingReferralCodeKey);
}

/// Synchronous in-memory peek for redirect tests / warm paths that already
/// stashed in this process. Does not read SharedPreferences.
String? peekPendingReferralCodeSync() => _pendingReferralCode;

/// Test-only: seed the in-memory stash without touching SharedPreferences.
void debugSetPendingReferralCodeSync(String? code) {
  _pendingReferralCode = code;
}
