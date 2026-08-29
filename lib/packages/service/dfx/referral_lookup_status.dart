import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';

/// Public lookup statuses that mean the code is invalid or spent.
/// Keep in sync with `mapResult` in realunit-web `public/js/lib/invite-core.js`.
/// Transport failures (5xx, 401, 408, 429) are not invalid — the code may still
/// work on retry and must not be shown as expired.
bool isReferralLookupInvalidStatus(int? status) {
  return status == 400 ||
      status == 404 ||
      status == 409 ||
      status == 410 ||
      status == 422;
}

/// NestJS 404/405 body when the referral route is not mounted yet
/// (`Cannot GET /v1/realunit/referral/code/…`, Fastify
/// `Route GET:/… not found`). That is not a spent code.
bool isReferralRouteMissing(String? message) {
  if (message == null) return false;
  final text = message.trim();
  if (RegExp(
    r'^Cannot (GET|HEAD|POST|PUT|PATCH|DELETE) ',
    caseSensitive: false,
  ).hasMatch(text)) {
    return true;
  }
  return RegExp(
    r'^Route (GET|HEAD|POST|PUT|PATCH|DELETE):',
    caseSensitive: false,
  ).hasMatch(text);
}

/// True only for a business rejection of this code. An unmounted route must
/// not light the «invalid / expired» copy or drop a stashed invite.
bool isReferralLookupInvalid(ApiException error) {
  if (isReferralRouteMissing(error.message)) return false;
  return isReferralLookupInvalidStatus(error.statusCode);
}
