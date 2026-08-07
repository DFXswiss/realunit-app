/// Mirror of the server-side `RealUnitLegalAgreement` enum on
/// `GET`/`PUT /v1/realunit/legal`. The API owns which agreements exist and
/// which are still outstanding for a wallet; the app forwards them 1:1 — see
/// CONTRIBUTING.md "API as Decision Authority". Mirrors the `.value` /
/// `fromValue` shape of `KycStepName` in `models/kyc/kyc_level.dart`.
enum RealUnitLegalAgreement {
  residenceConfirmation,
  taxDomicileSelfCertification,
  realUnitPrivacyPolicy,
  realUnitRegistrationAgreement,
  aktionariatTermsOfService,
  dfxTermsAndConditions,
}

extension RealUnitLegalAgreementExtension on RealUnitLegalAgreement {
  String get value {
    switch (this) {
      case RealUnitLegalAgreement.residenceConfirmation:
        return 'ResidenceConfirmation';
      case RealUnitLegalAgreement.taxDomicileSelfCertification:
        return 'TaxDomicileSelfCertification';
      case RealUnitLegalAgreement.realUnitPrivacyPolicy:
        return 'RealUnitPrivacyPolicy';
      case RealUnitLegalAgreement.realUnitRegistrationAgreement:
        return 'RealUnitRegistrationAgreement';
      case RealUnitLegalAgreement.aktionariatTermsOfService:
        return 'AktionariatTermsOfService';
      case RealUnitLegalAgreement.dfxTermsAndConditions:
        return 'DfxTermsAndConditions';
    }
  }

  static RealUnitLegalAgreement fromValue(String value) {
    switch (value) {
      case 'ResidenceConfirmation':
        return RealUnitLegalAgreement.residenceConfirmation;
      case 'TaxDomicileSelfCertification':
        return RealUnitLegalAgreement.taxDomicileSelfCertification;
      case 'RealUnitPrivacyPolicy':
        return RealUnitLegalAgreement.realUnitPrivacyPolicy;
      case 'RealUnitRegistrationAgreement':
        return RealUnitLegalAgreement.realUnitRegistrationAgreement;
      case 'AktionariatTermsOfService':
        return RealUnitLegalAgreement.aktionariatTermsOfService;
      case 'DfxTermsAndConditions':
        return RealUnitLegalAgreement.dfxTermsAndConditions;
      default:
        throw ArgumentError('Unknown RealUnitLegalAgreement value: $value');
    }
  }
}
