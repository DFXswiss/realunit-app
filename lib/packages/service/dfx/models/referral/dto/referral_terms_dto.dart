import 'package:realunit_wallet/packages/service/dfx/models/referral/locale_text.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/referral_json_list.dart';

/// `GET /v1/realunit/referral/terms`. Markdown is authored on the API;
/// the app renders it 1:1. Bundled assets are a fallback only.
class ReferralTermsDto {
  final String version;
  final String markdown;
  final String? markdownEn;

  const ReferralTermsDto({
    required this.version,
    required this.markdown,
    this.markdownEn,
  });

  String textForLang(String languageCode) {
    if (languageCode == 'en') {
      return firstNonEmpty([markdownEn, markdown]) ?? '';
    }
    return firstNonEmpty([markdown, markdownEn]) ?? '';
  }

  factory ReferralTermsDto.fromJson(Map<String, dynamic> json) {
    return ReferralTermsDto(
      version: referralJsonString(json['version']) ?? '',
      markdown: referralJsonString(json['markdown']) ?? '',
      markdownEn: referralJsonString(json['markdownEn']),
    );
  }
}
