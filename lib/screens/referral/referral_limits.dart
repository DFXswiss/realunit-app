import 'package:realunit_wallet/packages/io/normalize_referral_code.dart';

/// Guest-name cap for create-invite (UI field and cubit).
const maxReferralGuestNameLength = 80;

/// Newlines and Unicode spaces (nbsp, em/thin/ideographic) mapped to ASCII
/// space in the create-invite field and on submit.
final referralGuestNameSpaceChars = RegExp(
  r'[\n\r\t\u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000]+',
);

/// Single-line guest name for the share text («Hey Alice, …»).
/// Format characters are dropped; newlines/tabs and Unicode spaces
/// (nbsp, em/thin/ideographic) become ASCII spaces, runs collapse,
/// then trim and cap.
String sanitizeReferralGuestName(String raw) {
  var name = stripInvisibleReferralChars(raw);
  name = name.replaceAll(referralGuestNameSpaceChars, ' ');
  name = name.replaceAll(RegExp(r' +'), ' ').trim();
  if (name.length > maxReferralGuestNameLength) {
    name = name.substring(0, maxReferralGuestNameLength).trimRight();
  }
  return name;
}
