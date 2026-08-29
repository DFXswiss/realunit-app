import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/screens/referral/widgets/referral_share_invite_button.dart';
import 'package:realunit_wallet/styles/themes.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';

void main() {
  const channel = MethodChannel('dev.fluttercommunity.plus/share');

  testWidgets('shows error state when share throws and stays tappable', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        throw PlatformException(code: 'unavailable');
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: realUnitTheme,
        locale: const Locale('de'),
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        home: const Scaffold(
          body: ReferralShareInviteButton(
            text: 'Hey Alice: https://realunit.app/invite/AAAA',
          ),
        ),
      ),
    );
    await tester.tap(find.text('Einladungslink versenden'));
    await tester.pump();
    expect(
      tester.widget<AppFilledButton>(find.byType(AppFilledButton)).state,
      FilledButtonState.error,
    );
    expect(find.text('Einladungslink versenden'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(
      tester.widget<AppFilledButton>(find.byType(AppFilledButton)).state,
      FilledButtonState.idle,
    );
  });

  testWidgets('ignores a second tap while share is in flight', (tester) async {
    var calls = 0;
    final release = Completer<String>();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        calls++;
        return release.future;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: realUnitTheme,
        locale: const Locale('de'),
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        home: const Scaffold(
          body: ReferralShareInviteButton(
            text: 'Hey Alice: https://realunit.app/invite/AAAA',
          ),
        ),
      ),
    );
    await tester.tap(find.byType(AppFilledButton));
    await tester.pump();
    expect(
      tester.widget<AppFilledButton>(find.byType(AppFilledButton)).state,
      FilledButtonState.loading,
    );
    await tester.tap(find.byType(AppFilledButton));
    await tester.pump();
    expect(calls, 1);
    release.complete('');
    await tester.pump();
    expect(
      tester.widget<AppFilledButton>(find.byType(AppFilledButton)).state,
      FilledButtonState.idle,
    );
  });

  testWidgets(
    'resuming the app clears a hung share so Versenden is tappable again',
    (tester) async {
      var calls = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async {
          calls++;
          return Completer<String>().future;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: realUnitTheme,
          locale: const Locale('de'),
          localizationsDelegates: const [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: S.delegate.supportedLocales,
          home: const Scaffold(
            body: ReferralShareInviteButton(
              text: 'Hey Alice: https://realunit.app/invite/AAAA',
            ),
          ),
        ),
      );
      await tester.tap(find.byType(AppFilledButton));
      await tester.pump();
      expect(
        tester.widget<AppFilledButton>(find.byType(AppFilledButton)).state,
        FilledButtonState.loading,
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(
        tester.widget<AppFilledButton>(find.byType(AppFilledButton)).state,
        FilledButtonState.idle,
      );

      await tester.tap(find.byType(AppFilledButton));
      await tester.pump();
      expect(calls, 2);
    },
  );

  testWidgets(
    'does not show error when the share text changes while the sheet is open',
    (tester) async {
      final release = Completer<void>();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async {
          await release.future;
          throw PlatformException(code: 'unavailable');
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
      });

      var text = 'Hey Alice: https://realunit.app/invite/AAAA';
      Future<void> pumpButton() {
        return tester.pumpWidget(
          MaterialApp(
            theme: realUnitTheme,
            locale: const Locale('de'),
            localizationsDelegates: const [
              S.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: S.delegate.supportedLocales,
            home: Scaffold(
              body: ReferralShareInviteButton(
                key: const Key('share'),
                text: text,
              ),
            ),
          ),
        );
      }

      await pumpButton();
      await tester.tap(find.text('Einladungslink versenden'));
      await tester.pump();
      expect(
        tester.widget<AppFilledButton>(find.byType(AppFilledButton)).state,
        FilledButtonState.loading,
      );

      text = 'Hey Bob: https://realunit.app/invite/BBBB';
      await pumpButton();
      release.complete();
      await tester.pump();
      expect(
        tester.widget<AppFilledButton>(find.byType(AppFilledButton)).state,
        FilledButtonState.idle,
      );
    },
  );
}
