import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_summary_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_terms_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_referral_service.dart';
import 'package:realunit_wallet/screens/referral/cubit/referral_cubit.dart';
import 'package:realunit_wallet/screens/referral/referral_error_message.dart';
import 'package:realunit_wallet/screens/referral/referral_terms_page.dart';
import 'package:realunit_wallet/styles/themes.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';

class _MockReferralCubit extends MockCubit<ReferralState>
    implements ReferralCubit {}

const _summary = ReferralSummaryDto(
  eligible: true,
  termsAccepted: false,
  openCount: 0,
  creditedCount: 0,
  realuSum: 0,
  chfSum: 0,
);

void main() {
  late _MockReferralCubit cubit;

  setUp(() {
    cubit = _MockReferralCubit();
    when(() => cubit.state).thenReturn(ReferralNeedsTerms(summary: _summary));
    whenListen(
      cubit,
      const Stream<ReferralState>.empty(),
      initialState: ReferralNeedsTerms(summary: _summary),
    );
    when(() => cubit.acceptTerms()).thenAnswer((_) async {});
  });

  testWidgets(
    'create-invite CTA stays disabled until the accepted-terms checkbox is on',
    (tester) async {
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
          home: BlocProvider<ReferralCubit>.value(
            value: cubit,
            child: const ReferralTermsPage(
              initialMarkdownContent: '# Teilnahmebedingungen',
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.text('Teilnahmebedingungen Referral-Programm'),
        findsOneWidget,
      );
      expect(tester.widget<MarkdownBody>(find.byType(MarkdownBody)).selectable, isTrue);
      expect(tester.widget<MarkdownBody>(find.byType(MarkdownBody)).onTapLink, isNotNull);

      final button = tester.widget<AppFilledButton>(find.byType(AppFilledButton));
      expect(button.onPressed, isNull);

      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();

      final enabled = tester.widget<AppFilledButton>(find.byType(AppFilledButton));
      expect(enabled.onPressed, isNotNull);

      await tester.tap(find.byType(AppFilledButton));
      await tester.pump();
      verify(() => cubit.acceptTerms()).called(1);
    },
  );

  testWidgets(
    'read-only after accept hides the checkbox and create CTA',
    (tester) async {
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
          home: const ReferralTermsPage(
            readOnly: true,
            initialMarkdownContent: '# Teilnahmebedingungen',
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('Teilnahmebedingungen'), findsWidgets);
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(find.byType(AppFilledButton), findsNothing);
    },
  );

  testWidgets(
    'read-only loads GET /terms 1:1 instead of only the bundled asset',
    (tester) async {
      final service = _MockReferralService();
      when(() => service.getTerms()).thenAnswer(
        (_) async => const ReferralTermsDto(
          version: '2026-08-14',
          markdown: '# Live TB after accept',
          markdownEn: '# Live EN',
        ),
      );
      GetIt.instance.registerSingleton<RealUnitReferralService>(service);
      addTearDown(() async {
        await GetIt.instance.reset();
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
          home: const ReferralTermsPage(readOnly: true),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('Live TB after accept'), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsNothing);
    },
  );

  testWidgets('shows the API error from a failed terms accept', (tester) async {
    when(() => cubit.state).thenReturn(
      ReferralNeedsTerms(
        summary: _summary,
        errorMessage: referralUnavailableMessage,
      ),
    );
    whenListen(
      cubit,
      const Stream<ReferralState>.empty(),
      initialState: ReferralNeedsTerms(
        summary: _summary,
        errorMessage: referralUnavailableMessage,
      ),
    );

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
        home: BlocProvider<ReferralCubit>.value(
          value: cubit,
          child: const ReferralTermsPage(
            initialMarkdownContent: '# Teilnahmebedingungen',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.text('Wir konnten den Code gerade nicht prüfen. Bitte versuche es später erneut.'),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.text(
          'Wir konnten den Code gerade nicht prüfen. Bitte versuche es später erneut.',
        ),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.liveRegion == true,
        ),
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<AppFilledButton>(find.byType(AppFilledButton)).autofocus,
      isFalse,
    );
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    expect(
      tester.widget<AppFilledButton>(find.byType(AppFilledButton)).autofocus,
      isTrue,
    );
    expect(
      tester.widget<AppFilledButton>(find.byType(AppFilledButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('accepting announces a live region', (tester) async {
    when(() => cubit.state).thenReturn(
      ReferralTermsAccepting(summary: _summary),
    );
    whenListen(
      cubit,
      const Stream<ReferralState>.empty(),
      initialState: ReferralTermsAccepting(summary: _summary),
    );

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
        home: BlocProvider<ReferralCubit>.value(
          value: cubit,
          child: const ReferralTermsPage(
            initialMarkdownContent: '# Teilnahmebedingungen',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Teilnahmebedingungen werden akzeptiert…'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('Teilnahmebedingungen werden akzeptiert…'),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.liveRegion == true,
        ),
      ),
      findsOneWidget,
    );
    final tile = tester.widget<CheckboxListTile>(find.byType(CheckboxListTile));
    expect(tile.onChanged, isNull);
  });

  testWidgets(
    'keeps the accept error while the retry POST is in flight',
    (tester) async {
      when(() => cubit.state).thenReturn(
        ReferralTermsAccepting(
          summary: _summary,
          errorMessage: referralUnavailableMessage,
        ),
      );
      whenListen(
        cubit,
        const Stream<ReferralState>.empty(),
        initialState: ReferralTermsAccepting(
          summary: _summary,
          errorMessage: referralUnavailableMessage,
        ),
      );

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
          home: BlocProvider<ReferralCubit>.value(
            value: cubit,
            child: const ReferralTermsPage(
              initialMarkdownContent: '# Teilnahmebedingungen',
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.text(
          'Wir konnten den Code gerade nicht prüfen. Bitte versuche es später erneut.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Teilnahmebedingungen werden akzeptiert…'),
        findsNothing,
      );
      expect(
        tester.widget<AppFilledButton>(find.byType(AppFilledButton)).state,
        FilledButtonState.loading,
      );
    },
  );

  testWidgets(
    'falls back to bundled TB 14.08 when the terms API is unreachable',
    (tester) async {
      final service = _MockReferralService();
      when(() => service.getTerms()).thenThrow(Exception('down'));
      GetIt.instance.registerSingleton<RealUnitReferralService>(service);
      addTearDown(() async {
        await GetIt.instance.reset();
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
          home: BlocProvider<ReferralCubit>.value(
            value: cubit,
            child: const ReferralTermsPage(),
          ),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.textContaining('14.08.2026'), findsWidgets);
      expect(find.textContaining('70 RealUnit-Aktientoken'), findsWidgets);
    },
  );

  testWidgets('checkbox is hidden until the TB markdown has loaded', (
    tester,
  ) async {
    final service = _MockReferralService();
    when(() => service.getTerms()).thenAnswer(
      (_) => Completer<ReferralTermsDto>().future,
    );
    GetIt.instance.registerSingleton<RealUnitReferralService>(service);
    addTearDown(() async {
      await GetIt.instance.reset();
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
        home: BlocProvider<ReferralCubit>.value(
          value: cubit,
          child: const ReferralTermsPage(),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CheckboxListTile), findsNothing);
    final button = tester.widget<AppFilledButton>(find.byType(AppFilledButton));
    expect(button.onPressed, isNull);
    expect(find.text('Teilnahmebedingungen werden geladen…'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('Teilnahmebedingungen werden geladen…'),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.liveRegion == true,
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'terms Retry ignores a second tap while markdown is reloading',
    (tester) async {
      var calls = 0;
      final retryTerms = Completer<ReferralTermsDto>();
      final service = _MockReferralService();
      when(() => service.getTerms()).thenAnswer((_) async {
        calls += 1;
        if (calls == 1) throw Exception('down');
        return retryTerms.future;
      });
      GetIt.instance.registerSingleton<RealUnitReferralService>(service);
      addTearDown(() async {
        await GetIt.instance.reset();
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
          home: BlocProvider<ReferralCubit>.value(
            value: cubit,
            child: ReferralTermsPage(
              loadAsset: (_) async => throw Exception('missing'),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Wiederholen'), findsOneWidget);
      expect(calls, 1);

      final retry = tester.widget<AppFilledButton>(
        find.widgetWithText(AppFilledButton, 'Wiederholen'),
      );
      retry.onPressed?.call();
      retry.onPressed?.call();
      await tester.pump();
      expect(calls, 2);
      expect(find.text('Wiederholen'), findsOneWidget);
      expect(
        find.textContaining('Dokument konnte nicht geladen'),
        findsOneWidget,
      );
      expect(
        tester.widget<AppFilledButton>(
          find.widgetWithText(AppFilledButton, 'Wiederholen'),
        ).state,
        FilledButtonState.loading,
      );
    },
  );

  testWidgets(
    'ignores a stale terms load after a later load of another language',
    (tester) async {
      final first = Completer<ReferralTermsDto>();
      final second = Completer<ReferralTermsDto>();
      var calls = 0;
      final service = _MockReferralService();
      when(() => service.getTerms()).thenAnswer((_) {
        calls += 1;
        return calls == 1 ? first.future : second.future;
      });
      GetIt.instance.registerSingleton<RealUnitReferralService>(service);
      addTearDown(() async {
        await GetIt.instance.reset();
      });

      final locale = ValueNotifier(const Locale('de'));
      addTearDown(locale.dispose);

      await tester.pumpWidget(
        ValueListenableBuilder<Locale>(
          valueListenable: locale,
          builder: (context, value, _) {
            return MaterialApp(
              theme: realUnitTheme,
              locale: value,
              localizationsDelegates: const [
                S.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
              ],
              supportedLocales: S.delegate.supportedLocales,
              home: BlocProvider<ReferralCubit>.value(
                value: cubit,
                child: const ReferralTermsPage(),
              ),
            );
          },
        ),
      );
      await tester.pump();
      expect(calls, 1);

      locale.value = const Locale('en');
      await tester.pump();
      expect(calls, 2);

      second.complete(
        const ReferralTermsDto(
          version: '2026-08-14',
          markdown: '# Alte TB',
          markdownEn: '# New terms',
        ),
      );
      await tester.pump();
      expect(find.textContaining('New terms'), findsOneWidget);

      first.complete(
        const ReferralTermsDto(
          version: '2026-08-14',
          markdown: '# Stale DE',
          markdownEn: '# Stale EN',
        ),
      );
      await tester.pump();
      expect(find.textContaining('New terms'), findsOneWidget);
      expect(find.textContaining('Stale DE'), findsNothing);
      expect(find.textContaining('Alte TB'), findsNothing);
    },
  );

  test('only http(s) terms links open in the in-app browser', () {
    expect(
      referralTermsOpensInApp('https://realunit.ch/downloads/'),
      isTrue,
    );
    expect(referralTermsOpensInApp('http://example.com/tb'), isTrue);
    expect(referralTermsOpensInApp('mailto:info@realunit.ch'), isFalse);
    expect(referralTermsOpensInApp('javascript:alert(1)'), isFalse);
    expect(referralTermsOpensInApp('info@realunit.ch'), isFalse);
    expect(referralTermsOpensInApp('realunit-wallet://invite/AB12CD'), isFalse);
    expect(referralTermsOpensInApp(null), isFalse);
    expect(referralTermsOpensInApp(''), isFalse);
    expect(referralTermsOpensInApp('/downloads/'), isTrue);
    expect(
      referralTermsInAppUri('/downloads/prospekt.pdf'),
      Uri.parse('https://realunit.ch/downloads/prospekt.pdf'),
    );
    expect(
      referralTermsInAppUri('https://realunit.ch/downloads/'),
      Uri.parse('https://realunit.ch/downloads/'),
    );
    expect(referralTermsInAppUri('mailto:info@realunit.ch'), isNull);
    expect(referralTermsInAppUri('../secret'), isNull);
    expect(
      referralTermsInAppUri('//realunit.ch/downloads/'),
      Uri.parse('https://realunit.ch/downloads/'),
    );
    expect(
      referralTermsInAppUri('//docs.dfx.swiss/de/tnc.html'),
      Uri.parse('https://docs.dfx.swiss/de/tnc.html'),
    );
  });
}

class _MockReferralService extends Mock implements RealUnitReferralService {}
