import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_code_lookup_dto.dart';
import 'package:realunit_wallet/screens/kyc/steps/registration/widgets/referral_code_field.dart';
import 'package:realunit_wallet/styles/themes.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';

bool _isLiveRegion(WidgetTester tester, Finder textFinder) {
  return find
      .ancestor(
        of: textFinder,
        matching: find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.liveRegion == true,
        ),
      )
      .evaluate()
      .isNotEmpty;
}

void main() {
  Future<void> pumpField(
    WidgetTester tester, {
    required TextEditingController controller,
    required Future<ReferralCodeLookupDto> Function(String code) lookup,
    ValueChanged<String?>? onResolved,
    Future<String?> Function()? readClipboard,
    Future<String?> Function()? pendingCode,
    bool autoPasteOnEmpty = false,
    Locale locale = const Locale('de'),
    bool enabled = true,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        theme: realUnitTheme,
        locale: locale,
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        home: Scaffold(
          body: ReferralCodeField(
            key: const Key('referral-code'),
            controller: controller,
            lookup: lookup,
            onResolved: onResolved,
            readClipboard: readClipboard,
            pendingCode: pendingCode,
            autoPasteOnEmpty: autoPasteOnEmpty,
            enabled: enabled,
          ),
        ),
      ),
    );
  }

  testWidgets('shows checking copy while lookup is in flight', (tester) async {
    final ctrl = TextEditingController(text: 'AB12');
    await pumpField(
      tester,
      controller: ctrl,
      lookup: (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 800));
        return const ReferralCodeLookupDto(
          kind: 'invite',
          inviterName: 'Björn',
        );
      },
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Code wird geprüft…'), findsOneWidget);
    expect(_isLiveRegion(tester, find.text('Code wird geprüft…')), isTrue);

    await tester.pump(const Duration(milliseconds: 800));

    expect(find.text('Code wird geprüft…'), findsNothing);
    expect(find.textContaining('Einladung von Björn erkannt'), findsOneWidget);
  });

  testWidgets(
    'hides previous recognition while a later lookup is in flight',
    (tester) async {
      final ctrl = TextEditingController(text: 'AB12');
      await pumpField(
        tester,
        controller: ctrl,
        lookup: (code) async {
          if (code == 'CD34') {
            await Future<void>.delayed(const Duration(milliseconds: 800));
          }
          return ReferralCodeLookupDto(
            kind: 'invite',
            inviterName: code == 'AB12' ? 'Björn' : 'Alice',
          );
        },
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('Einladung von Björn erkannt'), findsOneWidget);

      ctrl.text = 'CD34';
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.textContaining('Einladung von Björn erkannt'), findsNothing);
      expect(find.text('Code wird geprüft…'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text('Code wird geprüft…'), findsNothing);
      expect(find.textContaining('Einladung von Alice erkannt'), findsOneWidget);
    },
  );

  testWidgets('shows invite recognition after a successful lookup', (tester) async {
    final ctrl = TextEditingController(text: 'AB12');
    await pumpField(
      tester,
      controller: ctrl,
      lookup: (_) async => const ReferralCodeLookupDto(
        kind: 'invite',
        inviterName: 'Björn',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Hast du einen Empfehlungscode?'), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.enableIMEPersonalizedLearning, isFalse);
    expect(find.textContaining('Einladung von Björn erkannt'), findsOneWidget);
    expect(
      _isLiveRegion(tester, find.textContaining('Einladung von Björn erkannt')),
      isTrue,
    );
  });

  testWidgets('does not show invite recognition for a whitespace inviter', (
    tester,
  ) async {
    final ctrl = TextEditingController(text: 'AB12');
    await pumpField(
      tester,
      controller: ctrl,
      lookup: (_) async => const ReferralCodeLookupDto(
        kind: 'invite',
        inviterName: '   ',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.textContaining('Einladung von'), findsNothing);
  });

  testWidgets('shows the API campaign text in a dialog for a promo code', (
    tester,
  ) async {
    final ctrl = TextEditingController(text: 'EVT1');
    await pumpField(
      tester,
      controller: ctrl,
      lookup: (_) async => const ReferralCodeLookupDto(
        kind: 'promo',
        actionText: 'Mit dem Code EVT1 schenken wir dir 20 Token.',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(find.text('Aktion'), findsOneWidget);
    expect(
      find.text('Mit dem Code EVT1 schenken wir dir 20 Token.'),
      findsNWidgets(2),
    );
    expect(
      tester
          .widget<Text>(
            find.text('Mit dem Code EVT1 schenken wir dir 20 Token.').first,
          )
          .locale
          ?.languageCode,
      'de',
    );
    expect(
      _isLiveRegion(
        tester,
        find.text('Mit dem Code EVT1 schenken wir dir 20 Token.'),
      ),
      isTrue,
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
    expect(find.text('Aktion'), findsNothing);
  });

  testWidgets('does not show a promo dialog after the field is cleared', (
    tester,
  ) async {
    final ctrl = TextEditingController(text: 'EVT1');
    await pumpField(
      tester,
      controller: ctrl,
      lookup: (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 800));
        return const ReferralCodeLookupDto(
          kind: 'promo',
          actionText: 'Mit dem Code EVT1 schenken wir dir 20 Token.',
        );
      },
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    ctrl.clear();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();

    expect(find.text('Aktion'), findsNothing);
    expect(
      find.text('Mit dem Code EVT1 schenken wir dir 20 Token.'),
      findsNothing,
    );
  });

  testWidgets(
    'DE campaign fallback on an English locale is tagged German',
    (tester) async {
      final ctrl = TextEditingController(text: 'EVT1');
      await pumpField(
        tester,
        controller: ctrl,
        locale: const Locale('en'),
        lookup: (_) async => const ReferralCodeLookupDto(
          kind: 'promo',
          actionText: 'Mit dem Code EVT1 schenken wir dir 20 Token.',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      final campaign = tester.widget<Text>(
        find.text('Mit dem Code EVT1 schenken wir dir 20 Token.').first,
      );
      expect(campaign.locale?.languageCode, 'de');
    },
  );

  testWidgets('shows invalid copy on a 404 lookup', (tester) async {
    final ctrl = TextEditingController(text: 'NOPE');
    await pumpField(
      tester,
      controller: ctrl,
      lookup: (_) async => throw const ApiException(
        statusCode: 404,
        code: 'NOT_FOUND',
        message: 'missing',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.text('Dieser Code ist ungültig oder abgelaufen.'),
      findsOneWidget,
    );
    expect(
      _isLiveRegion(
        tester,
        find.text('Dieser Code ist ungültig oder abgelaufen.'),
      ),
      isTrue,
    );
  });

  testWidgets('shows spent copy on a 410 SPENT lookup', (tester) async {
    final ctrl = TextEditingController(text: 'USED1');
    await pumpField(
      tester,
      controller: ctrl,
      lookup: (_) async => throw const ApiException(
        statusCode: 410,
        code: 'SPENT',
        message: 'invite already bound',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.text('Dieser Einladungs- oder Promo-Code wurde bereits verwendet.'),
      findsOneWidget,
    );
    expect(
      find.text('Dieser Code ist ungültig oder abgelaufen.'),
      findsNothing,
    );
  });

  testWidgets('onResolved is null for an invalid code and set for a valid one', (
    tester,
  ) async {
    String? resolved = 'sentinel';
    final ctrl = TextEditingController(text: 'NOPE');
    await pumpField(
      tester,
      controller: ctrl,
      onResolved: (code) => resolved = code,
      lookup: (code) async {
        if (code.toUpperCase() == 'NOPE') {
          throw const ApiException(
            statusCode: 404,
            code: 'NOT_FOUND',
            message: 'missing',
          );
        }
        return const ReferralCodeLookupDto(kind: 'invite');
      },
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(resolved, isNull);

    resolved = 'sentinel';
    ctrl.text = 'AB12';
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(resolved, 'AB12');
  });

  testWidgets(
    'a NestJS unmounted-route 404 is not shown as an invalid code',
    (tester) async {
      final ctrl = TextEditingController(text: 'AB12');
      await pumpField(
        tester,
        controller: ctrl,
        lookup: (_) async => throw const ApiException(
          statusCode: 404,
          code: 'UNKNOWN',
          message: 'Cannot GET /v1/realunit/referral/code/AB12',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        find.text('Dieser Code ist ungültig oder abgelaufen.'),
        findsNothing,
      );
      expect(find.text('Wiederholen'), findsOneWidget);
      expect(ctrl.text, 'AB12');
    },
  );

  testWidgets('a 500 lookup is not shown as an invalid code', (tester) async {
    final ctrl = TextEditingController(text: 'AB12');
    await pumpField(
      tester,
      controller: ctrl,
      lookup: (_) async => throw const ApiException(
        statusCode: 500,
        code: 'SERVER_ERROR',
        message: 'down',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.text('Dieser Code ist ungültig oder abgelaufen.'),
      findsNothing,
    );
    expect(
      find.text(
        'Wir konnten den Code gerade nicht prüfen. Bitte versuche es später erneut.',
      ),
      findsOneWidget,
    );
    expect(
      _isLiveRegion(
        tester,
        find.text(
          'Wir konnten den Code gerade nicht prüfen. Bitte versuche es später erneut.',
        ),
      ),
      isTrue,
    );
    expect(find.text('Wiederholen'), findsOneWidget);
    expect(
      tester
          .widget<AppFilledButton>(
            find.widgetWithText(AppFilledButton, 'Wiederholen'),
          )
          .variant,
      FilledButtonVariant.secondary,
    );
    expect(ctrl.text, 'AB12');
  });

  testWidgets('a 429 lookup is not shown as an invalid code', (tester) async {
    final ctrl = TextEditingController(text: 'AB12');
    await pumpField(
      tester,
      controller: ctrl,
      lookup: (_) async => throw const ApiException(
        statusCode: 429,
        code: 'RATE_LIMIT',
        message: 'slow',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.text('Dieser Code ist ungültig oder abgelaufen.'),
      findsNothing,
    );
    expect(find.text('Wiederholen'), findsOneWidget);
  });

  testWidgets('unavailable retry looks up the code again', (tester) async {
    var calls = 0;
    final ctrl = TextEditingController(text: 'AB12');
    await pumpField(
      tester,
      controller: ctrl,
      lookup: (_) async {
        calls += 1;
        if (calls == 1) {
          throw const ApiException(
            statusCode: 500,
            code: 'SERVER_ERROR',
            message: 'down',
          );
        }
        return const ReferralCodeLookupDto(
          kind: 'invite',
          inviterName: 'Björn',
        );
      },
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Wiederholen'), findsOneWidget);

    await tester.tap(find.text('Wiederholen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(calls, 2);
    expect(find.textContaining('Einladung von Björn erkannt'), findsOneWidget);
    expect(find.text('Wiederholen'), findsNothing);
  });

  testWidgets(
    'unavailable retry ignores a second tap while lookup is in flight',
    (tester) async {
      var calls = 0;
      final retryLookup = Completer<ReferralCodeLookupDto>();
      final ctrl = TextEditingController(text: 'AB12');
      await pumpField(
        tester,
        controller: ctrl,
        lookup: (_) {
          calls += 1;
          if (calls == 1) {
            return Future<ReferralCodeLookupDto>.error(
              const ApiException(
                statusCode: 500,
                code: 'SERVER_ERROR',
                message: 'down',
              ),
            );
          }
          return retryLookup.future;
        },
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Wiederholen'), findsOneWidget);

      final retry = tester.widget<AppFilledButton>(
        find.widgetWithText(AppFilledButton, 'Wiederholen'),
      );
      retry.onPressed?.call();
      retry.onPressed?.call();
      await tester.pump();
      expect(calls, 2);
      expect(
        find.text(
          'Wir konnten den Code gerade nicht prüfen. Bitte versuche es später erneut.',
        ),
        findsOneWidget,
      );
      expect(find.text('Code wird geprüft…'), findsNothing);
      expect(
        tester
            .widget<AppFilledButton>(
              find.widgetWithText(AppFilledButton, 'Wiederholen'),
            )
            .state,
        FilledButtonState.loading,
      );

      retryLookup.complete(
        const ReferralCodeLookupDto(
          kind: 'invite',
          inviterName: 'Björn',
        ),
      );
      await tester.pump();
      expect(find.textContaining('Einladung von Björn erkannt'), findsOneWidget);
    },
  );

  testWidgets(
    'commitLookup joins an in-flight lookup of the same code',
    (tester) async {
      final ctrl = TextEditingController(text: 'AB12');
      final lookup = Completer<ReferralCodeLookupDto>();
      var calls = 0;
      await pumpField(
        tester,
        controller: ctrl,
        lookup: (_) {
          calls += 1;
          return lookup.future;
        },
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(calls, 1);

      final state = tester.state<ReferralCodeFieldState>(
        find.byType(ReferralCodeField),
      );
      unawaited(state.commitLookup());
      await tester.pump();
      expect(calls, 1);

      lookup.complete(
        const ReferralCodeLookupDto(
          kind: 'invite',
          inviterName: 'Björn',
        ),
      );
      await tester.pump();
      expect(find.textContaining('Einladung von Björn erkannt'), findsOneWidget);
    },
  );

  testWidgets(
    'commitLookup does not look up the same code again after a terminal result',
    (tester) async {
      var calls = 0;
      final ctrl = TextEditingController(text: 'AB12');
      await pumpField(
        tester,
        controller: ctrl,
        lookup: (_) async {
          calls += 1;
          return const ReferralCodeLookupDto(
            kind: 'invite',
            inviterName: 'Björn',
          );
        },
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(calls, 1);
      expect(find.textContaining('Einladung von Björn erkannt'), findsOneWidget);

      await tester.state<ReferralCodeFieldState>(find.byType(ReferralCodeField)).commitLookup();
      await tester.pump();
      expect(calls, 1);
    },
  );

  testWidgets(
    'Done looks up a new code while a previous lookup is in flight',
    (tester) async {
      final first = Completer<ReferralCodeLookupDto>();
      final second = Completer<ReferralCodeLookupDto>();
      var calls = 0;
      final ctrl = TextEditingController(text: 'AB12');
      await pumpField(
        tester,
        controller: ctrl,
        lookup: (code) {
          calls += 1;
          return code == 'AB12' ? first.future : second.future;
        },
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(calls, 1);

      await tester.enterText(find.byType(TextFormField), 'CD34');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(calls, 2);

      second.complete(
        const ReferralCodeLookupDto(
          kind: 'invite',
          inviterName: 'Alice',
        ),
      );
      await tester.pump();
      expect(find.textContaining('Einladung von Alice erkannt'), findsOneWidget);

      first.complete(
        const ReferralCodeLookupDto(
          kind: 'invite',
          inviterName: 'Björn',
        ),
      );
      await tester.pump();
      expect(find.textContaining('Einladung von Alice erkannt'), findsOneWidget);
      expect(find.textContaining('Einladung von Björn erkannt'), findsNothing);
    },
  );

  testWidgets('ignores a stale lookup after the field changes', (tester) async {
    final ctrl = TextEditingController(text: 'OLD1');
    var firstLookupStarted = false;
    await pumpField(
      tester,
      controller: ctrl,
      lookup: (code) async {
        if (code == 'OLD1') {
          firstLookupStarted = true;
          await Future<void>.delayed(const Duration(milliseconds: 800));
          return const ReferralCodeLookupDto(
            kind: 'invite',
            inviterName: 'Stale',
          );
        }
        return const ReferralCodeLookupDto(
          kind: 'invite',
          inviterName: 'Björn',
        );
      },
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(firstLookupStarted, isTrue);

    ctrl.text = 'NEW1';
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.textContaining('Einladung von Stale erkannt'), findsNothing);
    expect(find.textContaining('Einladung von Björn erkannt'), findsOneWidget);
  });

  testWidgets(
    'auto-paste fills an empty field from a landing clipboard code',
    (tester) async {
      String? lookedUp;
      final ctrl = TextEditingController();
      await pumpField(
        tester,
        controller: ctrl,
        autoPasteOnEmpty: true,
        readClipboard: () async => 'https://realunit.app/invite/AB12',
        lookup: (code) async {
          lookedUp = code;
          return const ReferralCodeLookupDto(
            kind: 'invite',
            inviterName: 'Björn',
          );
        },
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(ctrl.text, 'AB12');
      expect(lookedUp, 'AB12');
      expect(find.textContaining('Einladung von Björn erkannt'), findsOneWidget);
    },
  );

  testWidgets(
    'deeplink stash wins over clipboard auto-paste',
    (tester) async {
      String? lookedUp;
      final ctrl = TextEditingController();
      await pumpField(
        tester,
        controller: ctrl,
        autoPasteOnEmpty: true,
        pendingCode: () async => 'STASH1',
        readClipboard: () async => 'CLIP01',
        lookup: (code) async {
          lookedUp = code;
          return const ReferralCodeLookupDto(
            kind: 'invite',
            inviterName: 'Björn',
          );
        },
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(ctrl.text, 'STASH1');
      expect(lookedUp, 'STASH1');
      expect(find.textContaining('Einladung von Björn erkannt'), findsOneWidget);
    },
  );

  testWidgets(
    'in-flight auto-paste does not overwrite a stash that filled while reading',
    (tester) async {
      final clipboard = Completer<String?>();
      String? lookedUp;
      final ctrl = TextEditingController();
      await pumpField(
        tester,
        controller: ctrl,
        autoPasteOnEmpty: true,
        pendingCode: () async => null,
        readClipboard: () => clipboard.future,
        lookup: (code) async {
          lookedUp = code;
          return const ReferralCodeLookupDto(
            kind: 'invite',
            inviterName: 'Björn',
          );
        },
      );
      await tester.pump();
      ctrl.text = 'STASH1';
      clipboard.complete('CLIP01');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(ctrl.text, 'STASH1');
      expect(lookedUp, 'STASH1');
    },
  );

  testWidgets(
    'auto-paste does not overwrite a code already in the field',
    (tester) async {
      String? lookedUp;
      final ctrl = TextEditingController(text: 'TYPED1');
      await pumpField(
        tester,
        controller: ctrl,
        autoPasteOnEmpty: true,
        pendingCode: () async => 'STASH1',
        readClipboard: () async => 'CLIP01',
        lookup: (code) async {
          lookedUp = code;
          return const ReferralCodeLookupDto(
            kind: 'invite',
            inviterName: 'Björn',
          );
        },
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(ctrl.text, 'TYPED1');
      expect(lookedUp, 'TYPED1');
    },
  );

  testWidgets('paste inserts a clipboard invite URL as the extracted code', (
    tester,
  ) async {
    String? lookedUp;
    final ctrl = TextEditingController();
    await pumpField(
      tester,
      controller: ctrl,
      readClipboard: () async => 'https://realunit.app/invite/AB12',
      lookup: (code) async {
        lookedUp = code;
        return const ReferralCodeLookupDto(
          kind: 'invite',
          inviterName: 'Björn',
        );
      },
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Einfügen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(ctrl.text, 'AB12');
    expect(lookedUp, 'AB12');
    expect(find.textContaining('Einladung von Björn erkannt'), findsOneWidget);
  });

  testWidgets(
    'paste of the same code joins an in-flight lookup',
    (tester) async {
      final lookup = Completer<ReferralCodeLookupDto>();
      var calls = 0;
      final ctrl = TextEditingController(text: 'AB12');
      await pumpField(
        tester,
        controller: ctrl,
        readClipboard: () async => 'https://realunit.app/invite/AB12',
        lookup: (_) {
          calls += 1;
          return lookup.future;
        },
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(calls, 1);

      await tester.tap(find.byTooltip('Einfügen'));
      await tester.pump();
      expect(calls, 1);

      lookup.complete(
        const ReferralCodeLookupDto(
          kind: 'invite',
          inviterName: 'Björn',
        ),
      );
      await tester.pump();
      expect(ctrl.text, 'AB12');
      expect(find.textContaining('Einladung von Björn erkannt'), findsOneWidget);
    },
  );

  testWidgets('paste ignores a clipboard of only format characters', (
    tester,
  ) async {
    var lookups = 0;
    final ctrl = TextEditingController();
    await pumpField(
      tester,
      controller: ctrl,
      readClipboard: () async => '\u200E\u200B\u202C',
      lookup: (_) async {
        lookups++;
        return const ReferralCodeLookupDto(kind: 'invite');
      },
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Einfügen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(ctrl.text, isEmpty);
    expect(lookups, 0);
  });

  testWidgets('paste ignores a RealUnit invite URL that has no code', (
    tester,
  ) async {
    var lookups = 0;
    final ctrl = TextEditingController();
    await pumpField(
      tester,
      controller: ctrl,
      readClipboard: () async => 'https://realunit.app/invite?utm_content=summer-sale',
      lookup: (_) async {
        lookups++;
        return const ReferralCodeLookupDto(kind: 'invite');
      },
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Einfügen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(ctrl.text, isEmpty);
    expect(lookups, 0);
  });

  testWidgets(
    'ignores a second paste while the clipboard read is in flight',
    (tester) async {
      var reads = 0;
      final release = Completer<String?>();
      final ctrl = TextEditingController();
      await pumpField(
        tester,
        controller: ctrl,
        readClipboard: () {
          reads += 1;
          return release.future;
        },
        lookup: (_) async => const ReferralCodeLookupDto(
          kind: 'invite',
          inviterName: 'Björn',
        ),
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Einfügen'));
      await tester.pump();
      expect(
        tester.widget<IconButton>(find.byType(IconButton)).onPressed,
        isNull,
      );
      await tester.tap(find.byTooltip('Einfügen'), warnIfMissed: false);
      await tester.pump();
      expect(reads, 1);

      release.complete('AB12');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(ctrl.text, 'AB12');
      expect(find.textContaining('Einladung von Björn erkannt'), findsOneWidget);
    },
  );

  testWidgets(
    'a hung clipboard read is ignored after two seconds so paste is not stuck',
    (tester) async {
      var reads = 0;
      var lookups = 0;
      final ctrl = TextEditingController();
      await pumpField(
        tester,
        controller: ctrl,
        readClipboard: () {
          reads += 1;
          return Completer<String?>().future;
        },
        lookup: (_) async {
          lookups++;
          return const ReferralCodeLookupDto(
            kind: 'invite',
            inviterName: 'Björn',
          );
        },
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Einfügen'));
      await tester.pump();
      expect(reads, 1);
      await tester.tap(find.byTooltip('Einfügen'));
      await tester.pump();
      expect(reads, 1);

      final committed = tester
          .state<ReferralCodeFieldState>(find.byType(ReferralCodeField))
          .commitLookup();
      await tester.pump(const Duration(seconds: 2));
      await committed;
      expect(ctrl.text, isEmpty);
      expect(lookups, 0);

      await tester.tap(find.byTooltip('Einfügen'));
      await tester.pump();
      expect(reads, 2);
      await tester.pump(const Duration(seconds: 2));
    },
  );

  testWidgets(
    'paste is discarded when the field is locked before the clipboard returns',
    (tester) async {
      final release = Completer<String?>();
      var lookups = 0;
      final ctrl = TextEditingController();
      await pumpField(
        tester,
        controller: ctrl,
        readClipboard: () => release.future,
        lookup: (_) async {
          lookups++;
          return const ReferralCodeLookupDto(
            kind: 'invite',
            inviterName: 'Björn',
          );
        },
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Einfügen'));
      await tester.pump();

      await pumpField(
        tester,
        controller: ctrl,
        enabled: false,
        readClipboard: () => release.future,
        lookup: (_) async {
          lookups++;
          return const ReferralCodeLookupDto(
            kind: 'invite',
            inviterName: 'Björn',
          );
        },
      );
      release.complete('AB12');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(ctrl.text, isEmpty);
      expect(lookups, 0);
    },
  );

  testWidgets(
    'paste is discarded after abandonLookup even if the field stays enabled',
    (tester) async {
      final release = Completer<String?>();
      var lookups = 0;
      final ctrl = TextEditingController();
      await pumpField(
        tester,
        controller: ctrl,
        readClipboard: () => release.future,
        lookup: (_) async {
          lookups++;
          return const ReferralCodeLookupDto(
            kind: 'invite',
            inviterName: 'Björn',
          );
        },
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Einfügen'));
      await tester.pump();

      tester.state<ReferralCodeFieldState>(find.byType(ReferralCodeField)).abandonLookup();
      release.complete('AB12');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(ctrl.text, isEmpty);
      expect(lookups, 0);
    },
  );

  testWidgets('commitLookup waits for an in-flight paste', (tester) async {
    final release = Completer<String?>();
    var calls = 0;
    final ctrl = TextEditingController();
    await pumpField(
      tester,
      controller: ctrl,
      readClipboard: () => release.future,
      lookup: (code) async {
        calls++;
        expect(code, 'AB12');
        return const ReferralCodeLookupDto(
          kind: 'invite',
          inviterName: 'Björn',
        );
      },
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Einfügen'));
    await tester.pump();
    expect(calls, 0);

    final committed = tester
        .state<ReferralCodeFieldState>(find.byType(ReferralCodeField))
        .commitLookup();
    await tester.pump();
    expect(calls, 0);

    release.complete('https://realunit.app/invite/AB12');
    await committed;
    await tester.pump();
    expect(calls, 1);
    expect(ctrl.text, 'AB12');
    expect(find.textContaining('Einladung von Björn erkannt'), findsOneWidget);
  });

  testWidgets('paste ignores a clipboard read failure', (tester) async {
    var lookups = 0;
    final ctrl = TextEditingController();
    await pumpField(
      tester,
      controller: ctrl,
      readClipboard: () async {
        throw PlatformException(code: 'denied');
      },
      lookup: (_) async {
        lookups++;
        return const ReferralCodeLookupDto(kind: 'invite');
      },
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Einfügen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(ctrl.text, isEmpty);
    expect(lookups, 0);
  });

  testWidgets('tapping a prefilled code selects it for replacement', (
    tester,
  ) async {
    final ctrl = TextEditingController(text: 'AB12');
    await pumpField(
      tester,
      controller: ctrl,
      lookup: (_) async => const ReferralCodeLookupDto(kind: 'invite'),
    );
    await tester.pump();
    await tester.tap(find.byType(TextFormField));
    await tester.pump();

    expect(ctrl.selection.baseOffset, 0);
    expect(ctrl.selection.extentOffset, 4);
  });

  testWidgets('does not offer autofill on the code field', (tester) async {
    final ctrl = TextEditingController();
    await pumpField(
      tester,
      controller: ctrl,
      lookup: (_) async => const ReferralCodeLookupDto(kind: 'invite'),
    );
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.autofillHints, isEmpty);
  });

  testWidgets('strips format characters as they are entered', (tester) async {
    final ctrl = TextEditingController();
    await pumpField(
      tester,
      controller: ctrl,
      lookup: (_) async => const ReferralCodeLookupDto(kind: 'invite'),
    );
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    var value = const TextEditingValue(text: '\u200EAB\u200B12\u202C');
    for (final formatter in field.inputFormatters ?? const <TextInputFormatter>[]) {
      value = formatter.formatEditUpdate(TextEditingValue.empty, value);
    }
    expect(value.text, 'AB12');

    value = const TextEditingValue(text: 'AB\u00A012 CD');
    for (final formatter in field.inputFormatters ?? const <TextInputFormatter>[]) {
      value = formatter.formatEditUpdate(TextEditingValue.empty, value);
    }
    expect(value.text, 'AB12CD');
  });

  testWidgets('keyboard done looks up without waiting for debounce', (
    tester,
  ) async {
    String? lookedUp;
    final ctrl = TextEditingController();
    await pumpField(
      tester,
      controller: ctrl,
      lookup: (code) async {
        lookedUp = code;
        return const ReferralCodeLookupDto(
          kind: 'invite',
          inviterName: 'Björn',
        );
      },
    );
    await tester.pump();
    await tester.enterText(find.byType(TextFormField), 'AB12');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(lookedUp, 'AB12');
    expect(find.textContaining('Einladung von Björn erkannt'), findsOneWidget);
  });

  testWidgets('looks up the code extracted from a pasted invite URL', (
    tester,
  ) async {
    String? lookedUp;
    final ctrl = TextEditingController(
      text: 'https://realunit.app/invite/AB12',
    );
    await pumpField(
      tester,
      controller: ctrl,
      lookup: (code) async {
        lookedUp = code;
        return const ReferralCodeLookupDto(
          kind: 'invite',
          inviterName: 'Björn',
        );
      },
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(lookedUp, 'AB12');
    expect(ctrl.text, 'AB12');
    expect(find.textContaining('Einladung von Björn erkannt'), findsOneWidget);
  });

  testWidgets('looks up the code from a pasted android-app alternate link', (
    tester,
  ) async {
    String? lookedUp;
    final ctrl = TextEditingController(
      text: 'android-app://swiss.realunit.app/https/realunit.app/invite/AB12',
    );
    await pumpField(
      tester,
      controller: ctrl,
      lookup: (code) async {
        lookedUp = code;
        return const ReferralCodeLookupDto(
          kind: 'invite',
          inviterName: 'Björn',
        );
      },
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(lookedUp, 'AB12');
    expect(ctrl.text, 'AB12');
    expect(find.textContaining('Einladung von Björn erkannt'), findsOneWidget);
  });

  testWidgets('looks up a mixed-case code as uppercase', (tester) async {
    String? lookedUp;
    final ctrl = TextEditingController(text: 'AbCd12');
    await pumpField(
      tester,
      controller: ctrl,
      lookup: (code) async {
        lookedUp = code;
        return const ReferralCodeLookupDto(
          kind: 'invite',
          inviterName: 'Björn',
        );
      },
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(lookedUp, 'ABCD12');
    expect(ctrl.text, 'ABCD12');
  });

  testWidgets('looks up a percent-encoded code after decoding', (tester) async {
    String? lookedUp;
    final ctrl = TextEditingController(text: 'AB%2F12');
    await pumpField(
      tester,
      controller: ctrl,
      lookup: (code) async {
        lookedUp = code;
        return const ReferralCodeLookupDto(
          kind: 'invite',
          inviterName: 'Björn',
        );
      },
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(lookedUp, 'AB/12');
    expect(ctrl.text, 'AB/12');
    expect(find.textContaining('Einladung von Björn erkannt'), findsOneWidget);
  });

  testWidgets('a lookup timeout is not shown as an invalid code', (tester) async {
    final ctrl = TextEditingController(text: 'AB12');
    await pumpField(
      tester,
      controller: ctrl,
      lookup: (_) async => throw TimeoutException('lookup'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.text('Dieser Code ist ungültig oder abgelaufen.'),
      findsNothing,
    );
    expect(
      find.text('Wir konnten den Code gerade nicht prüfen. Bitte versuche es später erneut.'),
      findsOneWidget,
    );
    expect(ctrl.text, 'AB12');
  });

  testWidgets('a hung lookup becomes unavailable after 15s', (tester) async {
    final ctrl = TextEditingController(text: 'AB12');
    await pumpField(
      tester,
      controller: ctrl,
      lookup: (_) => Completer<ReferralCodeLookupDto>().future,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Code wird geprüft…'), findsOneWidget);

    await tester.pump(const Duration(seconds: 15));
    expect(find.text('Code wird geprüft…'), findsNothing);
    expect(
      find.text('Wir konnten den Code gerade nicht prüfen. Bitte versuche es später erneut.'),
      findsOneWidget,
    );
    expect(find.text('Wiederholen'), findsOneWidget);
    expect(ctrl.text, 'AB12');
  });

  testWidgets('disabling the field cancels a pending lookup debounce', (
    tester,
  ) async {
    var lookups = 0;
    final ctrl = TextEditingController();
    await pumpField(
      tester,
      controller: ctrl,
      lookup: (_) async {
        lookups++;
        return const ReferralCodeLookupDto(
          kind: 'invite',
          inviterName: 'Björn',
        );
      },
    );
    await tester.pump();
    ctrl.text = 'AB12';
    await tester.pump();
    await pumpField(
      tester,
      controller: ctrl,
      enabled: false,
      lookup: (_) async {
        lookups++;
        return const ReferralCodeLookupDto(
          kind: 'invite',
          inviterName: 'Björn',
        );
      },
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(lookups, 0);
    expect(find.textContaining('Einladung von Björn erkannt'), findsNothing);
  });
}
