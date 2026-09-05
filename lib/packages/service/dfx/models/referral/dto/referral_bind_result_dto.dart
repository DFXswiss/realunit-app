import 'package:realunit_wallet/packages/service/dfx/models/referral/locale_text.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/referral_json_list.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/referral_kind.dart';

/// Response from `POST /v1/realunit/referral/bind`.
/// For `kind == Promo`, [campaignText] / [campaignTextEn] carry the prescribed
/// wording from the API — do not compose campaign copy in the app.
/// For `kind == Invite`, [inviterName] is the Empfehler shown after a late bind.
class ReferralBindResultDto {
  final String kind;
  final String? inviterName;
  final String? inviteeName;
  final String? campaignText;
  final String? campaignTextEn;
  final String? actionText;
  final String? actionTextEn;
  final num? minBuyRealu;
  final DateTime? validUntil;
  final num? redemptionCap;

  const ReferralBindResultDto({
    required this.kind,
    this.inviterName,
    this.inviteeName,
    this.campaignText,
    this.campaignTextEn,
    this.actionText,
    this.actionTextEn,
    this.minBuyRealu,
    this.validUntil,
    this.redemptionCap,
  });

  bool get isPromo => kind.toLowerCase() == 'promo';
  bool get isInvite => kind.toLowerCase() == 'invite';

  /// Inviter shown after a successful invite bind. Whitespace-only is absent.
  String? get displayInviterName => firstNonEmpty([inviterName]);

  /// Locale-aware campaign wording. EN falls back to DE when the EN field is
  /// absent or empty.
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

  factory ReferralBindResultDto.fromJson(Map<String, dynamic> json) {
    final kind = inferReferralKind(json);
    final minBuy = referralJsonNum(json['minBuyRealu']);
    return ReferralBindResultDto(
      kind: kind,
      inviterName: referralPersonName(json['inviterName']),
      inviteeName: referralJsonString(json['inviteeName']),
      campaignText: referralJsonString(json['campaignText']),
      campaignTextEn: referralJsonString(json['campaignTextEn']),
      actionText: referralJsonString(json['actionText']),
      actionTextEn: referralJsonString(json['actionTextEn']),
      // Promo first-purchase floor. Spec default is 200 REALU when omitted.
      minBuyRealu: minBuy ?? (kind.toLowerCase() == 'promo' ? 200 : null),
      validUntil: referralJsonDate(json['validUntil']),
      redemptionCap: referralJsonNum(json['redemptionCap']),
    );
  }
}
