import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/kyc_unsupported_step_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/models/kyc/kyc_level.dart';

// The rendered string is the whole payload of the report — the crash reporter
// receives nothing else about the occurrence. If it does not name the step, the
// event cannot say which entry the client's mapping table is missing.
void main() {
  group('$KycUnsupportedStepException', () {
    test('names the step by its API wire identifier', () {
      const exception = KycUnsupportedStepException(KycStepName.residencePermit);

      expect(exception.stepName, KycStepName.residencePermit);
      expect(exception.toString(), contains(KycStepName.residencePermit.value));
    });

    test('renders readably when the API named no step at all', () {
      const exception = KycUnsupportedStepException(null);

      expect(exception.stepName, isNull);
      expect(exception.toString(), isNot(contains('null')));
      expect(exception.toString(), isNotEmpty);
    });
  });
}
