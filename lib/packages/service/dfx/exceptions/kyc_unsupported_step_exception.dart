import 'package:realunit_wallet/packages/service/dfx/models/kyc/kyc_level.dart';

/// Reported — never thrown — when the API routes an account to a KYC step this
/// app has no screen for, or reports a pending review whose step list holds no
/// required step we can name.
///
/// The app maps a subset of [KycStepName] to screens; anything outside it lands
/// on the generic handoff page. Nothing else marks that: every request in the
/// flow returns 200, so without this event the only signal that the mapping
/// table has a gap is a user complaint.
///
/// [stepName] is the API's wire identifier for the step, or null when the API
/// named no step at all. It carries nothing about the user.
class KycUnsupportedStepException implements Exception {
  final KycStepName? stepName;

  const KycUnsupportedStepException(this.stepName);

  @override
  String toString() =>
      'KycUnsupportedStepException: no screen for KYC step '
      '${stepName?.value ?? '<none reported>'}';
}
