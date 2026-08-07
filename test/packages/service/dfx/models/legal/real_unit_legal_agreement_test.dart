import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/packages/service/dfx/models/legal/real_unit_legal_agreement.dart';

void main() {
  group('RealUnitLegalAgreement', () {
    test('value <-> fromValue round-trips every agreement', () {
      for (final agreement in RealUnitLegalAgreement.values) {
        expect(RealUnitLegalAgreementExtension.fromValue(agreement.value), agreement);
      }
    });

    test('fromValue throws ArgumentError on an unknown value', () {
      expect(
        () => RealUnitLegalAgreementExtension.fromValue('NopeNotAnAgreement'),
        throwsArgumentError,
      );
    });
  });
}
