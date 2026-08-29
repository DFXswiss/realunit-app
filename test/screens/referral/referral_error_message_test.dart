import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/screens/referral/referral_error_message.dart';

void main() {
  test('maps TimeoutException to the unavailable token', () {
    expect(
      referralErrorMessage(TimeoutException('summary')),
      referralUnavailableMessage,
    );
    expect(
      referralErrorMessage(Exception('down')),
      referralUnavailableMessage,
    );
  });

  test('maps unmounted NestJS Cannot GET to the unavailable token', () {
    expect(
      referralErrorMessage(
        const ApiException(
          statusCode: 404,
          code: 'NOT_FOUND',
          message: 'Cannot GET /v1/realunit/referral/summary',
        ),
      ),
      referralUnavailableMessage,
    );
    expect(
      referralErrorMessage(
        const ApiException(
          statusCode: 404,
          code: 'NOT_FOUND',
          message: 'Route GET:/v1/realunit/referral/summary not found',
        ),
      ),
      referralUnavailableMessage,
    );
  });

  test('maps 503 UNAVAILABLE persist failure to the unavailable token', () {
    expect(
      referralErrorMessage(
        const ApiException(
          statusCode: 503,
          code: 'UNAVAILABLE',
          message: 'persist failed',
        ),
      ),
      referralUnavailableMessage,
    );
  });

  test('maps 503 UNAVAILABLE holding lookup failed to the unavailable token', () {
    expect(
      referralErrorMessage(
        const ApiException(
          statusCode: 503,
          code: 'UNAVAILABLE',
          message: 'holding lookup failed',
        ),
      ),
      referralUnavailableMessage,
    );
  });

  test('maps create 4xx codes to localized tokens', () {
    expect(
      referralErrorMessage(
        const ApiException(
          statusCode: 403,
          code: 'NOT_ELIGIBLE',
          message: 'holding below min',
        ),
      ),
      referralNotEligibleMessage,
    );
    expect(
      referralErrorMessage(
        const ApiException(
          statusCode: 409,
          code: 'NEEDS_TERMS',
          message: 'terms not accepted',
        ),
      ),
      referralNeedsTermsMessage,
    );
    expect(
      referralErrorMessage(
        const ApiException(
          statusCode: 400,
          code: 'INVALID',
          message: 'guestName required',
        ),
      ),
      referralGuestNameMessage,
    );
    expect(
      referralErrorMessage(
        const ApiException(
          statusCode: 400,
          code: 'INVALID',
          message: 'accepted must be true',
        ),
      ),
      referralNeedsTermsMessage,
    );
  });

  test('maps QUOTA and leftover 4xx to tokens, never engine English', () {
    expect(
      referralErrorMessage(
        const ApiException(
          statusCode: 400,
          code: 'QUOTA',
          message: 'limit',
        ),
      ),
      referralQuotaMessage,
    );
    expect(
      referralErrorMessage(
        const ApiException(
          statusCode: 400,
          code: 'NOPE',
          message: 'employees excluded',
        ),
      ),
      referralInvalidMessage,
    );
  });

  test('maps bind and lookup business codes to tokens', () {
    expect(
      referralErrorMessage(
        const ApiException(
          statusCode: 410,
          code: 'SPENT',
          message: 'invite already bound',
        ),
      ),
      referralSpentMessage,
    );
    expect(
      referralErrorMessage(
        const ApiException(
          statusCode: 410,
          code: 'EXPIRED',
          message: 'promo expired',
        ),
      ),
      referralInvalidMessage,
    );
    expect(
      referralErrorMessage(
        const ApiException(
          statusCode: 404,
          code: 'NOT_FOUND',
          message: 'unknown code',
        ),
      ),
      referralInvalidMessage,
    );
    expect(
      referralErrorMessage(
        const ApiException(
          statusCode: 409,
          code: 'SELF_REFERRAL',
          message: 'cannot bind own invite',
        ),
      ),
      referralSelfReferralMessage,
    );
    expect(
      referralErrorMessage(
        const ApiException(
          statusCode: 409,
          code: 'ALREADY_BOUND',
          message: 'already bound',
        ),
      ),
      referralAlreadyBoundMessage,
    );
    expect(
      referralErrorMessage(
        const ApiException(
          statusCode: 409,
          code: 'ALREADY_REGISTERED',
          message: 'invitee already registered',
        ),
      ),
      referralAlreadyRegisteredMessage,
    );
  });

  testWidgets('unknown leftover tokens map to unavailable copy, never raw English', (
    tester,
  ) async {
    late String unknown;
    late String quota;
    late String spentTitle;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        home: Builder(
          builder: (context) {
            unknown = localizedReferralError(context, 'nope');
            quota = localizedReferralError(context, referralQuotaMessage);
            spentTitle = localizedReferralErrorTitle(
              context,
              referralSpentMessage,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(
      unknown,
      'Wir konnten den Code gerade nicht prüfen. Bitte versuche es später erneut.',
    );
    expect(unknown, isNot('nope'));
    expect(
      quota,
      'In diesem Quartal sind keine weiteren Prämien möglich.',
    );
    expect(spentTitle, 'Code bereits eingelöst');
  });
}
