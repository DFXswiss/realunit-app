import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_created_invite_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_summary_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_referral_service.dart';
import 'package:realunit_wallet/screens/referral/cubit/referral_cubit.dart';
import 'package:realunit_wallet/screens/referral/referral_create_page.dart';
import 'package:realunit_wallet/screens/referral/referral_error_message.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/styles/themes.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';

class _MockReferralCubit extends MockCubit<ReferralState>
    implements ReferralCubit {}

class _MockService extends Mock implements RealUnitReferralService {}

const _summary = ReferralSummaryDto(
  eligible: true,
  termsAccepted: true,
  openCount: 0,
  creditedCount: 0,
  realuSum: 0,
  chfSum: 0,
);

void main() {
  late _MockReferralCubit cubit;

  setUp(() {
    cubit = _MockReferralCubit();
    when(() => cubit.isClosed).thenReturn(false);
  });

  testWidgets('after create, copy and share actions are shown with the share text', (
    tester,
  ) async {
    const created = ReferralCreatedInviteDto(
      code: 'AB12CD',
      url: 'https://realunit.app/invite/AB12CD',
      guestName: 'Alice',
    );
    when(() => cubit.state).thenReturn(
      const ReferralInviteCreated(summary: _summary, invite: created),
    );
    whenListen(
      cubit,
      const Stream<ReferralState>.empty(),
      initialState: const ReferralInviteCreated(summary: _summary, invite: created),
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
          child: const ReferralCreateView(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Deine Einladung für Alice'), findsOneWidget);
    expect(find.text('Persönlicher Einladungslink'), findsOneWidget);
    expect(
      find.text(
        'Hey Alice, RealUnit lädt dich ein zu RealUnit: https://realunit.app/invite/AB12CD',
      ),
      findsOneWidget,
    );
    expect(find.text('Einladungslink kopieren'), findsOneWidget);
    expect(find.text('Einladungslink versenden'), findsOneWidget);
    expect(
      tester
          .widget<AppFilledButton>(
            find.widgetWithText(AppFilledButton, 'Einladungslink versenden'),
          )
          .autofocus,
      isTrue,
    );
  });

  testWidgets('after create, a blank guest name uses the nameless title', (
    tester,
  ) async {
    const created = ReferralCreatedInviteDto(
      code: 'AB12CD',
      url: 'https://realunit.app/invite/AB12CD',
      guestName: '  ',
    );
    when(() => cubit.state).thenReturn(
      const ReferralInviteCreated(summary: _summary, invite: created),
    );
    whenListen(
      cubit,
      const Stream<ReferralState>.empty(),
      initialState: const ReferralInviteCreated(summary: _summary, invite: created),
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
          child: const ReferralCreateView(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Deine Einladung'), findsOneWidget);
    expect(find.textContaining('Deine Einladung für'), findsNothing);
    expect(find.text('Hey ,'), findsNothing);
    expect(
      find.text('RealUnit lädt dich ein zu RealUnit: https://realunit.app/invite/AB12CD'),
      findsOneWidget,
    );
  });

  testWidgets('copy writes the invite URL to the clipboard', (tester) async {
    String? copied;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });

    const created = ReferralCreatedInviteDto(
      code: 'AB12CD',
      url: 'https://realunit.app/invite/AB12CD',
      guestName: 'Alice',
    );
    when(() => cubit.state).thenReturn(
      const ReferralInviteCreated(summary: _summary, invite: created),
    );
    whenListen(
      cubit,
      const Stream<ReferralState>.empty(),
      initialState: const ReferralInviteCreated(summary: _summary, invite: created),
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
          child: const ReferralCreateView(),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Einladungslink kopieren'));
    await tester.pump();

    expect(
      copied,
      'Hey Alice, RealUnit lädt dich ein zu RealUnit: https://realunit.app/invite/AB12CD',
    );
    expect(find.text('Kopiert'), findsOneWidget);
    expect(find.text('In die Zwischenablage kopiert'), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Einladungslink kopieren'), findsOneWidget);
  });

  testWidgets('copy fallback names the Empfehler from inviterName', (
    tester,
  ) async {
    String? copied;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });

    const created = ReferralCreatedInviteDto(
      code: 'AB12CD',
      url: 'https://realunit.app/invite/AB12CD',
      guestName: 'Alice',
      inviterName: 'Björn',
    );
    when(() => cubit.state).thenReturn(
      const ReferralInviteCreated(summary: _summary, invite: created),
    );
    whenListen(
      cubit,
      const Stream<ReferralState>.empty(),
      initialState: const ReferralInviteCreated(summary: _summary, invite: created),
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
          child: const ReferralCreateView(),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Einladungslink kopieren'));
    await tester.pump();

    expect(
      copied,
      'Hey Alice, Björn lädt dich ein zu RealUnit: https://realunit.app/invite/AB12CD',
    );
  });

  testWidgets('share uses the API copyText 1:1', (tester) async {
    String? shared;
    String? subject;
    String? title;
    const channel = MethodChannel('dev.fluttercommunity.plus/share');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        if (call.method == 'share') {
          final args = call.arguments;
          if (args is Map) {
            shared = args['text'] as String?;
            subject = args['subject'] as String?;
            title = args['title'] as String?;
          }
        }
        return '';
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
    });

    const created = ReferralCreatedInviteDto(
      code: 'AB12CD',
      url: 'https://realunit.app/invite/AB12CD',
      guestName: 'Alice',
      copyText: 'Hey Alice, Björn lädt dich ein: https://realunit.app/invite/AB12CD',
    );
    when(() => cubit.state).thenReturn(
      const ReferralInviteCreated(summary: _summary, invite: created),
    );
    whenListen(
      cubit,
      const Stream<ReferralState>.empty(),
      initialState: const ReferralInviteCreated(summary: _summary, invite: created),
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
          child: const ReferralCreateView(),
        ),
      ),
    );
    await tester.pump();
    expect(
      find.text(
        'Hey Alice, Björn lädt dich ein: https://realunit.app/invite/AB12CD',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Einladungslink versenden'));
    await tester.pump();

    expect(
      shared,
      'Hey Alice, Björn lädt dich ein: https://realunit.app/invite/AB12CD',
    );
    expect(subject, 'Persönlicher Einladungslink');
    expect(title, 'Persönlicher Einladungslink');
  });

  testWidgets('failure offers retry that reloads the summary', (tester) async {
    when(() => cubit.state).thenReturn(
      const ReferralFailure(message: referralUnavailableMessage),
    );
    whenListen(
      cubit,
      const Stream<ReferralState>.empty(),
      initialState: const ReferralFailure(message: referralUnavailableMessage),
    );
    when(() => cubit.load()).thenAnswer((_) async {});
    when(() => cubit.openCreate()).thenReturn(null);

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
          child: const ReferralCreateView(),
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
      tester
          .widget<Text>(
            find.text(
              'Wir konnten den Code gerade nicht prüfen. Bitte versuche es später erneut.',
            ),
          )
          .style
          ?.color,
      RealUnitColors.status.red600,
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
      isTrue,
    );
    await tester.tap(find.byType(AppFilledButton));
    await tester.pump();
    await tester.pump();
    verify(() => cubit.load()).called(1);
    verify(() => cubit.openCreate()).called(1);
  });

  testWidgets('shows the API error on the name-entry form', (tester) async {
    when(() => cubit.state).thenReturn(
      const ReferralCreateReady(
        summary: _summary,
        errorMessage: referralQuotaMessage,
      ),
    );
    whenListen(
      cubit,
      const Stream<ReferralState>.empty(),
      initialState: const ReferralCreateReady(
        summary: _summary,
        errorMessage: referralQuotaMessage,
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
          child: const ReferralCreateView(),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.text('In diesem Quartal sind keine weiteren Prämien möglich.'),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.text('In diesem Quartal sind keine weiteren Prämien möglich.'),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.liveRegion == true,
        ),
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<AppFilledButton>(find.byType(AppFilledButton)).autofocus,
      isTrue,
    );
    expect(
      tester.widget<AppFilledButton>(find.byType(AppFilledButton)).label,
      'Einladungslink erstellen',
    );
    expect(tester.widget<TextField>(find.byType(TextField)).autofocus, isFalse);
  });

  testWidgets('creating announces a live region', (tester) async {
    when(() => cubit.state).thenReturn(
      const ReferralCreating(summary: _summary, guestName: 'Alice'),
    );
    whenListen(
      cubit,
      const Stream<ReferralState>.empty(),
      initialState: const ReferralCreating(summary: _summary, guestName: 'Alice'),
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
          child: const ReferralCreateView(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Einladung wird erstellt…'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('Einladung wird erstellt…'),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.liveRegion == true,
        ),
      ),
      findsOneWidget,
    );
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.enabled, isFalse);
  });

  testWidgets(
    'keeps the create error while the retry POST is in flight',
    (tester) async {
      when(() => cubit.state).thenReturn(
        const ReferralCreating(
          summary: _summary,
          guestName: 'Alice',
          errorMessage: referralQuotaMessage,
        ),
      );
      whenListen(
        cubit,
        const Stream<ReferralState>.empty(),
        initialState: const ReferralCreating(
          summary: _summary,
          guestName: 'Alice',
          errorMessage: referralQuotaMessage,
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
            child: const ReferralCreateView(),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.text('In diesem Quartal sind keine weiteren Prämien möglich.'),
        findsOneWidget,
      );
      expect(find.text('Einladung wird erstellt…'), findsNothing);
      expect(
        tester.widget<AppFilledButton>(find.byType(AppFilledButton)).state,
        FilledButtonState.loading,
      );
    },
  );

  testWidgets('hides the form when the API gate is closed', (tester) async {
    when(() => cubit.state).thenReturn(const ReferralNotEligible());
    whenListen(
      cubit,
      const Stream<ReferralState>.empty(),
      initialState: const ReferralNotEligible(),
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
          child: const ReferralCreateView(),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.text(
        'Das Empfehlungsprogramm steht verifizierten Aktionären mit dem erforderlichen Bestand zur Verfügung.',
      ),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.text(
          'Das Empfehlungsprogramm steht verifizierten Aktionären mit dem erforderlichen Bestand zur Verfügung.',
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
      isTrue,
    );
    expect(
      tester.widget<AppFilledButton>(find.byType(AppFilledButton)).label,
      'Schließen',
    );
  });

  testWidgets('not-eligible Close pops false so overview does not refresh', (
    tester,
  ) async {
    when(() => cubit.state).thenReturn(const ReferralNotEligible());
    whenListen(
      cubit,
      const Stream<ReferralState>.empty(),
      initialState: const ReferralNotEligible(),
    );

    bool? popped;
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => TextButton(
            onPressed: () async {
              popped = await context.push<bool>('/create');
            },
            child: const Text('go'),
          ),
        ),
        GoRoute(
          path: '/create',
          builder: (_, _) => BlocProvider<ReferralCubit>.value(
            value: cubit,
            child: const ReferralCreateView(),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

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
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Schließen'));
    await tester.pumpAndSettle();

    expect(popped, isFalse);
  });

  testWidgets('does not create an invite when the guest name is empty', (tester) async {
    when(() => cubit.state).thenReturn(const ReferralCreateReady(summary: _summary));
    whenListen(
      cubit,
      const Stream<ReferralState>.empty(),
      initialState: const ReferralCreateReady(summary: _summary),
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
          child: const ReferralCreateView(),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(AppFilledButton));
    await tester.pump();

    expect(
      find.text('Bitte den Vornamen der eingeladenen Person eingeben.'),
      findsOneWidget,
    );
    verifyNever(() => cubit.createInvite(guestName: any(named: 'guestName')));
  });

  testWidgets('keyboard done submits the guest name', (tester) async {
    when(() => cubit.state).thenReturn(const ReferralCreateReady(summary: _summary));
    whenListen(
      cubit,
      const Stream<ReferralState>.empty(),
      initialState: const ReferralCreateReady(summary: _summary),
    );
    when(() => cubit.createInvite(guestName: any(named: 'guestName')))
        .thenAnswer((_) async {});

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
          child: const ReferralCreateView(),
        ),
      ),
    );
    await tester.pump();
    final group = tester.widget<AutofillGroup>(find.byType(AutofillGroup));
    expect(group.onDisposeAction, AutofillContextAction.commit);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.keyboardType, TextInputType.name);
    expect(field.autofocus, isTrue);
    expect(field.autofillHints, contains(AutofillHints.givenName));
    expect(field.autofillHints, contains(AutofillHints.name));
    expect(field.autocorrect, isTrue);
    expect(field.enableSuggestions, isTrue);
    await tester.enterText(find.byType(TextFormField), 'Alice');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    verify(() => cubit.createInvite(guestName: 'Alice')).called(1);
  });

  testWidgets('submit sanitizes extra spaces in the guest name', (tester) async {
    when(() => cubit.state).thenReturn(const ReferralCreateReady(summary: _summary));
    whenListen(
      cubit,
      const Stream<ReferralState>.empty(),
      initialState: const ReferralCreateReady(summary: _summary),
    );
    when(() => cubit.createInvite(guestName: any(named: 'guestName')))
        .thenAnswer((_) async {});

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
          child: const ReferralCreateView(),
        ),
      ),
    );
    await tester.pump();
    await tester.enterText(find.byType(TextFormField), '  Alice   Bob  ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
      'Alice Bob',
    );
    verify(() => cubit.createInvite(guestName: 'Alice Bob')).called(1);
  });

  testWidgets('guest-name field maps Unicode spaces as they are typed', (
    tester,
  ) async {
    when(() => cubit.state).thenReturn(const ReferralCreateReady(summary: _summary));
    whenListen(
      cubit,
      const Stream<ReferralState>.empty(),
      initialState: const ReferralCreateReady(summary: _summary),
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
          child: const ReferralCreateView(),
        ),
      ),
    );
    await tester.pump();
    await tester.enterText(find.byType(TextFormField), 'Alice\u3000Bob');
    await tester.pump();
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
      'Alice Bob',
    );
  });

  testWidgets('ignores a second submit while create is in flight', (tester) async {
    when(() => cubit.state).thenReturn(const ReferralCreateReady(summary: _summary));
    whenListen(
      cubit,
      const Stream<ReferralState>.empty(),
      initialState: const ReferralCreateReady(summary: _summary),
    );
    final release = Completer<void>();
    when(() => cubit.createInvite(guestName: any(named: 'guestName')))
        .thenAnswer((_) => release.future);

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
          child: const ReferralCreateView(),
        ),
      ),
    );
    await tester.pump();
    await tester.enterText(find.byType(TextFormField), 'Alice');
    await tester.tap(find.byType(AppFilledButton));
    await tester.pump();
    await tester.tap(find.byType(AppFilledButton));
    await tester.pump();
    verify(() => cubit.createInvite(guestName: 'Alice')).called(1);
    release.complete();
    await tester.pump();
  });

  testWidgets('needs-terms offers retry that reloads the summary', (tester) async {
    when(() => cubit.state).thenReturn(
      const ReferralNeedsTerms(summary: _summary),
    );
    whenListen(
      cubit,
      const Stream<ReferralState>.empty(),
      initialState: const ReferralNeedsTerms(summary: _summary),
    );
    when(() => cubit.load()).thenAnswer((_) async {});
    when(() => cubit.openCreate()).thenReturn(null);

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
          child: const ReferralCreateView(),
        ),
      ),
    );
    await tester.pump();
    expect(
      find.text('Bitte zuerst die Teilnahmebedingungen akzeptieren.'),
      findsOneWidget,
    );
    expect(
      tester.widget<AppFilledButton>(find.byType(AppFilledButton)).autofocus,
      isTrue,
    );
    await tester.tap(find.byType(AppFilledButton));
    await tester.pump();
    await tester.pump();
    verify(() => cubit.load()).called(1);
    verify(() => cubit.openCreate()).called(1);
  });

  testWidgets(
    'needs-terms retry stays on the copy while the summary reloads',
    (tester) async {
      when(() => cubit.state).thenReturn(
        const ReferralNeedsTerms(summary: _summary, retrying: true),
      );
      whenListen(
        cubit,
        const Stream<ReferralState>.empty(),
        initialState: const ReferralNeedsTerms(summary: _summary, retrying: true),
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
            child: const ReferralCreateView(),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.text('Bitte zuerst die Teilnahmebedingungen akzeptieren.'),
        findsOneWidget,
      );
      expect(
        tester.widget<AppFilledButton>(find.byType(AppFilledButton)).state,
        FilledButtonState.loading,
      );
      expect(
        tester.widget<AppFilledButton>(find.byType(AppFilledButton)).onPressed,
        isNull,
      );
    },
  );

  testWidgets('app-bar back after create pops true so overview can refresh', (
    tester,
  ) async {
    const created = ReferralCreatedInviteDto(
      code: 'AB12CD',
      url: 'https://realunit.app/invite/AB12CD',
      guestName: 'Alice',
    );
    when(() => cubit.state).thenReturn(
      const ReferralInviteCreated(summary: _summary, invite: created),
    );
    whenListen(
      cubit,
      const Stream<ReferralState>.empty(),
      initialState: const ReferralInviteCreated(summary: _summary, invite: created),
    );

    bool? popped;
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => TextButton(
            onPressed: () async {
              popped = await context.push<bool>('/create');
            },
            child: const Text('go'),
          ),
        ),
        GoRoute(
          path: '/create',
          builder: (_, _) => BlocProvider<ReferralCubit>.value(
            value: cubit,
            child: const ReferralCreateView(),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

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
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(popped, isTrue);
  });

  testWidgets('Done after create pops true so overview can refresh', (
    tester,
  ) async {
    const created = ReferralCreatedInviteDto(
      code: 'AB12CD',
      url: 'https://realunit.app/invite/AB12CD',
      guestName: 'Alice',
    );
    when(() => cubit.state).thenReturn(
      const ReferralInviteCreated(summary: _summary, invite: created),
    );
    whenListen(
      cubit,
      const Stream<ReferralState>.empty(),
      initialState: const ReferralInviteCreated(summary: _summary, invite: created),
    );

    bool? popped;
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => TextButton(
            onPressed: () async {
              popped = await context.push<bool>('/create');
            },
            child: const Text('go'),
          ),
        ),
        GoRoute(
          path: '/create',
          builder: (_, _) => BlocProvider<ReferralCubit>.value(
            value: cubit,
            child: const ReferralCreateView(),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

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
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Erledigt'));
    await tester.pumpAndSettle();

    expect(popped, isTrue);
  });

  testWidgets(
    'ReferralCreatePage loads summary then opens the name-entry form',
    (tester) async {
      final service = _MockService();
      when(() => service.getSummary()).thenAnswer((_) async => _summary);
      when(() => service.getInvites()).thenAnswer((_) async => []);
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
          home: const ReferralCreatePage(),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byType(TextFormField), findsOneWidget);
    },
  );

  testWidgets(
    'submit from overview opens create then posts the guest name',
    (tester) async {
      when(() => cubit.state).thenReturn(
        const ReferralOverviewLoaded(summary: _summary, invites: []),
      );
      whenListen(
        cubit,
        const Stream<ReferralState>.empty(),
        initialState: const ReferralOverviewLoaded(
          summary: _summary,
          invites: [],
        ),
      );
      when(() => cubit.openCreate()).thenReturn(null);
      when(
        () => cubit.createInvite(guestName: any(named: 'guestName')),
      ).thenAnswer((_) async {});

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
            child: const ReferralCreateView(),
          ),
        ),
      );
      await tester.pump();
      await tester.enterText(find.byType(TextFormField), 'Alice');
      await tester.tap(find.byType(AppFilledButton));
      await tester.pump();

      verify(() => cubit.openCreate()).called(1);
      verify(() => cubit.createInvite(guestName: 'Alice')).called(1);
    },
  );

  testWidgets(
    'submit is a no-op when create is already in flight on the cubit',
    (tester) async {
      when(() => cubit.state).thenReturn(const ReferralCreateReady(summary: _summary));
      whenListen(
        cubit,
        const Stream<ReferralState>.empty(),
        initialState: const ReferralCreateReady(summary: _summary),
      );
      when(
        () => cubit.createInvite(guestName: any(named: 'guestName')),
      ).thenAnswer((_) async {});

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
            child: const ReferralCreateView(),
          ),
        ),
      );
      await tester.pump();
      await tester.enterText(find.byType(TextFormField), 'Alice');
      when(() => cubit.state).thenReturn(
        const ReferralCreating(summary: _summary, guestName: 'Alice'),
      );
      await tester.tap(find.byType(AppFilledButton));
      await tester.pump();

      verifyNever(
        () => cubit.createInvite(guestName: any(named: 'guestName')),
      );
    },
  );
}
