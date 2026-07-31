import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:realunit_wallet/setup/routing/routes/app_routes.dart';
import 'package:realunit_wallet/setup/routing/routes/onboarding_routes.dart';
import 'package:realunit_wallet/setup/routing/routes/pin_routes.dart';

/// The outcome of the boot/lock navigation decision (see
/// [resolveBootNavigation]) driven by `main.dart`'s `_navigate`. The decision
/// itself is `getIt`-free so the whole gate ladder can be unit-tested
/// exhaustively; [applyBootNavAction] below performs the go_router side effect.
sealed class BootNavAction {
  const BootNavAction();
}

/// The wallet is still loading — do not navigate yet, wait for the next
/// emission that flips `isLoadingWallet` off.
final class BootNavWaitForLoad extends BootNavAction {
  const BootNavWaitForLoad();
}

/// All gates passed but the wallet is not in memory yet — trigger the load and
/// wait for the resulting HomeBloc emission.
final class BootNavLoadWallet extends BootNavAction {
  const BootNavLoadWallet();
}

/// Navigate to a gate / landing route by its go_router name.
final class BootNavGoNamed extends BootNavAction {
  final String routeName;
  const BootNavGoNamed(this.routeName);
}

/// Restore the in-flight (non-gate) route the user was on before the background
/// lock / re-lock, addressed by its location (path).
final class BootNavRestore extends BootNavAction {
  final String location;
  const BootNavRestore(this.location);
}

/// All gates passed and the user is already on a valid non-gate route — leave
/// them exactly where they are, never yank them to the dashboard.
final class BootNavStay extends BootNavAction {
  const BootNavStay();
}

/// The location the user actually sees, including imperatively pushed routes.
///
/// `RouteMatchList.uri` only reflects declarative (`go`) matches — after a
/// `push` (how the KYC flow is entered from Buy/Sell) it still reports the
/// base route underneath. Everything that judges or captures "where the user
/// is" (the boot machine's `currentLocation`, the background capture, the
/// scheme-open redirect) must read this helper instead, or a pushed flow is
/// invisible to it.
String effectiveLocation(RouteMatchList configuration) {
  final matches = configuration.matches;
  final last = matches.isEmpty ? null : matches.last;
  if (last is ImperativeRouteMatch) return last.matches.uri.toString();
  return configuration.uri.toString();
}

/// Locations that are boot/lock gates: `_navigate` re-derives them from state
/// and must never treat one as an in-flight route to restore. What *is*
/// restorable is governed by the [restorableLocations] allowlist below — not
/// by "anything that is not a gate".
const Set<String> gateLocations = {
  '/home',
  '/welcome',
  '/createWallet',
  '/restoreWallet',
  '/verifySeed',
  '/onboardingComplete',
  '/pinGate',
  '/setupPin',
  '/verifyPin',
  '/bitboxAddressRecovery',
  '/debugAuth',
};

/// Whether [loc] resolves to one of the [gateLocations] gates. Compares the
/// path only, so a query string cannot defeat the check.
bool isGateLocation(String loc) => gateLocations.contains(Uri.parse(loc).path);

/// Maps the location the app was backgrounded on to what the resume capture
/// should store: gate locations map to null so a nested re-lock — backgrounded
/// again while the PIN gate is showing — keeps the earlier in-flight capture
/// instead of clobbering it with the gate.
String? resumeCaptureFor(String location) => isGateLocation(location) ? null : location;

/// Non-gate locations safe to restore after a resume / re-lock: they rebuild
/// from a bare path (no required `extra`) and sit behind no secondary PIN gate.
/// Fail-closed — anything not listed falls back to the dashboard (the pre-fix
/// behaviour), so a newly added route can never silently become restorable (and
/// crash on a missing `extra`) or surface a PIN-gated screen. Matched by exact
/// path: `/settings/seed` != `/settings`, `/buyPaymentDetails` != `/buy`.
const Set<String> restorableLocations = {
  '/kyc',
  '/dashboard',
  '/buy',
  '/sell',
  '/receive',
  '/settings',
  '/support',
};

/// Whether [loc]'s path is in the [restorableLocations] allowlist (query
/// string ignored).
bool isRestorableLocation(String loc) => restorableLocations.contains(Uri.parse(loc).path);

/// Pure boot/lock routing decision, evaluated on every HomeBloc / PinAuthCubit
/// emission.
///
/// The gate ladder is evaluated top to bottom, so a restore can only ever be
/// returned by the final branch — after `!isPinVerified` has already diverted
/// to the PIN gate. A [BootNavRestore] is additionally limited to the
/// [restorableLocations] allowlist, so it never re-enters a gate route, never
/// bypasses the PIN gate, and never targets a route that needs `extra`.
BootNavAction resolveBootNavigation({
  required bool isLoadingWallet,
  required bool softwareTermsAccepted,
  required bool hasWallet,
  required bool onboardingCompleted,
  required bool isPinSetup,
  required bool isPinVerified,
  required bool bitboxAddressRecoveryNeeded,
  required bool walletLoaded,
  required String currentLocation,
  required String? resumeLocation,
}) {
  if (isLoadingWallet) return const BootNavWaitForLoad();
  if (!softwareTermsAccepted) return const BootNavGoNamed(AppRoutes.home);
  if (!hasWallet) return const BootNavGoNamed(OnboardingRoutes.welcome);
  if (!onboardingCompleted) {
    return const BootNavGoNamed(OnboardingRoutes.completed);
  }
  if (!isPinSetup) return const BootNavGoNamed(PinRoutes.setup);
  if (!isPinVerified) return const BootNavGoNamed(PinRoutes.verify);
  if (bitboxAddressRecoveryNeeded) {
    // A BitBox wallet was persisted with an empty/invalid address — divert to
    // the re-pairing recovery flow instead of loading it into the dashboard
    // (which would crash the build via `EthereumAddress.fromHex("")`).
    return const BootNavGoNamed(AppRoutes.bitboxAddressRecovery);
  }
  if (!walletLoaded) return const BootNavLoadWallet();

  // All gates passed.
  if (!isGateLocation(currentLocation)) return const BootNavStay();
  if (resumeLocation != null && isRestorableLocation(resumeLocation)) {
    return BootNavRestore(resumeLocation);
  }
  return const BootNavGoNamed(AppRoutes.dashboard);
}

