import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/screens/pin/bloc/auth/pin_auth_cubit.dart';
import 'package:realunit_wallet/setup/routing/boot_navigation.dart';
import 'package:realunit_wallet/setup/routing/routes/app_link_entry.dart';
import 'package:realunit_wallet/setup/routing/routes/app_routes.dart';

class _MockPinAuthCubit extends Mock implements PinAuthCubit {}

void main() {
  late _MockPinAuthCubit pinAuthCubit;

  setUp(() {
    pinAuthCubit = _MockPinAuthCubit();
    GetIt.instance.registerSingleton<PinAuthCubit>(pinAuthCubit);
    when(() => pinAuthCubit.state).thenReturn(
      const PinAuthState(isPinVerified: true, isPinSetup: true),
    );
  });

  tearDown(() => GetIt.instance.reset());

  // A minimal router wired to the *production* scheme handling — the
  // [appLinkSchemeRedirect] + [appLinkOnException] pair with the push-aware
  // [effectiveLocation], exactly as router_config.dart wires it. `/home` is the
  // normal cold-start entry; `/dashboard` and `/settings` stand in for
  // arbitrary in-app routes a warm resume must preserve.
  GoRouter buildRouter({String initialLocation = '/home'}) {
    late final GoRouter router;
    router = GoRouter(
      initialLocation: initialLocation,
      redirect: (context, state) => appLinkSchemeRedirect(
        state,
        effectiveLocation(router.routerDelegate.currentConfiguration),
        router,
      ),
      onException: appLinkOnException,
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Text('HOME', key: Key('home'))),
        ),
        GoRoute(
          path: '/dashboard',
          builder: (_, _) => const Scaffold(body: Text('DASH', key: Key('dashboard'))),
        ),
        GoRoute(
          path: '/settings',
          builder: (_, _) => const Scaffold(body: Text('SET', key: Key('settings'))),
        ),
        GoRoute(
          path: '/details',
          // Mirrors the real extra-required builders (/buyPaymentDetails,
          // /webView, …): rebuilding this route from a bare path throws.
          builder: (_, state) =>
              Scaffold(body: Text(state.extra! as String, key: const Key('details'))),
        ),
        // Gate routes from `gateLocations` — needed so warm-resume tests can
        // land on a real lock path and prove /pay is NOT pushed over it.
        GoRoute(
          path: '/verifyPin',
          builder: (_, _) =>
              const Scaffold(body: Text('VERIFY', key: Key('verifyPin'))),
        ),
        GoRoute(
          path: '/pinGate',
          builder: (_, _) =>
              const Scaffold(body: Text('PINGATE', key: Key('pinGate'))),
        ),
        GoRoute(
          path: '/setupPin',
          builder: (_, _) =>
              const Scaffold(body: Text('SETUP', key: Key('setupPin'))),
        ),
        GoRoute(
          name: AppRoutes.pay,
          path: '/pay',
          builder: (_, state) => Scaffold(body: Text('PAY:${state.extra}', key: const Key('pay'))),
        ),
      ],
    );
    return router;
  }

  String currentPath(GoRouter router) => router.routerDelegate.currentConfiguration.uri.path;

  Future<GoRouter> pump(WidgetTester tester, {String initial = '/home'}) async {
    final router = buildRouter(initialLocation: initial);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    return router;
  }

  test('scheme constants', () {
    expect(appLinkScheme, 'realunit-wallet');
    expect(appLinkUrl, 'realunit-wallet://open');
    expect(appLinkColdStartLocation, '/home');
  });

  group('extractPaymentDeeplinkPayload', () {
    const sampleLnurl =
        'LNURL1DP68GURN8GHJ7VF3XGENJVE5UMD9E3K7MF0V9CXJTMKXP6XCEF';

    test('single-colon lightning form extracts the lightning payload', () {
      expect(
        extractPaymentDeeplinkPayload('realunit-wallet:lightning:$sampleLnurl'),
        'lightning:$sampleLnurl',
      );
    });

    test('bare LNURL form extracts the LNURL verbatim', () {
      expect(
        extractPaymentDeeplinkPayload('realunit-wallet:$sampleLnurl'),
        sampleLnurl,
      );
    });

    test('https lnurlp form extracts the URL verbatim', () {
      const url = 'https://api.dfx.swiss/v1/lnurlp/pl_abc123';
      expect(
        extractPaymentDeeplinkPayload('realunit-wallet:$url'),
        url,
      );
    });

    test('canonical path-less open returns null', () {
      expect(extractPaymentDeeplinkPayload(appLinkUrl), isNull);
    });

    test('path-carrying scheme URL returns null', () {
      expect(
        extractPaymentDeeplinkPayload('realunit-wallet://open/settings'),
        isNull,
      );
    });

    test('non-scheme string returns null', () {
      expect(extractPaymentDeeplinkPayload('https://example.com'), isNull);
    });
  });

  testWidgets('warm resume: a scheme open keeps the user on /dashboard', (
    tester,
  ) async {
    final router = await pump(tester);
    router.go('/dashboard');
    await tester.pumpAndSettle();
    expect(currentPath(router), '/dashboard');

    // The scheme open must NOT force any navigation — no jump to /home.
    router.go(appLinkUrl);
    await tester.pumpAndSettle();

    expect(currentPath(router), '/dashboard');
    expect(find.byKey(const Key('dashboard')), findsOneWidget);
    expect(find.byKey(const Key('home')), findsNothing);
  });

  testWidgets('warm resume: a scheme open keeps the user on any route', (
    tester,
  ) async {
    final router = await pump(tester);
    router.go('/settings');
    await tester.pumpAndSettle();
    expect(currentPath(router), '/settings');

    router.go(appLinkUrl);
    await tester.pumpAndSettle();

    expect(currentPath(router), '/settings');
    expect(find.byKey(const Key('settings')), findsOneWidget);
  });

  testWidgets(
    'warm resume: a scheme open keeps the user on a PUSHED route '
    '(how /kyc is reached from Buy/Sell)',
    (tester) async {
      final router = await pump(tester);
      router.go('/dashboard');
      await tester.pumpAndSettle();

      // The KYC flow is entered imperatively — context.pushNamed(AppRoutes.kyc)
      // from the Buy/Sell buttons — so the flow route sits ON TOP of the base
      // route instead of replacing it. /settings stands in for the pushed flow.
      unawaited(router.push('/settings'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings')), findsOneWidget);

      // Same promise as for go-routes above: the scheme open must NOT force
      // any navigation. The pushed route (and with it any page-scoped state,
      // e.g. the KycCubit) must survive the open.
      router.go(appLinkUrl);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('settings')), findsOneWidget);
      expect(find.byKey(const Key('dashboard')), findsNothing);

      // A true no-op also preserves the imperative stack itself — the pushed
      // route must still pop back to the base route it was pushed from. This
      // guards against "fixes" that rebuild the page as a new base route
      // (which would drop page-scoped state, `state.extra`, and the back
      // stack while leaving the same page visible).
      expect(router.canPop(), isTrue);
      router.pop();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('dashboard')), findsOneWidget);
    },
  );

  testWidgets(
    'warm resume: a payment deeplink pushes /pay with the payload as extra '
    'on top of the current stack (pushed route not clobbered)',
    (tester) async {
      const sampleLnurl =
          'LNURL1DP68GURN8GHJ7VF3XGENJVE5UMD9E3K7MF0V9CXJTMKXP6XCEF';
      final router = await pump(tester);
      router.go('/dashboard');
      await tester.pumpAndSettle();

      // Mirror the KYC-pattern test: push a route so the stack is non-trivial.
      unawaited(router.push('/settings'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings')), findsOneWidget);

      // Single-colon form — the double-slash form throws in Uri.parse / go.
      router.go('realunit-wallet:lightning:$sampleLnurl');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pay')), findsOneWidget);
      expect(find.text('PAY:lightning:$sampleLnurl'), findsOneWidget);

      // The push sits ON TOP of the existing stack — nothing was replaced.
      expect(router.canPop(), isTrue);
      router.pop();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings')), findsOneWidget);
      expect(router.canPop(), isTrue);
      router.pop();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('dashboard')), findsOneWidget);
    },
  );

  testWidgets(
    'warm resume: a re-lock landing before the deferred push runs is honored — '
    'no /pay push, payload stashed for post-unlock replay',
    (tester) async {
      addTearDown(clearPendingPaymentDeeplink);
      const sampleLnurl =
          'LNURL1DP68GURN8GHJ7VF3XGENJVE5UMD9E3K7MF0V9CXJTMKXP6XCEF';
      final router = await pump(tester);
      router.go('/dashboard');
      await tester.pumpAndSettle();

      // Keep setUp's unlocked stub (isPinVerified && isPinSetup) so the
      // decision-time check schedules the deferred push callback.
      router.go('realunit-wallet:lightning:$sampleLnurl');
      // Flip the mock AFTER router.go and BEFORE pumpAndSettle so the
      // decision-time check reads unlocked (schedules the deferred callback)
      // while the execution-time re-check reads locked — this is what makes
      // the test non-vacuous (it would fail if the postFrame re-check were
      // deleted, since the deferred callback would then unconditionally push).
      // Simulates a re-lock (AppLifecycleState.resumed -> onAppResumed())
      // landing between decision and deferred frame.
      when(() => pinAuthCubit.state).thenReturn(const PinAuthState(isPinVerified: false));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pay')), findsNothing);
      expect(currentPath(router), '/dashboard');
      expect(peekPendingPaymentDeeplink(), 'lightning:$sampleLnurl');
    },
  );

  testWidgets(
    'warm resume: the canonical no-payload open never pushes /pay',
    (tester) async {
      final router = await pump(tester);
      router.go('/dashboard');
      await tester.pumpAndSettle();

      router.go(appLinkUrl);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pay')), findsNothing);
      expect(find.byKey(const Key('dashboard')), findsOneWidget);
    },
  );

  // Genuinely-locked warm-resume: a payment deeplink while isPinVerified is
  // false (real PIN/unlock gates) must stash and stay — never push /pay over
  // the lock screen. Step-up gates (e.g. /pinGate while already unlocked) take
  // the deferred-push path instead; see the /pinGate test below.
  testWidgets(
    'warm resume on /verifyPin while locked: payment deeplink stashes and does not push /pay',
    (tester) async {
      addTearDown(clearPendingPaymentDeeplink);
      when(() => pinAuthCubit.state).thenReturn(const PinAuthState(isPinVerified: false));
      const sampleLnurl =
          'LNURL1DP68GURN8GHJ7VF3XGENJVE5UMD9E3K7MF0V9CXJTMKXP6XCEF';
      final router = await pump(tester);
      router.go('/verifyPin');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('verifyPin')), findsOneWidget);

      router.go('realunit-wallet:lightning:$sampleLnurl');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pay')), findsNothing);
      expect(find.byKey(const Key('verifyPin')), findsOneWidget);
      expect(currentPath(router), '/verifyPin');
      expect(peekPendingPaymentDeeplink(), 'lightning:$sampleLnurl');
    },
  );

  // /setupPin runtime state from PinAuthCubit.initialize() is
  // isPinSetup=false, isPinVerified=true (vacuous auto-pass before any PIN is
  // configured). Classifying unlock by isPinVerified alone would deferred-push
  // /pay and bypass the mandatory PIN-setup gate — this regression guard uses
  // the real pair state.
  testWidgets(
    'warm resume on /setupPin (vacuous isPinVerified before any PIN is configured): '
    'payment deeplink stashes and does not push /pay',
    (tester) async {
      addTearDown(clearPendingPaymentDeeplink);
      when(() => pinAuthCubit.state).thenReturn(
        const PinAuthState(isPinSetup: false, isPinVerified: true),
      );
      const sampleLnurl =
          'LNURL1DP68GURN8GHJ7VF3XGENJVE5UMD9E3K7MF0V9CXJTMKXP6XCEF';
      final router = await pump(tester);
      router.go('/setupPin');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('setupPin')), findsOneWidget);

      router.go('realunit-wallet:lightning:$sampleLnurl');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pay')), findsNothing);
      expect(find.byKey(const Key('setupPin')), findsOneWidget);
      expect(currentPath(router), '/setupPin');
      expect(peekPendingPaymentDeeplink(), 'lightning:$sampleLnurl');
    },
  );

  testWidgets(
    'warm resume on /pinGate while unlocked (step-up): payment deeplink '
    'deferred-pushes /pay and does not stash',
    (tester) async {
      addTearDown(clearPendingPaymentDeeplink);
      // Already unlocked — e.g. /pinGate reached from settings seed-view /
      // change-PIN. setUp already stubs isPinVerified && isPinSetup.
      const sampleLnurl =
          'LNURL1DP68GURN8GHJ7VF3XGENJVE5UMD9E3K7MF0V9CXJTMKXP6XCEF';
      final router = await pump(tester);
      router.go('/pinGate');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pinGate')), findsOneWidget);

      router.go('realunit-wallet:lightning:$sampleLnurl');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pay')), findsOneWidget);
      expect(find.text('PAY:lightning:$sampleLnurl'), findsOneWidget);
      expect(peekPendingPaymentDeeplink(), isNull);
    },
  );

  testWidgets('cold start on the scheme URL boots to the normal entry', (
    tester,
  ) async {
    // Simulates the OS delivering `realunit-wallet://open` as the initial route
    // on a fresh launch (no prior in-app route to preserve).
    final router = await pump(tester, initial: appLinkUrl);

    expect(currentPath(router), appLinkColdStartLocation);
    expect(find.byKey(const Key('home')), findsOneWidget);
  });

  testWidgets(
    'cold start on a payment deeplink boots to /home and stashes the payload',
    (tester) async {
      addTearDown(clearPendingPaymentDeeplink);
      const sampleLnurl =
          'LNURL1DP68GURN8GHJ7VF3XGENJVE5UMD9E3K7MF0V9CXJTMKXP6XCEF';

      final router = await pump(
        tester,
        initial: 'realunit-wallet:lightning:$sampleLnurl',
      );

      expect(currentPath(router), appLinkColdStartLocation);
      expect(find.byKey(const Key('home')), findsOneWidget);
      expect(peekPendingPaymentDeeplink(), 'lightning:$sampleLnurl');
    },
  );

  testWidgets(
    'cold start on any scheme host/path boots without an error screen',
    (tester) async {
      for (final url in const [
        'realunit-wallet://',
        'realunit-wallet://open/foo?x=1',
        'realunit-wallet://anything',
      ]) {
        final router = await pump(tester, initial: url);
        expect(currentPath(router), appLinkColdStartLocation, reason: 'for $url');
        expect(
          find.byKey(const Key('home')),
          findsOneWidget,
          reason: 'for $url',
        );
      }
    },
  );

  testWidgets(
    'warm resume: a crafted scheme URL to an auth path is a no-op '
    '(no navigation, PIN gate not bypassed)',
    (tester) async {
      final router = await pump(tester);
      router.go('/settings');
      await tester.pumpAndSettle();

      // `realunit-wallet://dashboard` must not navigate anywhere on a warm
      // resume either — same no-op as the canonical open.
      router.go('realunit-wallet://dashboard');
      await tester.pumpAndSettle();

      expect(currentPath(router), '/settings');
      expect(find.byKey(const Key('settings')), findsOneWidget);
      expect(find.byKey(const Key('dashboard')), findsNothing);
    },
  );

  testWidgets(
    'warm resume: a crafted scheme URL carrying a real path does not navigate '
    '(flow-level gates not bypassed)',
    (tester) async {
      final router = await pump(tester);
      router.go('/dashboard');
      await tester.pumpAndSettle();

      // go_router matches on uri.path alone, so this WOULD match /settings if
      // the redirect let it fall through like the canonical path-less open.
      router.go('realunit-wallet://open/settings');
      await tester.pumpAndSettle();

      expect(currentPath(router), '/dashboard');
      expect(find.byKey(const Key('dashboard')), findsOneWidget);
      expect(find.byKey(const Key('settings')), findsNothing);
    },
  );

  testWidgets(
    'warm resume: a crafted path-carrying scheme URL over a pushed '
    'extra-required route neither navigates nor crashes',
    (tester) async {
      final router = await pump(tester);
      router.go('/dashboard');
      await tester.pumpAndSettle();

      // Backgrounding on a pushed extra-required route is the everyday case
      // (e.g. /buyPaymentDetails while paying in the banking app).
      unawaited(router.push('/details', extra: 'payment'));
      await tester.pumpAndSettle();
      expect(find.text('payment'), findsOneWidget);

      // The crafted URL is rewritten to the canonical path-less open and ends
      // in the onException no-op. A currentLocation pin instead would rebuild
      // /details via `go` with a null extra and crash the builder cast.
      router.go('realunit-wallet://open/settings');
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('payment'), findsOneWidget);
      expect(router.canPop(), isTrue);
      router.pop();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('dashboard')), findsOneWidget);
    },
  );

  testWidgets(
    'cold start on a crafted scheme URL to an auth path still boots to /home '
    '(PIN gate not bypassed)',
    (tester) async {
      // `realunit-wallet://dashboard` must not open the authenticated dashboard;
      // with no prior route it boots to /home and the real boot flow (PIN gate)
      // in main.dart runs.
      final router = await pump(tester, initial: 'realunit-wallet://dashboard');

      expect(currentPath(router), appLinkColdStartLocation);
      expect(find.byKey(const Key('dashboard')), findsNothing);
      expect(find.byKey(const Key('home')), findsOneWidget);
    },
  );

  testWidgets('in-app navigation is left untouched by the scheme redirect', (
    tester,
  ) async {
    final router = await pump(tester);

    router.go('/dashboard');
    await tester.pumpAndSettle();
    expect(currentPath(router), '/dashboard');
    expect(find.byKey(const Key('dashboard')), findsOneWidget);
  });
}
