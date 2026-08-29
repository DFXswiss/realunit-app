import 'package:realunit_wallet/packages/service/dfx/models/referral/locale_text.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/referral_json_list.dart';

/// Resolves Invite vs Promo when the API omits `kind`.
/// Explicit `kind` always wins. Otherwise an inviter name is an invite;
/// campaign/action text without an inviter is a promo.
String inferReferralKind(
  Map<String, dynamic> json, {
  String fallback = 'invite',
}) {
  final raw = referralJsonString(json['kind']);
  if (raw != null) return raw;
  final inviter = referralJsonString(json['inviterName']);
  if (inviter != null) return 'invite';
  if (firstNonEmpty([
        referralJsonString(json['campaignText']),
        referralJsonString(json['campaignTextEn']),
        referralJsonString(json['actionText']),
        referralJsonString(json['actionTextEn']),
      ]) !=
      null) {
    return 'promo';
  }
  return fallback;
}
