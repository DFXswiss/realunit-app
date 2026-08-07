import 'package:realunit_wallet/packages/service/dfx/models/legal/dto/real_unit_legal_agreement_status_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/legal/real_unit_legal_agreement.dart';

/// Server-side legal-acceptance state for the current wallet, returned by both
/// `GET` and `PUT /v1/realunit/legal`. `allAccepted` is the authoritative gate
/// for the legal disclaimer in `KycCubit` — see CONTRIBUTING.md "API as
/// Decision Authority".
class RealUnitLegalInfoDto {
  final List<RealUnitLegalAgreementStatusDto> agreements;
  final bool allAccepted;

  const RealUnitLegalInfoDto({
    required this.agreements,
    required this.allAccepted,
  });

  /// The agreements the user has not yet accepted at the current version.
  /// Forwarded verbatim to `PUT /v1/realunit/legal` so the app records exactly
  /// what the server still needs.
  List<RealUnitLegalAgreement> get outstandingAgreements =>
      agreements.where((a) => !a.accepted).map((a) => a.agreement).toList();

  factory RealUnitLegalInfoDto.fromJson(Map<String, dynamic> json) {
    return RealUnitLegalInfoDto(
      agreements: (json['agreements'] as List<dynamic>)
          .map((e) => RealUnitLegalAgreementStatusDto.fromJson(e as Map<String, dynamic>))
          .toList(),
      allAccepted: json['allAccepted'] as bool,
    );
  }
}
