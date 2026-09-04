import 'package:realunit_wallet/packages/service/dfx/models/referral/locale_text.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/referral_json_list.dart';

/// Response from `POST /v1/realunit/referral/invites`.
/// The server generates the personalised share text; the app renders it 1:1.
class ReferralCreatedInviteDto {
  final String code;
  final String url;
  final String guestName;
  final String? copyText;
  final String? copyTextEn;
  final String? inviterName;

  const ReferralCreatedInviteDto({
    required this.code,
    required this.url,
    required this.guestName,
    this.copyText,
    this.copyTextEn,
    this.inviterName,
  });

  /// Locale-aware share wording. EN falls back to DE when the EN field is absent
  /// or empty.
  String? copyTextForLocale(String languageCode) {
    if (languageCode == 'en') {
      return firstNonEmpty([copyTextEn, copyText]);
    }
    return firstNonEmpty([copyText, copyTextEn]);
  }

  factory ReferralCreatedInviteDto.fromJson(Map<String, dynamic> json) {
    final code = referralJsonString(json['code']);
    final url = referralInviteUrl(url: json['url'], code: code);
    final guestName = referralJsonString(json['guestName']) ?? '';
    if (code == null || url == null) {
      throw const FormatException('referral created invite missing fields');
    }
    return ReferralCreatedInviteDto(
      code: code,
      url: url,
      guestName: guestName,
      copyText: referralJsonString(json['copyText']),
      copyTextEn: referralJsonString(json['copyTextEn']),
      inviterName: referralPersonName(json['inviterName']),
    );
  }
}
