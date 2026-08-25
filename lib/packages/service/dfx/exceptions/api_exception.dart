import 'dart:convert';

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

  /// Builds an [ApiException] from an HTTP error body that may or may not be JSON.
  ///
  /// JSON objects go through [fromJson] (KYC/registration subclasses preserved).
  /// Non-JSON or non-object bodies yield an empty [message] — never the raw body.
  factory ApiException.fromBody(String body, {required int httpStatusCode}) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return ApiException.fromJson(decoded, httpStatusCode: httpStatusCode);
      }
    } on FormatException {
      // Non-JSON body (plain text, HTML, empty). No API user-facing text.
    }
    return ApiException(
      statusCode: httpStatusCode,
      code: 'UNKNOWN',
      message: '',
    );
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

  /// Normalizes the JSON `message` field. Null/empty means the API sent no
  /// user-facing text — callers must not invent a substitute.
  static String? userFacingMessageFromJson(Object? message) {
    if (message == null) {
      return null;
    }
    if (message is List) {
      final joined = message.map((item) => item.toString()).join(', ');
      return joined.isEmpty ? null : joined;
    }
    final text = message.toString();
    return text.isEmpty ? null : text;
  }
}
