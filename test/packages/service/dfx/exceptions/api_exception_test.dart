import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/payment/buy_exceptions.dart';

void main() {
  group('$ApiException', () {
    group('fromJson', () {
      test('uses statusCode from JSON body when present', () {
        final exception = ApiException.fromJson(
          {'statusCode': 404, 'message': 'Not found'},
          httpStatusCode: 500,
        );

        expect(exception.statusCode, 404);
        expect(exception.message, 'Not found');
        expect(exception.code, 'UNKNOWN');
      });

      test('falls back to httpStatusCode when JSON body has no statusCode', () {
        final exception = ApiException.fromJson(
          {'code': 'TFA_REQUIRED', 'message': '2FA required (strict)', 'level': 'strict'},
          httpStatusCode: 403,
        );

        expect(exception.statusCode, 403);
        expect(exception.code, 'TFA_REQUIRED');
        expect(exception.message, '2FA required (strict)');
      });

      test('statusCode is null when neither JSON body nor httpStatusCode provide it', () {
        final exception = ApiException.fromJson(
          {'code': 'SOME_ERROR', 'message': 'Something went wrong'},
        );

        expect(exception.statusCode, isNull);
        expect(exception.code, 'SOME_ERROR');
      });

      test('handles message as List', () {
        final exception = ApiException.fromJson(
          {'message': ['error1', 'error2']},
          httpStatusCode: 400,
        );

        expect(exception.message, 'error1, error2');
        expect(exception.statusCode, 400);
      });

      test('creates KycLevelRequiredException with httpStatusCode', () {
        final exception = ApiException.fromJson(
          {
            'code': 'KYC_LEVEL_REQUIRED',
            'message': 'KYC level too low',
            'requiredLevel': 30,
            'currentLevel': 20,
          },
          httpStatusCode: 403,
        );

        expect(exception, isA<KycLevelRequiredException>());
        expect(exception.statusCode, 403);
        final kyc = exception as KycLevelRequiredException;
        expect(kyc.requiredLevel, 30);
        expect(kyc.currentLevel, 20);
        expect(kyc.context, isNull);
      });

      test('creates KycLevelRequiredException with context from JSON', () {
        final exception = ApiException.fromJson(
          {
            'code': 'KYC_LEVEL_REQUIRED',
            'message': 'KYC level too low',
            'requiredLevel': 30,
            'currentLevel': 20,
            'context': 'RealunitBuy',
          },
          httpStatusCode: 403,
        );

        expect(exception, isA<KycLevelRequiredException>());
        final kyc = exception as KycLevelRequiredException;
        expect(kyc.context, 'RealunitBuy');
      });

      test('creates RegistrationRequiredException with httpStatusCode', () {
        final exception = ApiException.fromJson(
          {'code': 'REGISTRATION_REQUIRED', 'message': 'Please register first'},
          httpStatusCode: 403,
        );

        expect(exception, isA<RegistrationRequiredException>());
        expect(exception.statusCode, 403);
        expect(exception.message, 'Please register first');
        expect((exception as RegistrationRequiredException).context, isNull);
      });

      test('creates RegistrationRequiredException with context from JSON', () {
        final exception = ApiException.fromJson(
          {
            'code': 'REGISTRATION_REQUIRED',
            'message': 'Please register first',
            'context': 'RealunitSell',
          },
          httpStatusCode: 403,
        );

        expect(exception, isA<RegistrationRequiredException>());
        final reg = exception as RegistrationRequiredException;
        expect(reg.context, 'RealunitSell');
      });
    });

    group('userFacingMessage', () {
      test('returns ApiException.message 1:1', () {
        const error = ApiException(
          statusCode: 503,
          code: 'AKTIONARIAT_UNAVAILABLE',
          message: 'Price source is temporarily unavailable',
        );

        expect(
          ApiException.userFacingMessage(error),
          'Price source is temporarily unavailable',
        );
        expect(
          ApiException.userFacingMessage(error),
          isNot(contains('RealUnitApiException')),
        );
      });

      test('returns Object.toString for non-API errors', () {
        expect(
          ApiException.userFacingMessage(Exception('socket closed')),
          'Exception: socket closed',
        );
      });
    });
  });
}
