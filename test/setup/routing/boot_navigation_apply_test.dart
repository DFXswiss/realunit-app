import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:realunit_wallet/setup/routing/boot_navigation.dart';
import 'package:realunit_wallet/setup/routing/routes/app_routes.dart';
import 'package:realunit_wallet/setup/routing/routes/pin_routes.dart';

// Drives the real `_navigate` wiring — `resolveBootNavigation` + the go_router
// side effect `applyBootNavAction` — against a real [GoRouter]. This is the seam
// the pure-function table and the cubit tests can't reach: it proves the
// decision is actually enacted on a router, and that a resume of an
// `extra`-required route lands on the dashboard WITHOUT building (and crashing
// on) that route. Pumping the full `WalletApp` is impractical (it depends on the
// whole DI graph + the global router building real, service-backed pages), so we
// exercise the smallest faithful seam instead.
void main() {
  // Only the routes this seam touches. `/buyPaymentDetails` mirrors the real
  // builder's non-nullable `extra` cast, so building it from a bare path throws
  // — exactly the crash the restore allowlist must prevent.
  GoRouter buildRouter() => GoRouter(
    initialLocation: '/verifyPin',
    routes: [
      GoRoute(
        name: PinRoutes.verify,
        path: '/verifyPin',
        builder: (_, _) => const Text('verify'),
      ),
      GoRoute(
        name: AppRoutes.dashboard,
        path: '/dashboard',
        builder: (_, _) => const Text('dashboard'),
      ),
      GoRoute(
        name: AppRoutes.kyc,
        path: '/kyc',
        builder: (_, _) => const Text('kyc'),
      ),
      GoRoute(
        name: AppRoutes.buyPaymentDetails,
        path: '/buyPaymentDetails',
        builder: (_, state) => Text('buy ${state.extra as Object}'),
      ),
      GoRoute(
        name: AppRoutes.pay,
        path: '/pay',
        builder: (_, state) => Text('pay ${state.extra}'),
      ),
    ],
  );

  // Fully-passed post-gate input: the router is on the PIN gate right after a
  // re-lock, so a captured non-gate route can be restored.
  BootNavAction resolveAfterRelock(String? resumeLocation) => resolveBootNavigation(
    isLoadingWallet: false,
    softwareTermsAccepted: true,
    hasWallet: true,
    onboardingCompleted: true,
    isPinSetup: true,
    isPinVerified: true,
    bitboxAddressRecoveryNeeded: false,
    walletLoaded: true,
    currentLocation: '/verifyPin',
    resumeLocation: resumeLocation,
  );

  String locationOf(GoRouter router) => router.routerDelegate.currentConfiguration.uri.toString();

  testWidgets(
    're-lock -> PIN -> restore lands on the captured /kyc route with the '
    'dashboard underneath (pop-based exits keep working)',
    (tester) async {
      final router = buildRouter();
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      var cleared = false;
      applyBootNavAction(
        resolveAfterRelock('/kyc'),
        router,
        onLoadWallet: () {},
        onClearResume: () => cleared = true,
      );
      await tester.pumpAndSettle();

      expect(find.text('kyc'), findsOneWidget);
      expect(effectiveLocation(router.routerDelegate.currentConfiguration), '/kyc');
      expect(cleared, isTrue);

      // The restore rebuilds the real entry shape (dashboard base + pushed
      // flow), so the flow's pop-based exits (Close buttons, AppBar auto-back)
      // still have somewhere to go — a bare `go` restore would strand them.
      expect(router.canPop(), isTrue);
      router.pop();
      await tester.pumpAndSettle();
      expect(find.text('dashboard'), findsOneWidget);
      expect(locationOf(router), '/dashboard');
    },
  );

  testWidgets('restoring /dashboard itself stays a plain go (nothing to pop)', (
    tester,
  ) async {
    final router = buildRouter();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    applyBootNavAction(
      resolveAfterRelock('/dashboard'),
      router,
      onLoadWallet: () {},
      onClearResume: () {},
    );
    await tester.pumpAndSettle();

    expect(find.text('dashboard'), findsOneWidget);
    expect(locationOf(router), '/dashboard');
    expect(router.canPop(), isFalse);
  });

  testWidgets(
    'resuming an extra-required route lands on /dashboard without throwing',
    (tester) async {
      final router = buildRouter();
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      final action = resolveAfterRelock('/buyPaymentDetails');
      // Fail-closed: not on the allowlist -> dashboard, never the crashing route.
      expect((action as BootNavGoNamed).routeName, AppRoutes.dashboard);

      var cleared = false;
      applyBootNavAction(
        action,
        router,
        onLoadWallet: () {},
        onClearResume: () => cleared = true,
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('dashboard'), findsOneWidget);
      expect(locationOf(router), '/dashboard');
      // The dashboard is a final landing — the stale capture must be dropped.
      expect(cleared, isTrue);
    },
  );

  testWidgets('navigating to a gate keeps the capture for the pending unlock', (
    tester,
  ) async {
    final router = buildRouter();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    // A re-lock diverts to the PIN gate. Clearing here would silently degrade
    // the post-unlock restore to the dashboard fallback.
    var cleared = false;
    applyBootNavAction(
      const BootNavGoNamed(PinRoutes.verify),
      router,
      onLoadWallet: () {},
      onClearResume: () => cleared = true,
    );
    await tester.pumpAndSettle();

    expect(find.text('verify'), findsOneWidget);
    expect(cleared, isFalse);
  });

  testWidgets(
    'premise guard: restoring /buyPaymentDetails from a bare path really throws',
    (tester) async {
      final router = buildRouter();
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      // Proves the crash the allowlist prevents is real: navigating to the
      // extra-required route without `extra` surfaces an exception.
      router.go('/buyPaymentDetails');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNotNull);
    },
  );

  testWidgets(
    'effectiveLocation reports a pushed route where the raw uri stays on the base',
    (tester) async {
      final router = buildRouter();
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      router.go('/dashboard');
      await tester.pumpAndSettle();
      expect(effectiveLocation(router.routerDelegate.currentConfiguration), '/dashboard');

      // The KYC flow is entered exactly like this: an imperative push on top
      // of the dashboard.
      unawaited(router.push('/kyc'));
      await tester.pumpAndSettle();

      // Premise guard for every effectiveLocation call site: the raw uri is
      // blind to the push — the helper is not.
      expect(locationOf(router), '/dashboard');
      expect(effectiveLocation(router.routerDelegate.currentConfiguration), '/kyc');
    },
  );

  group('pendingPaymentDeeplink replay', () {
    setUp(clearPendingPaymentDeeplink);
    tearDown(clearPendingPaymentDeeplink);

    testWidgets(
      'dashboard landing with a stashed payload pushes /pay on top and consumes the stash',
      (tester) async {
        final router = buildRouter();
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pumpAndSettle();

        stashPendingPaymentDeeplink('lightning:LNURL1DP68GURN8GHJ7VF3XGENJVE5UMD');
        applyBootNavAction(
          const BootNavGoNamed(AppRoutes.dashboard),
          router,
          onLoadWallet: () {},
          onClearResume: () {},
        );
        await tester.pumpAndSettle();

        // /pay is pushed ON TOP of /dashboard: once an opaque push settles,
        // Flutter only keeps the topmost route built, so /dashboard's own
        // Text is correctly absent from the tree right now (not a bug) —
        // prove "on top of, not instead of" via the match list + canPop, and
        // via the AFTER-pop check below where /dashboard is onstage again.
        expect(find.text('pay lightning:LNURL1DP68GURN8GHJ7VF3XGENJVE5UMD'), findsOneWidget);
        expect(
          router.routerDelegate.currentConfiguration.matches
              .map((m) => m.matchedLocation)
              .toList(),
          ['/dashboard', '/pay'],
        );
        expect(peekPendingPaymentDeeplink(), isNull);
        expect(router.canPop(), isTrue);
        router.pop();
        await tester.pumpAndSettle();
        expect(find.text('dashboard'), findsOneWidget);
      },
    );

    testWidgets(
      'dashboard landing with no stash pushes nothing extra',
      (tester) async {
        final router = buildRouter();
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pumpAndSettle();

        applyBootNavAction(
          const BootNavGoNamed(AppRoutes.dashboard),
          router,
          onLoadWallet: () {},
          onClearResume: () {},
        );
        await tester.pumpAndSettle();

        expect(find.text('dashboard'), findsOneWidget);
        expect(router.canPop(), isFalse);
      },
    );

    testWidgets(
      'a non-dashboard gate landing never consumes or replays the stash',
      (tester) async {
        final router = buildRouter();
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pumpAndSettle();

        stashPendingPaymentDeeplink('lightning:LNURL1DP68GURN8GHJ7VF3XGENJVE5UMD');
        applyBootNavAction(
          const BootNavGoNamed(PinRoutes.verify),
          router,
          onLoadWallet: () {},
          onClearResume: () {},
        );
        await tester.pumpAndSettle();

        expect(find.text('verify'), findsOneWidget);
        expect(peekPendingPaymentDeeplink(), 'lightning:LNURL1DP68GURN8GHJ7VF3XGENJVE5UMD');
      },
    );

    testWidgets(
      'warm unlock with stash: resolveAfterRelock(null) lands on dashboard, '
      'pushes /pay, and consumes the stash',
      (tester) async {
        final router = buildRouter();
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pumpAndSettle();

        // Full gate-ladder path (not a bare BootNavGoNamed): after a plain
        // PIN unlock with no captured resume location, resolveBootNavigation
        // returns BootNavGoNamed(dashboard), which replays the stash.
        stashPendingPaymentDeeplink('lightning:LNURL1DP68GURN8GHJ7VF3XGENJVE5UMD');
        applyBootNavAction(
          resolveAfterRelock(null),
          router,
          onLoadWallet: () {},
          onClearResume: () {},
        );
        await tester.pumpAndSettle();

        expect(find.text('pay lightning:LNURL1DP68GURN8GHJ7VF3XGENJVE5UMD'), findsOneWidget);
        expect(
          router.routerDelegate.currentConfiguration.matches
              .map((m) => m.matchedLocation)
              .toList(),
          ['/dashboard', '/pay'],
        );
        expect(peekPendingPaymentDeeplink(), isNull);
        expect(router.canPop(), isTrue);
        router.pop();
        await tester.pumpAndSettle();
        expect(find.text('dashboard'), findsOneWidget);
      },
    );

    testWidgets(
      'BootNavRestore replays a stashed pendingPaymentDeeplink, pushing /pay '
      'on top of the restored location',
      (tester) async {
        final router = buildRouter();
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pumpAndSettle();

        stashPendingPaymentDeeplink('lightning:LNURL1DP68GURN8GHJ7VF3XGENJVE5UMD');
        applyBootNavAction(
          resolveAfterRelock('/kyc'),
          router,
          onLoadWallet: () {},
          onClearResume: () {},
        );
        await tester.pumpAndSettle();

        // /pay is pushed ON TOP of the restored stack (dashboard base + /kyc):
        // prove via the match list + canPop, and via the AFTER-pop check
        // where /kyc is onstage again.
        expect(find.text('pay lightning:LNURL1DP68GURN8GHJ7VF3XGENJVE5UMD'), findsOneWidget);
        expect(
          router.routerDelegate.currentConfiguration.matches
              .map((m) => m.matchedLocation)
              .toList(),
          ['/dashboard', '/kyc', '/pay'],
        );
        expect(peekPendingPaymentDeeplink(), isNull);
        expect(router.canPop(), isTrue);
        router.pop();
        await tester.pumpAndSettle();
        expect(find.text('kyc'), findsOneWidget);
      },
    );

    testWidgets(
      'BootNavStay replays a stashed pendingPaymentDeeplink, pushing /pay on '
      'top of the current location',
      (tester) async {
        final router = buildRouter();
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pumpAndSettle();

        // BootNavStay itself never navigates — put the router on a real
        // non-gate location first so /pay has something to land on top of.
        router.go('/dashboard');
        await tester.pumpAndSettle();

        stashPendingPaymentDeeplink('lightning:LNURL1DP68GURN8GHJ7VF3XGENJVE5UMD');
        applyBootNavAction(
          const BootNavStay(),
          router,
          onLoadWallet: () {},
          onClearResume: () {},
        );
        await tester.pumpAndSettle();

        expect(find.text('pay lightning:LNURL1DP68GURN8GHJ7VF3XGENJVE5UMD'), findsOneWidget);
        expect(
          router.routerDelegate.currentConfiguration.matches
              .map((m) => m.matchedLocation)
              .toList(),
          ['/dashboard', '/pay'],
        );
        expect(peekPendingPaymentDeeplink(), isNull);
        expect(router.canPop(), isTrue);
        router.pop();
        await tester.pumpAndSettle();
        expect(find.text('dashboard'), findsOneWidget);
      },
    );
  });
}
