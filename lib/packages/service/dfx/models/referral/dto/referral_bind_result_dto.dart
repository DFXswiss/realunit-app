/// Response from `POST /v1/realunit/referral/bind`.
/// For `kind == Promo`, [campaignText] / [campaignTextEn] carry the prescribed
/// wording from the API — do not compose campaign copy in the app.
class ReferralBindResultDto {
  final String kind;
  final String? campaignText;
  final String? campaignTextEn;
  final num? minBuyRealu;
  final DateTime? validUntil;
  final num? redemptionCap;

  const ReferralBindResultDto({
    required this.kind,
    this.campaignText,
    this.campaignTextEn,
    this.minBuyRealu,
    this.validUntil,
    this.redemptionCap,
  });

  bool get isPromo => kind == 'Promo';
  bool get isInvite => kind == 'Invite';

  /// Locale-aware campaign wording. EN falls back to DE when the EN field is absent.
  String? campaignTextForLocale(String languageCode) {
    if (languageCode == 'en') {
      return campaignTextEn ?? campaignText;
    }
    return campaignText ?? campaignTextEn;
  }

  factory ReferralBindResultDto.fromJson(Map<String, dynamic> json) {
    return ReferralBindResultDto(
      kind: json['kind'] as String,
      campaignText: json['campaignText'] as String?,
      campaignTextEn: json['campaignTextEn'] as String?,
      minBuyRealu: json['minBuyRealu'] as num?,
      validUntil: json['validUntil'] != null
          ? DateTime.parse(json['validUntil'] as String)
          : null,
      redemptionCap: json['redemptionCap'] as num?,
    );
  }
}
