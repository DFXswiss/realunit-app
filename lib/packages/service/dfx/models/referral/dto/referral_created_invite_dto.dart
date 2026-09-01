/// Response from `POST /v1/realunit/referral/invites`.
/// `copyText` is a German-only API fallback; prefer i18n share text when available.
class ReferralCreatedInviteDto {
  final String code;
  final String url;
  final String guestName;
  final String? copyText;

  const ReferralCreatedInviteDto({
    required this.code,
    required this.url,
    required this.guestName,
    this.copyText,
  });

  factory ReferralCreatedInviteDto.fromJson(Map<String, dynamic> json) {
    return ReferralCreatedInviteDto(
      code: json['code'] as String,
      url: json['url'] as String,
      guestName: json['guestName'] as String,
      copyText: json['copyText'] as String?,
    );
  }
}