/// Payment-deeplink payload captured by `appLinkSchemeRedirect`
/// (app_link_entry.dart) on a COLD start, or on a warm resume while the app is
/// still on a PIN/unlock gate, before the boot/unlock gate ladder has cleared.
/// Held here until [applyBootNavAction] replays it as an imperative `/pay`
/// push at the first post-unlock terminal landing — dashboard, restore, or
/// stay — i.e. strictly after the same PIN/unlock gate ladder a normal `/pay`
/// navigation passes, so the replay can never bypass it. A warm-resume
/// payment deeplink while already unlocked normally pushes straight away,
/// unless a re-lock is detected at the deferred execution-time check, in
/// which case it stashes here for post-unlock replay (same path as the
/// warm-locked branch). Pre-unlock gate waypoints (e.g.
/// [BootNavGoNamed] for PIN verify) never consume or replay the stash; every
/// post-unlock terminal landing (dashboard / restore / stay) replays and
/// consumes it, so the stash can never survive past the first of those.
///
/// Last-write-wins on the stash — a newer deeplink deliberately supersedes an
/// older un-replayed one; no queueing.
String? _pendingPaymentDeeplink;

/// Stashes [payload] for post-unlock replay via [applyBootNavAction].
/// Last-write-wins: a newer deeplink deliberately supersedes an older
/// un-replayed one; no queueing.
void stashPendingPaymentDeeplink(String payload) {
  _pendingPaymentDeeplink = payload;
}

/// Returns the current stashed payload and clears it in the same call.
String? takePendingPaymentDeeplink() {
  final payload = _pendingPaymentDeeplink;
  _pendingPaymentDeeplink = null;
  return payload;
}

/// Clears any stashed payment deeplink without returning it.
void clearPendingPaymentDeeplink() {
  _pendingPaymentDeeplink = null;
}

/// Returns the current stashed payload without clearing it (read-only).
String? peekPendingPaymentDeeplink() => _pendingPaymentDeeplink;

/// Executes a [resolveBootNavigation] decision against [router]. Split out from
/// `main.dart`'s `_navigate` so the routing side effects can be driven against a
/// real [GoRouter] in a widget test (the decision itself is covered by the pure
/// table). [onLoadWallet] triggers the wallet load; [onClearResume] drops the
/// captured resume location once it is spent.
void applyBootNavAction(
  BootNavAction action,
  GoRouter router, {
  required void Function() onLoadWallet,
  required void Function() onClearResume,
}) {
  switch (action) {
    case BootNavWaitForLoad():
      return;
    case BootNavLoadWallet():
      // Wallet not loaded yet — trigger load and wait for the HomeBloc update.
      onLoadWallet();
      return;
    case BootNavGoNamed(:final routeName):
      // Reaching the dashboard is the final landing — drop any stale resume
      // capture so a later benign emission can't bounce the user around, and
      // replay a cold-start / locked-warm-resume payment deeplink now that the
      // same gate ladder a normal /pay navigation passes has just been cleared
      // (see takePendingPaymentDeeplink / stashPendingPaymentDeeplink).
      if (routeName == AppRoutes.dashboard) {
        onClearResume();
        final payload = takePendingPaymentDeeplink();
        if (payload != null) {
          router.goNamed(routeName);
          unawaited(router.pushNamed(AppRoutes.pay, extra: payload));
          return;
        }
      }
      // Non-dashboard named navigation (PIN/setup/onboarding gates, …) is an
      // intermediate step of the same boot ladder: the stash must survive
      // through to the eventual dashboard landing so cold-start and
      // locked-warm-resume payment deeplinks can still replay. Do NOT clear
      // the pending-payment stash here.
      router.goNamed(routeName);
      return;
    case BootNavRestore(:final location):
      // Return to the in-flight route the user was on before the re-lock,
      // reached only after the PIN gate above has already passed. Rebuild the
      // real entry shape — dashboard as base, flow pushed on top — so the
      // flow's pop-based exits (Close buttons, AppBar auto-back) keep working;
      // a bare `go` would strand the restored route as the only match with
      // nothing underneath to pop back to. onClearResume drops the spent
      // capture so a later emission can't re-restore. Then, if a payment
      // deeplink was stashed while locked, replay it as an imperative /pay
      // push on top of the restored location (same post-unlock terminal
      // consumption as the dashboard branch).
      onClearResume();
      if (Uri.parse(location).path == '/dashboard') {
        router.go(location);
      } else {
        router.goNamed(AppRoutes.dashboard);
        unawaited(router.push(location));
      }
      final payload = takePendingPaymentDeeplink();
      if (payload != null) {
        unawaited(router.pushNamed(AppRoutes.pay, extra: payload));
      }
      return;
    case BootNavStay():
      // Already on a valid non-gate route — discard any stale resume capture.
      // This is a post-unlock terminal landing: if a payment deeplink was
      // stashed while locked, replay it as an imperative /pay push on top of
      // the current location (the only navigation this branch performs when
      // a stash exists).
      onClearResume();
      final payload = takePendingPaymentDeeplink();
      if (payload != null) {
        unawaited(router.pushNamed(AppRoutes.pay, extra: payload));
      }
      return;
  }
}
