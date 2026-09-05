import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_bind_result_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_referral_service.dart';
import 'package:realunit_wallet/screens/pin/bloc/auth/pin_auth_cubit.dart';
import 'package:realunit_wallet/setup/routing/referral_bind.dart';
import 'package:realunit_wallet/setup/routing/referral_pending_code.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/styles/themes.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockService extends Mock implements RealUnitReferralService {}

class _MockPinAuthCubit extends Mock implements PinAuthCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockService service;
  late GoRouter router;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    debugSetPendingReferralCodeSync(null);
    debugResetBindInFlight();
    service = _MockService();
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<RealUnitReferralService>(service);
    router = GoRouter(
      navigatorKey: GlobalKey<NavigatorState>(),
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: SizedBox()),
        ),
      ],
    );
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  test('keeps the stashed code when bind fails with a retryable error', () async {
    await stashPendingReferralCode('AB12CD');
    when(() => service.bind(code: 'AB12CD')).thenThrow(
      const ApiException(
        statusCode: 503,
        code: 'UNAVAILABLE',
        message: 'down',
      ),
    );

    await bindPendingReferralCode(router);

    expect(await peekPendingReferralCode(), 'AB12CD');
    verify(() => service.bind(code: 'AB12CD')).called(1);
  });

  test('keeps the stashed code when bind returns 401 or 429', () async {
    when(() => service.bind(code: 'AB12CD')).thenThrow(
      const ApiException(
        statusCode: 401,
        code: 'UNAUTHORIZED',
        message: 'auth',
      ),
    );
    await stashPendingReferralCode('AB12CD');
    await bindPendingReferralCode(router);
    expect(await peekPendingReferralCode(), 'AB12CD');

    when(() => service.bind(code: 'AB12CD')).thenThrow(
      const ApiException(
        statusCode: 429,
        code: 'RATE_LIMIT',
        message: 'slow down',
      ),
    );
    await bindPendingReferralCode(router);
    expect(await peekPendingReferralCode(), 'AB12CD');
    verify(() => service.bind(code: 'AB12CD')).called(2);
  });

  test('keeps the stashed code when bind returns 408', () async {
    await stashPendingReferralCode('AB12CD');
    when(() => service.bind(code: 'AB12CD')).thenThrow(
      const ApiException(
        statusCode: 408,
        code: 'TIMEOUT',
        message: 'slow',
      ),
    );

    await bindPendingReferralCode(router);

    expect(await peekPendingReferralCode(), 'AB12CD');
    verify(() => service.bind(code: 'AB12CD')).called(1);
  });

  test('keeps the stashed code when bind times out', () async {
    await stashPendingReferralCode('AB12CD');
    when(() => service.bind(code: 'AB12CD')).thenThrow(
      TimeoutException('bind'),
    );

    await bindPendingReferralCode(router);

    expect(await peekPendingReferralCode(), 'AB12CD');
    verify(() => service.bind(code: 'AB12CD')).called(1);
  });

  test('keeps the stash when bind hits an unmounted NestJS route', () async {
    await stashPendingReferralCode('AB12CD');
    when(() => service.bind(code: 'AB12CD')).thenThrow(
      const ApiException(
        statusCode: 404,
        code: 'UNKNOWN',
        message: 'Cannot POST /v1/realunit/referral/bind',
      ),
    );

    await bindPendingReferralCode(router);

    expect(await peekPendingReferralCode(), 'AB12CD');
    verify(() => service.bind(code: 'AB12CD')).called(1);
  });

  test('drops the stash on a 4xx business rejection', () async {
    await stashPendingReferralCode('AB12CD');
    when(() => service.bind(code: 'AB12CD')).thenThrow(
      const ApiException(
        statusCode: 409,
        code: 'ALREADY_BOUND',
        message: 'already bound',
      ),
    );

    await bindPendingReferralCode(router);

    expect(await peekPendingReferralCode(), isNull);
    verify(() => service.bind(code: 'AB12CD')).called(1);
  });

  testWidgets('shows invalid copy once when bind is rejected as 4xx', (
    tester,
  ) async {
    await stashPendingReferralCode('AB12CD');
    when(() => service.bind(code: 'AB12CD')).thenThrow(
      const ApiException(
        statusCode: 409,
        code: 'ALREADY_BOUND',
        message: 'already bound',
      ),
    );

    await tester.pumpWidget(
      MaterialApp.router(
        theme: realUnitTheme,
        locale: const Locale('de'),
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();

    final pending = bindPendingReferralCode(router);
    await tester.pump();
    await tester.pump();

    expect(find.text('Link ungültig oder abgelaufen'), findsOneWidget);
    expect(
      find.text('Du hast bereits einen Einladungs- oder Promo-Code eingelöst.'),
      findsOneWidget,
    );
    expect(
      tester.widget<Text>(find.text('Link ungültig oder abgelaufen')).style?.color,
      RealUnitColors.status.red600,
    );
    expect(
      tester
          .widget<Text>(
            find.text(
              'Du hast bereits einen Einladungs- oder Promo-Code eingelöst.',
            ),
          )
          .style
          ?.color,
      RealUnitColors.status.red600,
    );
    await tester.tapAt(const Offset(2, 2));
    await tester.pump();
    expect(
      find.text('Du hast bereits einen Einladungs- oder Promo-Code eingelöst.'),
      findsOneWidget,
    );
    expect(
      tester.widget<TextButton>(find.widgetWithText(TextButton, 'Schließen')).autofocus,
      isTrue,
    );
    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();
    await pending;
    expect(await peekPendingReferralCode(), isNull);
  });

  test('drops the stash on a business 404 (code not found)', () async {
    await stashPendingReferralCode('NOPE');
    when(() => service.bind(code: 'NOPE')).thenThrow(
      const ApiException(
        statusCode: 404,
        code: 'NOT_FOUND',
        message: 'missing',
      ),
    );

    await bindPendingReferralCode(router);

    expect(await peekPendingReferralCode(), isNull);
  });

  test('does not bind the same stash twice concurrently', () async {
    await stashPendingReferralCode('AB12CD');
    final started = Completer<void>();
    final release = Completer<ReferralBindResultDto>();
    when(() => service.bind(code: 'AB12CD')).thenAnswer((_) async {
      started.complete();
      return release.future;
    });

    final first = bindPendingReferralCode(router);
    await started.future;
    await bindPendingReferralCode(router);
    release.complete(const ReferralBindResultDto(kind: 'Invite'));
    await first;

    verify(() => service.bind(code: 'AB12CD')).called(1);
    expect(await peekPendingReferralCode(), isNull);
  });

  test('a retryable bind does not overwrite a newer stashed code', () async {
    await stashPendingReferralCode('AB12CD');
    final started = Completer<void>();
    final release = Completer<ReferralBindResultDto>();
    when(() => service.bind(code: 'AB12CD')).thenAnswer((_) async {
      started.complete();
      return release.future;
    });

    final first = bindPendingReferralCode(router);
    await started.future;
    await stashPendingReferralCode('EVT1');
    await bindPendingReferralCode(router);
    release.completeError(
      const ApiException(
        statusCode: 503,
        code: 'UNAVAILABLE',
        message: 'down',
      ),
    );
    await first;

    expect(await peekPendingReferralCode(), 'EVT1');
    verify(() => service.bind(code: 'AB12CD')).called(1);
    verifyNever(() => service.bind(code: 'EVT1'));
  });

  test('binds a leftover stash after the in-flight POST finishes', () async {
    await stashPendingReferralCode('AB12CD');
    final started = Completer<void>();
    final release = Completer<ReferralBindResultDto>();
    when(() => service.bind(code: 'AB12CD')).thenAnswer((_) async {
      started.complete();
      return release.future;
    });
    when(() => service.bind(code: 'EVT1')).thenAnswer(
      (_) async => const ReferralBindResultDto(kind: 'Invite'),
    );

    final first = bindPendingReferralCode(router);
    await started.future;
    await bindPendingReferralCode(router, code: 'EVT1');
    release.complete(const ReferralBindResultDto(kind: 'Invite'));
    await first;

    verify(() => service.bind(code: 'AB12CD')).called(1);
    verify(() => service.bind(code: 'EVT1')).called(1);
    expect(await peekPendingReferralCode(), isNull);
  });

  testWidgets('clears the stash after a successful bind', (tester) async {
    await stashPendingReferralCode('AB12CD');
    when(() => service.bind(code: 'AB12CD')).thenAnswer(
      (_) async => const ReferralBindResultDto(kind: 'Invite'),
    );

    await tester.pumpWidget(
      MaterialApp.router(
        theme: realUnitTheme,
        locale: const Locale('de'),
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();
    await bindPendingReferralCode(router);
    await tester.pumpAndSettle();

    expect(await peekPendingReferralCode(), isNull);
    verify(() => service.bind(code: 'AB12CD')).called(1);
    expect(router.state.uri.path, '/');
    expect(find.textContaining('Björn'), findsNothing);
  });

  testWidgets(
    'shows invite recognition after a late bind with inviterName',
    (tester) async {
      await stashPendingReferralCode('AB12CD');
      when(() => service.bind(code: 'AB12CD')).thenAnswer(
        (_) async => const ReferralBindResultDto(
          kind: 'Invite',
          inviterName: 'Björn',
        ),
      );

      await tester.pumpWidget(
        MaterialApp.router(
          theme: realUnitTheme,
          locale: const Locale('de'),
          localizationsDelegates: const [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: S.delegate.supportedLocales,
          routerConfig: router,
        ),
      );
      await tester.pumpAndSettle();

      final pending = bindPendingReferralCode(router);
      await tester.pump();
      await tester.pump();

      expect(
        find.text(
          'Einladung von Björn erkannt. Björn erhält seine Prämie automatisch, sobald du verifiziert bist und deinen ersten Kauf abgeschlossen hast.',
        ),
        findsOneWidget,
      );
      expect(find.text('Empfehlungen'), findsNothing);
      expect(
        tester.widget<TextButton>(find.widgetWithText(TextButton, 'Schließen')).autofocus,
        isTrue,
      );
      await tester.tap(find.text('Schließen'));
      await tester.pumpAndSettle();
      await pending;
      expect(await peekPendingReferralCode(), isNull);
      expect(router.state.uri.path, '/');
    },
  );

  testWidgets(
    'shows the API campaign text after a promo bind without SettingsBloc',
    (tester) async {
      await stashPendingReferralCode('EVT1');
      when(() => service.bind(code: 'EVT1')).thenAnswer(
        (_) async => const ReferralBindResultDto(
          kind: 'Promo',
          campaignText: 'Mit dem Code EVT1 schenken wir dir 20 Token.',
        ),
      );

      await tester.pumpWidget(
        MaterialApp.router(
          theme: realUnitTheme,
          locale: const Locale('de'),
          localizationsDelegates: const [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: S.delegate.supportedLocales,
          routerConfig: router,
        ),
      );
      await tester.pumpAndSettle();

      final pending = bindPendingReferralCode(router);
      await tester.pump();
      await tester.pump();

      expect(find.text('Aktion'), findsOneWidget);
      expect(
        find.text('Mit dem Code EVT1 schenken wir dir 20 Token.'),
        findsOneWidget,
      );
      await tester.tapAt(const Offset(2, 2));
      await tester.pump();
      expect(find.text('Aktion'), findsOneWidget);
      expect(
        tester.widget<TextButton>(find.widgetWithText(TextButton, 'Schließen')).autofocus,
        isTrue,
      );
      await tester.tap(find.text('Schließen'));
      await tester.pumpAndSettle();
      await pending;
      expect(await peekPendingReferralCode(), isNull);
    },
  );

  testWidgets('shows campaignTextEn after a promo bind in English', (
    tester,
  ) async {
    await stashPendingReferralCode('EVT1');
    when(() => service.bind(code: 'EVT1')).thenAnswer(
      (_) async => const ReferralBindResultDto(
        kind: 'Promo',
        campaignText: 'DE Aktion',
        campaignTextEn: 'EN campaign from the API',
      ),
    );

    await tester.pumpWidget(
      MaterialApp.router(
        theme: realUnitTheme,
        locale: const Locale('en'),
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();

    final pending = bindPendingReferralCode(router);
    await tester.pump();
    await tester.pump();

    expect(find.text('EN campaign from the API'), findsOneWidget);
    expect(find.text('DE Aktion'), findsNothing);
    expect(
      tester.widget<TextButton>(find.widgetWithText(TextButton, 'Close')).autofocus,
      isTrue,
    );
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await pending;
    expect(await peekPendingReferralCode(), isNull);
  });

  testWidgets(
    'shows the promo campaign on the next frame if the navigator was not attached',
    (tester) async {
      await stashPendingReferralCode('EVT1');
      when(() => service.bind(code: 'EVT1')).thenAnswer(
        (_) async => const ReferralBindResultDto(
          kind: 'Promo',
          campaignText: 'Mit dem Code EVT1 schenken wir dir 20 Token.',
        ),
      );

      await bindPendingReferralCode(router);
      expect(find.text('Aktion'), findsNothing);

      await tester.pumpWidget(
        MaterialApp.router(
          theme: realUnitTheme,
          locale: const Locale('de'),
          localizationsDelegates: const [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: S.delegate.supportedLocales,
          routerConfig: router,
        ),
      );
      await tester.pump();

      expect(find.text('Aktion'), findsOneWidget);
      expect(
        find.text('Mit dem Code EVT1 schenken wir dir 20 Token.'),
        findsOneWidget,
      );
      expect(
        tester.widget<TextButton>(find.widgetWithText(TextButton, 'Schließen')).autofocus,
        isTrue,
      );
      await tester.tap(find.text('Schließen'));
      await tester.pumpAndSettle();
      expect(await peekPendingReferralCode(), isNull);
    },
  );

  testWidgets(
    'shows invalid copy on the next frame if the navigator was not attached',
    (tester) async {
      await stashPendingReferralCode('AB12CD');
      when(() => service.bind(code: 'AB12CD')).thenThrow(
        const ApiException(
          statusCode: 409,
          code: 'ALREADY_BOUND',
          message: 'already bound',
        ),
      );

      await bindPendingReferralCode(router);
      expect(find.text('Link ungültig oder abgelaufen'), findsNothing);

      await tester.pumpWidget(
        MaterialApp.router(
          theme: realUnitTheme,
          locale: const Locale('de'),
          localizationsDelegates: const [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: S.delegate.supportedLocales,
          routerConfig: router,
        ),
      );
      await tester.pump();

      expect(find.text('Link ungültig oder abgelaufen'), findsOneWidget);
      expect(
        tester.widget<TextButton>(find.widgetWithText(TextButton, 'Schließen')).autofocus,
        isTrue,
      );
      await tester.tap(find.text('Schließen'));
      await tester.pumpAndSettle();
      expect(await peekPendingReferralCode(), isNull);
    },
  );

  testWidgets(
    'shows unavailable copy when bind times out and keeps the stash',
    (tester) async {
      await stashPendingReferralCode('AB12CD');
      when(() => service.bind(code: 'AB12CD')).thenThrow(
        TimeoutException('bind'),
      );

      await tester.pumpWidget(
        MaterialApp.router(
          theme: realUnitTheme,
          locale: const Locale('de'),
          localizationsDelegates: const [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: S.delegate.supportedLocales,
          routerConfig: router,
        ),
      );
      await tester.pumpAndSettle();

      final pending = bindPendingReferralCode(router);
      await tester.pump();
      await tester.pump();

      expect(
        find.text(
          'Wir konnten den Code gerade nicht prüfen. Bitte versuche es später erneut.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<AppFilledButton>(
              find.widgetWithText(AppFilledButton, 'Wiederholen'),
            )
            .autofocus,
        isTrue,
      );
      await tester.tapAt(const Offset(2, 2));
      await tester.pump();
      expect(
        find.text(
          'Wir konnten den Code gerade nicht prüfen. Bitte versuche es später erneut.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Schließen'));
      await tester.pumpAndSettle();
      await pending;
      expect(await peekPendingReferralCode(), 'AB12CD');
    },
  );

  for (final status in [401, 408, 429, 500, 503, 504]) {
    testWidgets(
      'shows unavailable copy when bind returns $status and keeps the stash',
      (tester) async {
        await stashPendingReferralCode('AB12CD');
        when(() => service.bind(code: 'AB12CD')).thenThrow(
          ApiException(
            statusCode: status,
            code: 'UNAVAILABLE',
            message: 'down',
          ),
        );

        await tester.pumpWidget(
          MaterialApp.router(
            theme: realUnitTheme,
            locale: const Locale('de'),
            localizationsDelegates: const [
              S.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: S.delegate.supportedLocales,
            routerConfig: router,
          ),
        );
        await tester.pumpAndSettle();

        final pending = bindPendingReferralCode(router);
        await tester.pump();
        await tester.pump();

        expect(
          find.text(
            'Wir konnten den Code gerade nicht prüfen. Bitte versuche es später erneut.',
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('Schließen'));
        await tester.pumpAndSettle();
        await pending;
        expect(await peekPendingReferralCode(), 'AB12CD');
      },
    );
  }

  testWidgets(
    'shows unavailable copy when bind hits an unmounted NestJS route',
    (tester) async {
      await stashPendingReferralCode('AB12CD');
      when(() => service.bind(code: 'AB12CD')).thenThrow(
        const ApiException(
          statusCode: 404,
          code: 'UNKNOWN',
          message: 'Cannot POST /v1/realunit/referral/bind',
        ),
      );

      await tester.pumpWidget(
        MaterialApp.router(
          theme: realUnitTheme,
          locale: const Locale('de'),
          localizationsDelegates: const [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: S.delegate.supportedLocales,
          routerConfig: router,
        ),
      );
      await tester.pumpAndSettle();

      final pending = bindPendingReferralCode(router);
      await tester.pump();
      await tester.pump();

      expect(
        find.text(
          'Wir konnten den Code gerade nicht prüfen. Bitte versuche es später erneut.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Schließen'));
      await tester.pumpAndSettle();
      await pending;
      expect(await peekPendingReferralCode(), 'AB12CD');
    },
  );

  testWidgets(
    'unavailable bind Retry posts the stash again without a new landing',
    (tester) async {
      var calls = 0;
      when(() => service.bind(code: 'AB12CD')).thenAnswer((_) async {
        calls += 1;
        if (calls == 1) {
          throw const ApiException(
            statusCode: 503,
            code: 'UNAVAILABLE',
            message: 'down',
          );
        }
        return const ReferralBindResultDto(kind: 'Invite');
      });
      await stashPendingReferralCode('AB12CD');

      await tester.pumpWidget(
        MaterialApp.router(
          theme: realUnitTheme,
          locale: const Locale('de'),
          localizationsDelegates: const [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: S.delegate.supportedLocales,
          routerConfig: router,
        ),
      );
      await tester.pumpAndSettle();

      final pending = bindPendingReferralCode(router);
      await tester.pump();
      await tester.pump();

      expect(
        find.text(
          'Wir konnten den Code gerade nicht prüfen. Bitte versuche es später erneut.',
        ),
        findsOneWidget,
      );
      expect(find.text('Wiederholen'), findsOneWidget);
      await tester.tap(find.text('Wiederholen'));
      await tester.pumpAndSettle();
      await pending;

      expect(
        find.text(
          'Wir konnten den Code gerade nicht prüfen. Bitte versuche es später erneut.',
        ),
        findsNothing,
      );
      expect(await peekPendingReferralCode(), isNull);
      expect(calls, 2);
    },
  );

  testWidgets(
    'unavailable bind Retry stays on the copy while the POST is in flight',
    (tester) async {
      var calls = 0;
      final release = Completer<ReferralBindResultDto>();
      when(() => service.bind(code: 'AB12CD')).thenAnswer((_) async {
        calls += 1;
        if (calls == 1) {
          throw const ApiException(
            statusCode: 503,
            code: 'UNAVAILABLE',
            message: 'down',
          );
        }
        return release.future;
      });
      await stashPendingReferralCode('AB12CD');

      await tester.pumpWidget(
        MaterialApp.router(
          theme: realUnitTheme,
          locale: const Locale('de'),
          localizationsDelegates: const [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: S.delegate.supportedLocales,
          routerConfig: router,
        ),
      );
      await tester.pumpAndSettle();

      final pending = bindPendingReferralCode(router);
      await tester.pump();
      await tester.pump();

      expect(find.text('Wiederholen'), findsOneWidget);
      await tester.tap(find.text('Wiederholen'));
      await tester.pump();

      expect(
        find.text(
          'Wir konnten den Code gerade nicht prüfen. Bitte versuche es später erneut.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<AppFilledButton>(
              find.widgetWithText(AppFilledButton, 'Wiederholen'),
            )
            .state,
        FilledButtonState.loading,
      );
      await tester.tap(find.widgetWithText(AppFilledButton, 'Wiederholen'));
      await tester.pump();
      expect(calls, 2);

      release.complete(const ReferralBindResultDto(kind: 'Invite'));
      await tester.pumpAndSettle();
      await pending;
      expect(
        find.text(
          'Wir konnten den Code gerade nicht prüfen. Bitte versuche es später erneut.',
        ),
        findsNothing,
      );
      expect(await peekPendingReferralCode(), isNull);
    },
  );

  testWidgets(
    'unavailable Retry restashes when bind is still unavailable',
    (tester) async {
      when(() => service.bind(code: 'AB12CD')).thenThrow(
        const ApiException(
          statusCode: 503,
          code: 'UNAVAILABLE',
          message: 'down',
        ),
      );
      await stashPendingReferralCode('AB12CD');

      await tester.pumpWidget(
        MaterialApp.router(
          theme: realUnitTheme,
          locale: const Locale('de'),
          localizationsDelegates: const [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: S.delegate.supportedLocales,
          routerConfig: router,
        ),
      );
      await tester.pumpAndSettle();

      final pending = bindPendingReferralCode(router);
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Wiederholen'));
      await tester.pump();
      await tester.pump();

      expect(
        find.text(
          'Wir konnten den Code gerade nicht prüfen. Bitte versuche es später erneut.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<AppFilledButton>(
              find.widgetWithText(AppFilledButton, 'Wiederholen'),
            )
            .state,
        FilledButtonState.idle,
      );
      expect(await peekPendingReferralCode(), 'AB12CD');
      await tester.tap(find.text('Schließen'));
      await tester.pumpAndSettle();
      await pending;
    },
  );

  testWidgets(
    'unavailable Retry keeps a newer stashed code when bind is still unavailable',
    (tester) async {
      var calls = 0;
      when(() => service.bind(code: any(named: 'code'))).thenAnswer((
        invocation,
      ) async {
        calls += 1;
        if (calls >= 2) {
          await stashPendingReferralCode('NEWER1');
        }
        throw const ApiException(
          statusCode: 503,
          code: 'UNAVAILABLE',
          message: 'down',
        );
      });
      await stashPendingReferralCode('AB12CD');

      await tester.pumpWidget(
        MaterialApp.router(
          theme: realUnitTheme,
          locale: const Locale('de'),
          localizationsDelegates: const [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: S.delegate.supportedLocales,
          routerConfig: router,
        ),
      );
      await tester.pumpAndSettle();

      final pending = bindPendingReferralCode(router);
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Wiederholen'));
      await tester.pump();
      await tester.pump();

      expect(await peekPendingReferralCode(), 'NEWER1');
      expect(
        find.text(
          'Wir konnten den Code gerade nicht prüfen. Bitte versuche es später erneut.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Schließen'));
      await tester.pumpAndSettle();
      await pending;
    },
  );

  testWidgets(
    'unavailable Retry shows invalid copy when bind is a 4xx rejection',
    (tester) async {
      var calls = 0;
      when(() => service.bind(code: 'AB12CD')).thenAnswer((_) async {
        calls += 1;
        if (calls == 1) {
          throw const ApiException(
            statusCode: 503,
            code: 'UNAVAILABLE',
            message: 'down',
          );
        }
        throw const ApiException(
          statusCode: 409,
          code: 'ALREADY_BOUND',
          message: 'already bound',
        );
      });
      await stashPendingReferralCode('AB12CD');

      await tester.pumpWidget(
        MaterialApp.router(
          theme: realUnitTheme,
          locale: const Locale('de'),
          localizationsDelegates: const [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: S.delegate.supportedLocales,
          routerConfig: router,
        ),
      );
      await tester.pumpAndSettle();

      final pending = bindPendingReferralCode(router);
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Wiederholen'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Link ungültig oder abgelaufen'), findsOneWidget);
      expect(await peekPendingReferralCode(), isNull);
      await tester.tap(find.text('Schließen'));
      await tester.pumpAndSettle();
      await pending;
    },
  );

  testWidgets(
    'unavailable dialog post-frame is a no-op without a navigator',
    (tester) async {
      await stashPendingReferralCode('AB12CD');
      when(() => service.bind(code: 'AB12CD')).thenThrow(
        const ApiException(
          statusCode: 503,
          code: 'UNAVAILABLE',
          message: 'down',
        ),
      );

      await bindPendingReferralCode(router);
      await tester.pump();

      expect(
        find.text(
          'Wir konnten den Code gerade nicht prüfen. Bitte versuche es später erneut.',
        ),
        findsNothing,
      );
      expect(await peekPendingReferralCode(), 'AB12CD');
    },
  );

  testWidgets(
    'deferred unavailable Retry shows the promo campaign',
    (tester) async {
      var calls = 0;
      when(() => service.bind(code: 'EVT1')).thenAnswer((_) async {
        calls += 1;
        if (calls == 1) {
          throw const ApiException(
            statusCode: 503,
            code: 'UNAVAILABLE',
            message: 'down',
          );
        }
        return const ReferralBindResultDto(
          kind: 'Promo',
          campaignText: 'Mit dem Code EVT1 schenken wir dir 20 Token.',
        );
      });
      await stashPendingReferralCode('EVT1');
      await bindPendingReferralCode(router);

      await tester.pumpWidget(
        MaterialApp.router(
          theme: realUnitTheme,
          locale: const Locale('de'),
          localizationsDelegates: const [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: S.delegate.supportedLocales,
          routerConfig: router,
        ),
      );
      await tester.pump();

      expect(find.text('Wiederholen'), findsOneWidget);
      await tester.tap(find.text('Wiederholen'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Aktion'), findsOneWidget);
      expect(
        find.text('Mit dem Code EVT1 schenken wir dir 20 Token.'),
        findsOneWidget,
      );
      expect(calls, 2);
      await tester.tap(find.text('Schließen'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'deferred unavailable Retry shows invalid copy on a 4xx rejection',
    (tester) async {
      var calls = 0;
      when(() => service.bind(code: 'AB12CD')).thenAnswer((_) async {
        calls += 1;
        if (calls == 1) {
          throw const ApiException(
            statusCode: 503,
            code: 'UNAVAILABLE',
            message: 'down',
          );
        }
        throw const ApiException(
          statusCode: 409,
          code: 'ALREADY_BOUND',
          message: 'already bound',
        );
      });
      await stashPendingReferralCode('AB12CD');
      await bindPendingReferralCode(router);

      await tester.pumpWidget(
        MaterialApp.router(
          theme: realUnitTheme,
          locale: const Locale('de'),
          localizationsDelegates: const [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: S.delegate.supportedLocales,
          routerConfig: router,
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Wiederholen'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Link ungültig oder abgelaufen'), findsOneWidget);
      expect(calls, 2);
      await tester.tap(find.text('Schließen'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'scheduleReferralBind stashes without binding when PIN is locked',
    (tester) async {
      final pin = _MockPinAuthCubit();
      when(() => pin.state).thenReturn(
        const PinAuthState(isPinSetup: true, isPinVerified: false),
      );
      GetIt.instance.registerSingleton<PinAuthCubit>(pin);

      scheduleReferralBind(router, 'AB12CD');
      await tester.pumpWidget(
        MaterialApp.router(
          theme: realUnitTheme,
          locale: const Locale('de'),
          localizationsDelegates: const [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: S.delegate.supportedLocales,
          routerConfig: router,
        ),
      );
      await tester.pump();

      expect(await peekPendingReferralCode(), 'AB12CD');
      verifyNever(() => service.bind(code: 'AB12CD'));
    },
  );

  testWidgets(
    'scheduleReferralBind binds after PIN unlock',
    (tester) async {
      final pin = _MockPinAuthCubit();
      when(() => pin.state).thenReturn(
        const PinAuthState(isPinSetup: true, isPinVerified: true),
      );
      GetIt.instance.registerSingleton<PinAuthCubit>(pin);
      when(() => service.bind(code: 'AB12CD')).thenAnswer(
        (_) async => const ReferralBindResultDto(kind: 'Invite'),
      );

      scheduleReferralBind(router, 'AB12CD');
      await tester.pumpWidget(
        MaterialApp.router(
          theme: realUnitTheme,
          locale: const Locale('de'),
          localizationsDelegates: const [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: S.delegate.supportedLocales,
          routerConfig: router,
        ),
      );
      await tester.pump();
      await tester.pump();

      verify(() => service.bind(code: 'AB12CD')).called(1);
      expect(await peekPendingReferralCode(), isNull);
    },
  );
}
