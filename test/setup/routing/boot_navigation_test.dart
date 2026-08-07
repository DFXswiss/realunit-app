import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:realunit_wallet/setup/routing/boot_navigation.dart';
import 'package:realunit_wallet/setup/routing/router_config.dart';
import 'package:realunit_wallet/setup/routing/routes/app_routes.dart';
import 'package:realunit_wallet/setup/routing/routes/onboarding_routes.dart';
import 'package:realunit_wallet/setup/routing/routes/pin_routes.dart';

void main() {
  // The drift-pin group below constructs the real global GoRouter; initialize
  // the test binding up front, matching the repo convention for plain-test
  // files that touch framework globals.
  TestWidgetsFlutterBinding.ensureInitialized();

  // A fully-passed, steady-state input where the user sits on a non-gate route
  // (/kyc). Individual tests flip exactly one field to exercise one branch.
  BootNavAction resolve({
    bool isLoadingWallet = false,
    bool softwareTermsAccepted = true,
    bool hasWallet = true,
    bool onboardingCompleted = true,
    bool isPinSetup = true,
    bool isPinVerified = true,
    bool bitboxAddressRecoveryNeeded = false,
    bool walletLoaded = true,
    String currentLocation = '/kyc',
    String? resumeLocation,
  }) => resolveBootNavigation(
    isLoadingWallet: isLoadingWallet,
    softwareTermsAccepted: softwareTermsAccepted,
    hasWallet: hasWallet,
    onboardingCompleted: onboardingCompleted,
    isPinSetup: isPinSetup,
    isPinVerified: isPinVerified,
    bitboxAddressRecoveryNeeded: bitboxAddressRecoveryNeeded,
    walletLoaded: walletLoaded,
    currentLocation: currentLocation,
    resumeLocation: resumeLocation,
  );

  group('resolveBootNavigation gate ladder', () {
    test('isLoadingWallet short-circuits to wait, ignoring everything else', () {
      expect(
        resolve(
          isLoadingWallet: true,
          softwareTermsAccepted: false,
          resumeLocation: '/kyc',
        ),
        isA<BootNavWaitForLoad>(),
      );
    });

    test('missing software terms -> home', () {
      final action = resolve(softwareTermsAccepted: false);
      expect((action as BootNavGoNamed).routeName, AppRoutes.home);
    });

    test('no wallet -> welcome', () {
      final action = resolve(hasWallet: false);
      expect((action as BootNavGoNamed).routeName, OnboardingRoutes.welcome);
    });

    test('onboarding not completed -> onboarding completed screen', () {
      final action = resolve(onboardingCompleted: false);
      expect((action as BootNavGoNamed).routeName, OnboardingRoutes.completed);
    });

    test('pin not set up -> setup pin', () {
      final action = resolve(isPinSetup: false);
      expect((action as BootNavGoNamed).routeName, PinRoutes.setup);
    });

    test('pin not verified -> verify pin', () {
      final action = resolve(isPinVerified: false);
      expect((action as BootNavGoNamed).routeName, PinRoutes.verify);
    });

    test('bitbox address recovery needed -> recovery flow', () {
      final action = resolve(bitboxAddressRecoveryNeeded: true);
      expect(
        (action as BootNavGoNamed).routeName,
        AppRoutes.bitboxAddressRecovery,
      );
    });

    test('wallet not loaded -> load wallet', () {
      expect(resolve(walletLoaded: false), isA<BootNavLoadWallet>());
    });
  });

  group('resolveBootNavigation gate precedence over restore (security)', () {
    test(
      'an un-verified PIN wins over a pending restore: never bypasses the gate',
      () {
        // The router is on the PIN gate and a restorable /kyc is captured, but
        // isPinVerified is false -> we MUST go to the PIN gate, never restore.
        final action = resolve(
          isPinVerified: false,
          currentLocation: '/verifyPin',
          resumeLocation: '/kyc',
        );
        expect((action as BootNavGoNamed).routeName, PinRoutes.verify);
      },
    );
  });

  group('resolveBootNavigation post-gate landing', () {
    test('already on a valid non-gate route -> stay put (never yank)', () {
      // Even with a stale capture present, an active non-gate route is kept.
      expect(
        resolve(currentLocation: '/kyc', resumeLocation: '/settings'),
        isA<BootNavStay>(),
      );
    });

    test('on the dashboard steady state -> stay put', () {
      expect(resolve(currentLocation: '/dashboard'), isA<BootNavStay>());
    });

    test('core scenario: relocked on the PIN gate, restore the captured /kyc', () {
      final action = resolve(
        currentLocation: '/verifyPin',
        resumeLocation: '/kyc',
      );
      expect((action as BootNavRestore).location, '/kyc');
    });

    test('on a gate route with no capture -> dashboard fallback', () {
      final action = resolve(currentLocation: '/verifyPin', resumeLocation: null);
      expect((action as BootNavGoNamed).routeName, AppRoutes.dashboard);
    });

    test('a gate resume location is NOT restored -> dashboard fallback', () {
      // The captured route is itself a gate (e.g. /setupPin): restoring it
      // would be pointless / unsafe, so fall back to the dashboard.
      final action = resolve(
        currentLocation: '/verifyPin',
        resumeLocation: '/setupPin',
      );
      expect((action as BootNavGoNamed).routeName, AppRoutes.dashboard);
    });

    test('restore preserves a resume path that carries a query string', () {
      final action = resolve(
        currentLocation: '/verifyPin',
        resumeLocation: '/kyc?context=buy',
      );
      expect((action as BootNavRestore).location, '/kyc?context=buy');
    });

    test('an extra-required resume route is NOT restored -> dashboard', () {
      // `/buyPaymentDetails` rebuilds via `state.extra as BuyPaymentDetailsParams`
      // (non-nullable): restoring it from a bare path would crash, so it is not
      // on the allowlist and falls back to the dashboard (fail-closed).
      final action = resolve(
        currentLocation: '/verifyPin',
        resumeLocation: '/buyPaymentDetails',
      );
      expect((action as BootNavGoNamed).routeName, AppRoutes.dashboard);
    });

    test('a PIN-gated settings subroute is NOT restored -> dashboard', () {
      // `/settings/seed` sits behind a secondary PIN gate; exact-path matching
      // (`/settings/seed` != `/settings`) keeps it off the allowlist.
      final action = resolve(
        currentLocation: '/verifyPin',
        resumeLocation: '/settings/seed',
      );
      expect((action as BootNavGoNamed).routeName, AppRoutes.dashboard);
    });
  });

  group('isGateLocation', () {
    for (final loc in gateLocations) {
      test('$loc is a gate', () => expect(isGateLocation(loc), isTrue));
    }

    test('a non-gate app route is not a gate', () {
      expect(isGateLocation('/kyc'), isFalse);
      expect(isGateLocation('/dashboard'), isFalse);
      expect(isGateLocation('/settings/security'), isFalse);
    });

    test('a query string does not defeat the gate check', () {
      expect(isGateLocation('/verifyPin?x=1'), isTrue);
    });

    test('resumeCaptureFor maps gates to null and keeps in-flight routes', () {
      expect(resumeCaptureFor('/verifyPin'), isNull);
      expect(resumeCaptureFor('/pinGate'), isNull);
      expect(resumeCaptureFor('/kyc'), '/kyc');
      expect(resumeCaptureFor('/kyc?context=buy'), '/kyc?context=buy');
      expect(resumeCaptureFor(''), '');
    });

    test('a query string does not turn a non-gate into a gate', () {
      expect(isGateLocation('/kyc?context=buy'), isFalse);
    });
  });

  group('isRestorableLocation', () {
    for (final loc in restorableLocations) {
      test(
        '$loc is restorable',
        () => expect(isRestorableLocation(loc), isTrue),
      );
    }

    test('an extra-required route is not restorable', () {
      expect(isRestorableLocation('/buyPaymentDetails'), isFalse);
      expect(isRestorableLocation('/sellBitbox'), isFalse);
      expect(isRestorableLocation('/legalDocument'), isFalse);
      expect(isRestorableLocation('/webView'), isFalse);
    });

    test('a PIN-gated / sensitive subroute is not restorable', () {
      expect(isRestorableLocation('/settings/seed'), isFalse);
      expect(isRestorableLocation('/settings/security'), isFalse);
      expect(isRestorableLocation('/settings/security/changePin'), isFalse);
    });

    test('a gate route is not restorable', () {
      expect(isRestorableLocation('/verifyPin'), isFalse);
      expect(isRestorableLocation('/home'), isFalse);
    });

    test('a query string does not defeat the allowlist match', () {
      expect(isRestorableLocation('/kyc?context=buy'), isTrue);
    });
  });

  group('drift pin against the real route table', () {
    // Both sets duplicate path literals from router_config.dart. A path rename
    // there would otherwise drift silently: an unrecognized gate strands the
    // user on the gate screen (BootNavStay instead of the dashboard fallback),
    // an unrecognized restorable route silently degrades to the dashboard.
    Set<String> collectPaths(List<RouteBase> routes, String prefix) {
      final paths = <String>{};
      for (final route in routes) {
        var next = prefix;
        if (route is GoRoute) {
          next = route.path.startsWith('/')
              ? route.path
              : '${prefix == '/' ? '' : prefix}/${route.path}';
          paths.add(next);
        }
        paths.addAll(collectPaths(route.routes, next));
      }
      return paths;
    }

    test('every gate and restorable location is a real route path', () {
      // Constructing GoRouter never invokes page builders, so walking the real
      // routerConfig needs neither DI nor pumpWidget.
      final realPaths = collectPaths(routerConfig.configuration.routes, '');

      expect(gateLocations.difference(realPaths), isEmpty);
      expect(restorableLocations.difference(realPaths), isEmpty);
    });
  });
}
