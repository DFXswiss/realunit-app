import 'package:realunit_wallet/packages/io/normalize_referral_code.dart';

/// Extracts an invite/promo code from a Play Store install-referrer string.
///
/// The website attaches `referrer=invite=<code>`. Play delivers that as
/// `invite=<code>` (sometimes still percent-encoded, sometimes twice).
/// Empty or foreign `invite=` does not hide a later `promo=` / `code=`.
/// A share message or raw invite/promo URL as the whole referrer is
/// unwrapped the same way, including Facebook `l.php?u=` / Google `url?q=`
/// wrappers, Outlook Safe Links, Proofpoint URL Defense, a path-nested
/// landing URL, or an AMP/CDN host-in-path URL. Fullwidth / CJK / HTML
/// folds run first so `realunit。app` still matches.
/// A payload nested in `utm_content` or `referrer=`
/// (and Facebook `u=` / Google `q=` / Outlook `url=` / email `link=`)
/// is unwrapped too — each key is tried until one yields a code, so a
/// campaign name in `utm_content` does not hide `u=` / `link=`. A whole
/// referrer that only mentions `realunit.app` (no code) still tries those keys.
/// Returns null when no code is present. Caps at 32 characters, same
/// as [stashPendingReferralCode] and the API.
String? parseInviteCodeFromReferrer(String? raw) => _parseInviteCodeFromReferrer(raw, 0);

String? _parseInviteCodeFromReferrer(String? raw, int depth) {
  if (raw == null || raw.isEmpty || depth > 2) return null;

  var decoded = stripInvisibleReferralChars(_decodeReferrer(raw));
  final first = _codeFromDecodedReferrer(decoded, depth);
  if (first != null) return first;

  final twice = stripInvisibleReferralChars(_decodeReferrer(decoded));
  if (twice == decoded) return null;
  return _codeFromDecodedReferrer(twice, depth);
}

String _decodeReferrer(String raw) {
  try {
    return Uri.decodeComponent(raw);
  } catch (_) {
    return raw;
  }
}

String? _codeFromDecodedReferrer(String decoded, int depth) {
  decoded = foldReferralPastedText(decoded);
  Map<String, String> params = const {};
  try {
    params = Uri.splitQueryString(decoded);
  } catch (_) {
    // Folded fullwidth / CJK referrers can still contain `%` that is not
    // a valid percent-escape. Fall through to payload unwrap.
  }
  const codeKeys = ['invite', 'promo', 'code'];
  for (final key in codeKeys) {
    final raw = params[key];
    if (raw == null || raw.isEmpty) continue;
    final fromParams = referralCodeFromInput(raw);
    if (fromParams != null) return fromParams;
  }
  // Campaigns sometimes pass the share text or a raw invite URL as the
  // whole referrer, with no invite=/promo=/code= key. A tracking URL that
  // only mentions realunit.app (no code) must not hide a later wrapper key.
  if (_looksLikeReferralPayload(decoded)) {
    final fromPayload = referralCodeFromInput(decoded);
    if (fromPayload != null) return fromPayload;
  }
  // Play / ads sometimes nest invite= or the landing URL in utm_content
  // or a nested referrer= / Facebook u= / Google q= / Outlook url= /
  // email link= key (same unwrap as the KYC paste / landing). A campaign
  // name in utm_content must not hide a later key that carries the code.
  const nestedKeys = ['utm_content', 'referrer', 'u', 'q', 'url', 'link'];
  for (final key in nestedKeys) {
    final nested = params[key];
    if (nested == null || nested.isEmpty || nested == decoded) continue;
    final fromNested = _parseInviteCodeFromReferrer(nested, depth + 1);
    if (fromNested != null) return fromNested;
  }
  return null;
}

bool _looksLikeReferralPayload(String value) {
  final lower = value.toLowerCase();
  return lower.contains('realunit.app') ||
      lower.contains('realunit-wallet:') ||
      lower.contains('intent://') ||
      lower.contains('android-app://swiss.realunit.app/') ||
      lower.contains('ios-app://') ||
      lower.contains('l.facebook.com/') ||
      lower.contains('facebook.com/l.php') ||
      lower.contains('google.com/url') ||
      lower.contains('safelinks.protection.outlook.com') ||
      lower.contains('urldefense.proofpoint.com') ||
      lower.contains('urldefense.com') ||
      lower.startsWith('invite?') ||
      lower.startsWith('promo?') ||
      lower.startsWith('invite#') ||
      lower.startsWith('promo#') ||
      lower.startsWith('invite/') ||
      lower.startsWith('promo/') ||
      lower.startsWith('/invite') ||
      lower.startsWith('/promo');
}
