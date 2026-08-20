import 'package:realunit_wallet/packages/service/dfx/exceptions/payment/buy_exceptions.dart';

class ApiException implements Exception {
  final int? statusCode;
  final String code;
  final String message;

  const ApiException({
    this.statusCode,
    required this.code,
    required this.message,
  });

  factory ApiException.fromJson(Map<String, dynamic> json, {int? httpStatusCode}) {
    final code = json['code'] as String?;

    switch (code) {
      case 'KYC_LEVEL_REQUIRED':
        return KycLevelRequiredException.fromJson(json, httpStatusCode: httpStatusCode);
      case 'REGISTRATION_REQUIRED':
        return RegistrationRequiredException.fromJson(json, httpStatusCode: httpStatusCode);
      default:
        final message = json['message'];
        return ApiException(
          statusCode: json['statusCode'] as int? ?? httpStatusCode,
          code: code ?? 'UNKNOWN',
          message: message is List ? message.join(', ') : message?.toString() ?? 'Unknown error',
        );
    }
  }

  @override
  String toString() => 'RealUnitApiException: $message (code: $code, statusCode: $statusCode)';

  /// User-visible text for an error thrown from a DFX API call.
  ///
  /// [ApiException] is shown 1:1 as [message]. Any other object has no API
  /// text; [Object.toString] is the remainder (transport, parse, local).
  static String userFacingMessage(Object error) {
    if (error is ApiException) {
      return error.message;
    }
    return error.toString();
  }
}
