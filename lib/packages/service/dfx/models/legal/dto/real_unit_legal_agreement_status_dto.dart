import 'package:realunit_wallet/packages/service/dfx/models/legal/real_unit_legal_agreement.dart';

/// Per-agreement acceptance status as reported by `GET /v1/realunit/legal`.
/// `accepted` is the API's own verdict (current version vs. accepted version) —
/// the app renders it 1:1 and never re-derives it from the version fields. The
/// version fields are carried for completeness/display only.
class RealUnitLegalAgreementStatusDto {
  final RealUnitLegalAgreement agreement;
  final String currentVersion;
  final String? acceptedVersion;
  final bool accepted;

  const RealUnitLegalAgreementStatusDto({
    required this.agreement,
    required this.currentVersion,
    this.acceptedVersion,
    required this.accepted,
  });

  factory RealUnitLegalAgreementStatusDto.fromJson(Map<String, dynamic> json) {
    return RealUnitLegalAgreementStatusDto(
      agreement: RealUnitLegalAgreementExtension.fromValue(json['agreement'] as String),
      currentVersion: json['currentVersion'] as String,
      acceptedVersion: json['acceptedVersion'] as String?,
      accepted: json['accepted'] as bool,
    );
  }
}
