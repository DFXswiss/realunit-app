import 'package:realunit_wallet/packages/service/dfx/models/referral/locale_text.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/referral_json_list.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/referral_kind.dart';

/// Public `GET /v1/realunit/referral/code/:code` payload for registration
/// preview and the website landing. Accepts `Invite`/`Promo` in either case.
class ReferralCodeLookupDto {
  final String kind;
  final String? inviterName;
  final String? inviteeName;
  final String? actionText;
  final String? actionTextEn;
  final String? campaignText;
  final String? campaignTextEn;
  final num? minBuyRealu;
  final DateTime? validUntil;
  final num? redemptionCap;

  const ReferralCodeLookupDto({
    required this.kind,
    this.inviterName,
    this.inviteeName,
    this.actionText,
    this.actionTextEn,
    this.campaignText,
    this.campaignTextEn,
    this.minBuyRealu,
    this.validUntil,
    this.redemptionCap,
  });

  bool get isPromo => kind.toLowerCase() == 'promo';
  bool get isInvite => kind.toLowerCase() == 'invite';

  /// Inviter shown on registration. Whitespace-only API fields are absent.
  String? get displayInviterName => firstNonEmpty([inviterName]);

  /// Locale-aware campaign / action wording. EN falls back to DE when the EN
  /// field is absent or empty.
  String? campaignTextForLocale(String languageCode) {
    if (languageCode == 'en') {
      return firstNonEmpty([
        actionTextEn,
        campaignTextEn,
        actionText,
        campaignText,
      ]);
    }
    return firstNonEmpty([
      actionText,
      campaignText,
      actionTextEn,
      campaignTextEn,
    ]);
  }

  /// Language of the string [campaignTextForLocale] returns, so a DE fallback
  /// on an English UI can be tagged `locale: Locale('de')`.
  String campaignTextLang(String languageCode) {
    if (campaignTextForLocale(languageCode) == null) {
      return languageCode == 'en' ? 'en' : 'de';
    }
    if (languageCode == 'en') {
      return firstNonEmpty([campaignTextEn, actionTextEn]) != null ? 'en' : 'de';
    }
    return firstNonEmpty([actionText, campaignText]) != null ? 'de' : 'en';
  }

  factory ReferralCodeLookupDto.fromJson(Map<String, dynamic> json) {
    final kind = inferReferralKind(json);
    final minBuy = referralJsonNum(json['minBuyRealu']);
    return ReferralCodeLookupDto(
      kind: kind,
      inviterName: referralPersonName(json['inviterName']),
      inviteeName: referralJsonString(json['inviteeName']),
      actionText: referralJsonString(json['actionText']),
      actionTextEn: referralJsonString(json['actionTextEn']),
      campaignText: referralJsonString(json['campaignText']),
      campaignTextEn: referralJsonString(json['campaignTextEn']),
      minBuyRealu: minBuy ?? (kind.toLowerCase() == 'promo' ? 200 : null),
      validUntil: referralJsonDate(json['validUntil']),
      redemptionCap: referralJsonNum(json['redemptionCap']),
    );
  }
}
