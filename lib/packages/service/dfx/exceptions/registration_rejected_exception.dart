import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';

/// A content-level rejection of the registration submit itself.
///
/// Thrown exclusively by `RealUnitRegistrationService` for a non-auth 4xx
/// response of `register/complete`, so the UI can safely attribute the server
/// reason to the user's entries ("check your entries and submit again").
/// Auth (401/403) and rate-limit (429) responses, 5xx, transport errors, and
/// failures of any other call stay plain [ApiException]s — for those, that
/// instruction would be wrong.
class RegistrationRejectedException extends ApiException {
  const RegistrationRejectedException({
    super.statusCode,
    required super.code,
    required super.message,
  });

  @override
  String toString() =>
      'RegistrationRejectedException: $message (code: $code, statusCode: $statusCode)';
}
