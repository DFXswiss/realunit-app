import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/screens/referral/widgets/referral_copy_invite_button.dart';
import 'package:realunit_wallet/styles/themes.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';

void main() {
  Future<void> mockClipboard() async {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') return null;
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });
  }

  testWidgets('resets Kopiert when the share text changes', (tester) async {
    await mockClipboard();
    var text = 'Hey Alice: https://realunit.app/invite/AAAA';
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
        home: Scaffold(
          body: ReferralCopyInviteButton(key: const Key('copy'), text: text),
        ),
      ),
    );
    await tester.tap(find.text('Einladungslink kopieren'));
    await tester.pump();
    expect(find.text('Kopiert'), findsOneWidget);

    text = 'Hey Bob: https://realunit.app/invite/BBBB';
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
        home: Scaffold(
          body: ReferralCopyInviteButton(key: const Key('copy'), text: text),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Kopiert'), findsNothing);
    expect(find.text('Einladungslink kopieren'), findsOneWidget);
  });

  testWidgets('does not show Kopiert when the clipboard write fails', (
    tester,
  ) async {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        throw PlatformException(code: 'denied');
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
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
          body: ReferralCopyInviteButton(
            text: 'Hey Alice: https://realunit.app/invite/AAAA',
          ),
        ),
      ),
    );
    await tester.tap(find.text('Einladungslink kopieren'));
    await tester.pump();
    expect(find.text('Kopiert'), findsNothing);
    expect(find.text('Einladungslink kopieren'), findsOneWidget);
    expect(
      tester.widget<AppFilledButton>(find.byType(AppFilledButton)).state,
      FilledButtonState.error,
    );
    await tester.pump(const Duration(seconds: 2));
    expect(
      tester.widget<AppFilledButton>(find.byType(AppFilledButton)).state,
      FilledButtonState.idle,
    );
  });

  testWidgets(
    'ignores a second tap while the clipboard write is in flight',
    (tester) async {
      var writes = 0;
      final release = Completer<void>();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          writes++;
          await release.future;
        }
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
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
            body: ReferralCopyInviteButton(
              text: 'Hey Alice: https://realunit.app/invite/AAAA',
            ),
          ),
        ),
      );
      await tester.tap(find.text('Einladungslink kopieren'));
      await tester.pump();
      expect(writes, 1);
      expect(
        tester.widget<AppFilledButton>(find.byType(AppFilledButton)).state,
        FilledButtonState.loading,
      );
      await tester.tap(find.byType(AppFilledButton));
      await tester.pump();
      expect(writes, 1);

      release.complete();
      await tester.pump();
      expect(find.text('Kopiert'), findsOneWidget);
      expect(writes, 1);
    },
  );

  testWidgets(
    'a hung clipboard write fails after two seconds so copy is not stuck',
    (tester) async {
      var writes = 0;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          writes++;
          await Completer<void>().future;
        }
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
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
            body: ReferralCopyInviteButton(
              text: 'Hey Alice: https://realunit.app/invite/AAAA',
            ),
          ),
        ),
      );
      await tester.tap(find.text('Einladungslink kopieren'));
      await tester.pump();
      expect(writes, 1);
      expect(find.text('Kopiert'), findsNothing);

      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Kopiert'), findsNothing);
      expect(
        tester.widget<AppFilledButton>(find.byType(AppFilledButton)).state,
        FilledButtonState.error,
      );

      await tester.tap(find.text('Einladungslink kopieren'));
      await tester.pump();
      expect(writes, 2);
      await tester.pump(const Duration(seconds: 2));
    },
  );

  testWidgets(
    'does not show Kopiert when the share text changes during the write',
    (tester) async {
      final release = Completer<void>();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          await release.future;
        }
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
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
              body: ReferralCopyInviteButton(
                key: const Key('copy'),
                text: text,
              ),
            ),
          ),
        );
      }

      await pumpButton();
      await tester.tap(find.text('Einladungslink kopieren'));
      await tester.pump();

      text = 'Hey Bob: https://realunit.app/invite/BBBB';
      await pumpButton();
      release.complete();
      await tester.pump();
      expect(find.text('Kopiert'), findsNothing);
      expect(find.text('Einladungslink kopieren'), findsOneWidget);
    },
  );

  testWidgets('a second tap while Kopiert copies again and restarts the timer', (
    tester,
  ) async {
    var writes = 0;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') writes++;
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
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
          body: ReferralCopyInviteButton(
            text: 'Hey Alice: https://realunit.app/invite/AAAA',
          ),
        ),
      ),
    );
    await tester.tap(find.text('Einladungslink kopieren'));
    await tester.pump();
    expect(find.text('Kopiert'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.tap(find.text('Kopiert'));
    await tester.pump();
    expect(writes, 2);
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.text('Kopiert'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Einladungslink kopieren'), findsOneWidget);
  });

  testWidgets('unmount during an in-flight clipboard write does not setState', (
    tester,
  ) async {
    final release = Completer<void>();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        await release.future;
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
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
          body: ReferralCopyInviteButton(
            text: 'Hey Alice: https://realunit.app/invite/AAAA',
          ),
        ),
      ),
    );
    await tester.tap(find.text('Einladungslink kopieren'));
    await tester.pump();
    expect(find.byType(ReferralCopyInviteButton), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(find.byType(ReferralCopyInviteButton), findsNothing);

    release.complete();
    await tester.pump();
  });
}
