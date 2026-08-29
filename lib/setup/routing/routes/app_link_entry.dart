import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:realunit_wallet/packages/io/normalize_referral_code.dart';
import 'package:realunit_wallet/screens/pin/bloc/auth/pin_auth_cubit.dart';
import 'package:realunit_wallet/setup/di.dart';
import 'package:realunit_wallet/setup/routing/boot_navigation.dart';
import 'package:realunit_wallet/setup/routing/referral_bind.dart';
import 'package:realunit_wallet/setup/routing/referral_pending_code.dart';
import 'package:realunit_wallet/setup/routing/routes/app_routes.dart';

/// Custom URL scheme the app is opened with. Registered in
/// `ios/Runner/Info.plist` (`CFBundleURLSchemes`) and
/// `android/app/src/main/AndroidManifest.xml` (VIEW intent-filter).
const String appLinkScheme = 'realunit-wallet';

/// Canonical button target the website links to. Any `realunit-wallet://…` URL
/// works — this is just the agreed, stable one.
const String appLinkUrl = 'realunit-wallet://open';

/// Cold-start fallback location (see [appLinkSchemeRedirect]) — the router's
/// normal entry, identical to `GoRouter.initialLocation`.
const String appLinkColdStartLocation = '/home';

/// Detects and extracts a DFX OpenCryptoPay payment payload out of a
/// `realunit-wallet:…` deeplink.
///
/// The DFX `/pl` frontend builds the deeplink generically as
/// `{deepLink}lightning:{LNURL}` with the backend `deepLink='realunit-wallet:'`
/// (no `//`), so the app receives the single-colon opaque form
/// `realunit-wallet:lightning:<LNURL>`. A `//`-prefixed variant
/// (`realunit-wallet://lightning:<LNURL>`) never reaches this function in
/// production: go_router derives `state.uri` via `Uri.parse` of the route-info,
/// which throws on that form before [appLinkSchemeRedirect] /
/// [extractPaymentDeeplinkPayload] is ever called — there is nothing to strip.
///
/// Works on the raw URI STRING, not `Uri` component accessors: this is an
/// opaque URI, not a hierarchical one, so `.host`/`.path` are not a reliable
/// general parsing strategy.
///
/// Returns the payload to feed into `PayScanCubit.onCodeDetected` VERBATIM
/// (e.g. `lightning:LNURL1...`, a bare `LNURL1...`, or a bare `https://...`
/// lnurlp URL), or null when [rawUri] is not a recognized payment deeplink —
/// including the canonical path-less open and any other path-carrying scheme
/// URL, which stay on the existing no-op / rewrite path in
/// [appLinkSchemeRedirect]. No validation beyond this structural sniff: a
/// malformed match is still returned and left for `LnurlDecoder` (reached via
/// `onCodeDetected`) to reject — this function must not swallow or
/// pre-validate (no silent fallback).
String? extractPaymentDeeplinkPayload(String rawUri) {
  const prefix = '$appLinkScheme:';
  if (!rawUri.startsWith(prefix)) return null;
  final remainder = rawUri.substring(prefix.length);
  if (remainder.isEmpty) return null;

  final isLightning = remainder.startsWith('lightning:');
  final isBareLnurl = remainder.toUpperCase().startsWith('LNURL');
  final isHttpLnurlp = remainder.startsWith('http://') || remainder.startsWith('https://');
  if (!isLightning && !isBareLnurl && !isHttpLnurlp) return null;
  return remainder;
}

const _referralLinkHosts = {
  'realunit.app',
  'www.realunit.app',
  'dev.realunit.app',
};

bool _isReferralPathKind(String? value) => value == 'invite' || value == 'promo';

bool _isWebReferralLink(Uri uri) =>
    (uri.scheme == 'https' || uri.scheme == 'http' || uri.scheme == 'intent') &&
    _referralLinkHosts.contains(uri.host);

/// Extracts a referral/promo invite code from a custom-scheme or https App Link.
///
/// Matches:
/// - `realunit-wallet://invite/{code}` and `realunit-wallet://promo/{code}`
/// - `realunit-wallet:invite/{code}` and `realunit-wallet:promo/{code}`
/// - `https://realunit.app/invite/{code}` and `/promo/{code}`
///   (Android App Links / iOS Universal Links)
/// - `intent://realunit.app/invite/{code}#Intent;scheme=https;…` (Chrome)
/// - `intent://invite/{code}#Intent;scheme=realunit-wallet;…`
/// - `android-app://swiss.realunit.app/https/realunit.app/invite/{code}`
/// - `ios-app://6759720010/realunit-wallet/invite/{code}`
/// - a share message or nested invite URL in `app-argument`
///
/// Returns the last path segment (trimmed, percent-decoded, max 256) or
/// null when not a referral/promo link. Invite and promo share one code field.
String? _referralCodeFromQuery(Uri uri) {
  return referralCodeFromQueryParameters(uri.queryParameters);
}

String? _referralCodeFromRawQuery(String remainder) {
  final q = remainder.indexOf('?');
  if (q < 0) return null;
  return referralCodeFromQueryParameters(
    Uri.splitQueryString(remainder.substring(q + 1)),
  );
}

String? _referralCodeFromFragment(Uri uri) {
  if (uri.fragment.isEmpty) return null;
  return referralCodeFromInput(uri.fragment) ?? normalizeReferralCode(uri.fragment);
}

String? _rawQueryValue(String raw, String key) {
  final q = raw.indexOf('?');
  if (q < 0) return null;
  return Uri.splitQueryString(raw.substring(q + 1))[key];
}

String? extractReferralInviteCode(Uri uri) {
  final direct = _extractReferralInviteCode(uri);
  if (direct != null) return direct;
  final fromRaw = referralCodeFromInput(uri.toString());
  if (fromRaw != null) return fromRaw;
  final argument =
      uri.queryParameters['app-argument'] ?? _rawQueryValue(uri.toString(), 'app-argument');
  if (argument == null || argument.isEmpty) return null;
  final nestedUri = Uri.tryParse(argument);
  if (nestedUri != null && nestedUri.toString() != uri.toString()) {
    final nested = _extractReferralInviteCode(nestedUri);
    if (nested != null) return nested;
  }
  return referralCodeFromInput(argument);
}

final _invitePathRemainder = RegExp(
  r'^/+(invite|promo)/(.*)$',
  caseSensitive: false,
);

final _opaqueInviteRemainder = RegExp(
  r'^(invite|promo)/(.*)$',
  caseSensitive: false,
);

String? _codeFromKindPath(String path) {
  final rest = path.startsWith('/') ? path.substring(1) : path;
  if (rest.isEmpty) return null;
  return referralCodeFromPathRemainder(rest);
}

String? _extractReferralInviteCode(Uri uri) {
  if (_isWebReferralLink(uri)) {
    final match = _invitePathRemainder.firstMatch(uri.path);
    if (match != null && match.group(2)!.isNotEmpty) {
      final fromRest = referralCodeFromPathRemainder(match.group(2));
      if (fromRest != null) return fromRest;
    }
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty || !_isReferralPathKind(segments.first)) {
      return null;
    }
    if (segments.length >= 2) {
      final fromSeg = referralCodeFromInput(segments[1]);
      if (fromSeg != null) return fromSeg;
    }
    return _referralCodeFromQuery(uri) ?? _referralCodeFromFragment(uri);
  }

  if (uri.scheme == 'intent' && _isReferralPathKind(uri.host)) {
    final fromRest = _codeFromKindPath(uri.path);
    if (fromRest != null) return fromRest;
    return _referralCodeFromQuery(uri) ?? _referralCodeFromFragment(uri);
  }

  if (uri.scheme == 'android-app') {
    final match = RegExp(
      r'^/+(https|http)/([^/]+)/(invite|promo)/(.*)$',
      caseSensitive: false,
    ).firstMatch(uri.path);
    if (match != null && _referralLinkHosts.contains(match.group(2)!.toLowerCase())) {
      return referralCodeFromPathRemainder(match.group(4));
    }
    return null;
  }

  if (uri.scheme == 'ios-app') {
    final match = RegExp(
      r'^/+(?:realunit-wallet/)?(invite|promo)/(.*)$',
      caseSensitive: false,
    ).firstMatch(uri.path);
    if (match != null && match.group(2)!.isNotEmpty) {
      return referralCodeFromPathRemainder(match.group(2));
    }
    return null;
  }

  if (uri.scheme != appLinkScheme) return null;

  // Prefer structured Uri parts when hierarchical (`://invite/{code}`).
  if (_isReferralPathKind(uri.host)) {
    final fromRest = _codeFromKindPath(uri.path);
    if (fromRest != null) return fromRest;
    return _referralCodeFromQuery(uri) ?? _referralCodeFromFragment(uri);
  }

  // Fall back to raw-string parsing for opaque `realunit-wallet:invite/{code}`
  // and any path-form the Uri parser did not split into host/path.
  final raw = uri.toString();
  const prefix = '$appLinkScheme:';
  if (!raw.startsWith(prefix)) return null;
  var remainder = raw.substring(prefix.length);
  if (remainder.startsWith('//')) remainder = remainder.substring(2);
  final withoutQuery = remainder.split('?').first;
  final opaque = _opaqueInviteRemainder.firstMatch(withoutQuery);
  if (opaque != null && opaque.group(2)!.isNotEmpty) {
    final fromRest = referralCodeFromPathRemainder(opaque.group(2));
    if (fromRest != null) return fromRest;
  }
  final segments = withoutQuery.split('/').where((s) => s.isNotEmpty).toList();
  if (segments.length >= 2 && _isReferralPathKind(segments.first)) {
    final fromSeg = referralCodeFromInput(segments[1]);
    if (fromSeg != null) return fromSeg;
  }
  if (segments.length >= 1 && _isReferralPathKind(segments.first)) {
    return _referralCodeFromRawQuery(remainder) ?? _referralCodeFromFragment(uri);
  }
  return null;
}

/// Top-level go_router redirect for custom-scheme opens.
///
/// A `realunit-wallet://…` open (canonical `realunit-wallet://open`) only brings
/// the app to the foreground — it must NOT force any in-app navigation.
///
/// Cold start: there is no prior in-app route ([currentLocation] is empty or
/// the scheme URL itself), so it hands off to the normal boot entry and lets
/// `main.dart`'s boot flow take over — the PIN gate and boot ordering stay
/// untouched.
///
/// Warm resume, canonical path-less open (`realunit-wallet://open`): it returns
/// `null` so the scheme URL stays unmatched and falls through to
/// [appLinkOnException], which keeps the current route configuration untouched
/// — a true no-op. Returning a location string here instead would be applied as
/// a `go` and REPLACE the whole match list: an imperatively pushed route (the
/// KYC flow from Buy/Sell) would be dropped together with its page-scoped
/// state, its `extra`, and the back stack underneath it.
///
/// Warm resume, scheme URL CARRYING a path: go_router matches on `uri.path`
/// alone, so `realunit-wallet://open/settings/seed` would match — and with a
/// `null` return it would navigate, straight past flow-level gates (the seed
/// page's PIN gate lives in the settings navigation path, not on the route).
/// Returning the current location instead would be no safer: applied as a
/// `go`, it rebuilds a pushed `extra`-required route (`/buyPaymentDetails`,
/// `/webView`, …) with a null `extra` and crashes its builder cast. So crafted
/// path-carrying URLs are rewritten to the canonical [appLinkUrl]: go_router
/// resolves the rewritten URL to an unmatched (error) match list and
/// short-circuits before any further redirect pass, so the chain terminates
/// and [appLinkOnException] keeps the configuration — the same true no-op as
/// the canonical open, with no rebuild at all.
///
/// Payment-deeplink carve-out: when the scheme URL carries a DFX OpenCryptoPay
/// payload (see [extractPaymentDeeplinkPayload]), the same security properties
/// still hold. Locked vs unlocked is classified by the authoritative pair
/// `isPinVerified && isPinSetup` (read only when already in-app / booted, so
/// the DI lookup is safe), not by location membership in [isGateLocation] and
/// not by `isPinVerified` alone. `PinAuthCubit.initialize()` sets
/// `isPinVerified: !isPinSetup`, so before any PIN is configured
/// `isPinVerified` is vacuously true — on `/setupPin` that auto-pass must not
/// be treated as "session unlocked" or a warm-resume payment deeplink would
/// deferred-push `/pay` and bypass the mandatory PIN-setup gate.
///
/// Warm resume, unlocked (`isInAppRoute` and `isPinVerified && isPinSetup`,
/// including a step-up gate like `/pinGate` reached from an already-unlocked
/// seed-view / change-PIN settings flow): the redirect itself still returns
/// `null` — a true no-op for the match list / back-stack / `extra` — and the
/// actual navigation is an imperative `pushNamed` deferred to
/// `addPostFrameCallback`, so it lands on top of whatever is currently shown
/// (including on top of a step-up gate) without replacing it. Step-up gates
/// complete independently via `pushReplacementNamed` and are not part of the
/// boot/unlock ladder, so a stash while sitting on one would never be consumed
/// — deferred push is the only path that actually resolves a deeplink arriving
/// there. The deferred callback re-checks the same pair
/// `isPinVerified && isPinSetup` at execution time: an independent app-resume
/// re-lock (`AppLifecycleState.resumed` → `PinAuthCubit.onAppResumed()`) can
/// land between decision and push. If no longer unlocked by that pair, the
/// payload is stashed via [stashPendingPaymentDeeplink] instead — same
/// post-unlock replay path as the warm-locked branch.
///
/// Warm resume, genuinely locked or not-yet-set-up (`isInAppRoute` and
/// `!(isPinVerified && isPinSetup)`, e.g. sitting on `/verifyPin` with
/// `isPinVerified == false`, or on `/setupPin` with `isPinSetup == false` even
/// when `isPinVerified` is the vacuous auto-pass): the payload is stashed via
/// [stashPendingPaymentDeeplink] and the redirect returns `null` so the gate
/// stays put — never push `/pay` over the lock screen or the PIN-setup gate.
/// The stash is replayed only once the PIN/unlock gate ladder lands on the
/// dashboard ([applyBootNavAction]'s dashboard / restore / stay branches),
/// never before — same post-unlock replay path as a cold start.
///
/// Cold start (`!isInAppRoute`): the PIN gate and boot ladder have not run yet,
/// and getIt may not be ready — [PinAuthCubit] is not read here. The payload
/// is stashed via [stashPendingPaymentDeeplink] and the redirect hands off to
/// [appLinkColdStartLocation] so the normal PIN/unlock gate ladder runs first;
/// [applyBootNavAction] replays the payload as an imperative `/pay` push only
/// once that ladder lands on the dashboard.
///
/// Non-scheme (in-app) navigation is left untouched (`null`).
//
// @no-integration-test: OS-level custom-scheme delivery and foregrounding can
// only be exercised on a real device, and no integration_test/ harness exists
// in this repo yet. The redirect is covered by widget tests in
// app_link_entry_test.dart.
String? appLinkSchemeRedirect(
  GoRouterState state,
  String currentLocation,
  GoRouter router,
) {
  // https App Links for /invite/{code} (Android) — go_router may receive them
  // as hierarchical https URIs rather than the custom scheme. Chrome intent
  // URLs (`intent://realunit.app/invite/{code}#Intent;scheme=https;…`) are
  // the same App Link once the fragment is ignored.
  if (state.uri.scheme == 'https' ||
      state.uri.scheme == 'http' ||
      state.uri.scheme == 'intent' ||
      state.uri.scheme == 'android-app' ||
      state.uri.scheme == 'ios-app') {
    final httpsCode = extractReferralInviteCode(state.uri);
    if (httpsCode != null) {
      final current = Uri.parse(currentLocation);
      final isInAppRoute = current.scheme.isEmpty && current.path.startsWith('/');
      return _handleReferralInviteRedirect(
        code: httpsCode,
        isInAppRoute: isInAppRoute,
        router: router,
      );
    }
    return null;
  }

  if (state.uri.scheme != appLinkScheme) return null;
  final current = Uri.parse(currentLocation);
  final isInAppRoute = current.scheme.isEmpty && current.path.startsWith('/');

  final inviteCode = extractReferralInviteCode(state.uri);
  if (inviteCode != null) {
    return _handleReferralInviteRedirect(
      code: inviteCode,
      isInAppRoute: isInAppRoute,
      router: router,
    );
  }

  final paymentPayload = extractPaymentDeeplinkPayload(state.uri.toString());
  if (paymentPayload != null) {
    if (isInAppRoute) {
      if (getIt<PinAuthCubit>().state.isPinVerified && getIt<PinAuthCubit>().state.isPinSetup) {
        // Warm resume, unlocked (including a step-up gate like /pinGate reached
        // from an already-unlocked seed-view / change-PIN flow): defer the push
        // to addPostFrameCallback (calling into the router synchronously from
        // inside its own redirect is reentrant/unsafe) and re-check the pair
        // isPinVerified && isPinSetup at execution time — a location snapshot
        // is not proof against an independent AppLifecycleState.resumed re-lock
        // landing between this decision and the deferred frame (TOCTOU). If
        // still unlocked by that pair, push /pay on top of whatever is currently
        // shown, including on top of a step-up gate; that gate's own flow
        // (seed-view / change-PIN) completes independently via
        // pushReplacementNamed and is not part of the boot/unlock ladder, so a
        // stash here would never be consumed — deferred-push is the only path
        // that actually resolves a deeplink arriving while on a step-up gate.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final pinState = getIt<PinAuthCubit>().state;
          if (!(pinState.isPinVerified && pinState.isPinSetup)) {
            stashPendingPaymentDeeplink(paymentPayload);
            return;
          }
          unawaited(router.pushNamed(AppRoutes.pay, extra: paymentPayload));
        });
        return null;
      }
      // Warm resume, locked or not-yet-set-up (!(isPinVerified && isPinSetup) —
      // on /verifyPin with isPinVerified false, or on /setupPin with
      // isPinSetup false even when isPinVerified is the vacuous auto-pass from
      // PinAuthCubit.initialize()). Stash the payload and stay on the gate —
      // never push /pay over the lock screen or the PIN-setup gate.
      // applyBootNavAction replays the stash only after the boot/unlock gate
      // ladder lands on the dashboard (same post-unlock replay path as a
      // cold-start stash).
      stashPendingPaymentDeeplink(paymentPayload);
      return null;
    }
    // Cold start: the PIN gate and boot ladder have not run yet, and getIt may
    // not be ready — do not read PinAuthCubit here. Stash the payload;
    // applyBootNavAction (boot_navigation.dart) replays it as an imperative
    // /pay push strictly after resolveBootNavigation lands on the dashboard —
    // i.e. after the same PIN/unlock gate ladder a normal /pay navigation
    // passes, never before.
    stashPendingPaymentDeeplink(paymentPayload);
    return appLinkColdStartLocation;
  }

  if (!isInAppRoute) return appLinkColdStartLocation;
  final hasPath = state.uri.path.isNotEmpty && state.uri.path != '/';
  return hasPath ? appLinkUrl : null;
}

/// Shared cold/warm handling for invite codes — same security properties as
/// the payment carve-out (never `go` over KYC `extra` / back stack; defer bind).
String? _handleReferralInviteRedirect({
  required String code,
  required bool isInAppRoute,
  required GoRouter router,
}) {
  if (isInAppRoute) {
    if (getIt<PinAuthCubit>().state.isPinVerified && getIt<PinAuthCubit>().state.isPinSetup) {
      // Unlocked: schedule stashes then take-binds once. Do not stash here or
      // a dashboard boot bind can take the same code in parallel.
      scheduleReferralBind(router, code);
      return null;
    }
    unawaited(stashPendingReferralCode(code));
    return null;
  }
  unawaited(stashPendingReferralCode(code));
  return appLinkColdStartLocation;
}

/// go_router exception handler paired with [appLinkSchemeRedirect].
///
/// With an `onException` handler installed, go_router keeps the current route
/// configuration whenever a URL matches no route (go_router `router.dart`:
/// "Avoid updating GoRouterDelegate if onException is provided"). A warm
/// custom-scheme open is exactly that case — [appLinkSchemeRedirect] lets it
/// fall through unmatched — so doing nothing here IS the foregrounding no-op,
/// and it is the only variant that survives imperatively pushed routes.
/// Cold-start scheme opens never reach this handler; the redirect already
/// mapped them to [appLinkColdStartLocation].
//
// @no-integration-test: OS-level custom-scheme delivery and foregrounding can
// only be exercised on a real device, and no integration_test/ harness exists
// in this repo yet. The handler is covered by widget tests in
// app_link_entry_test.dart.
void appLinkOnException(
  BuildContext context,
  GoRouterState state,
  GoRouter router,
) {
  if (state.uri.scheme == appLinkScheme) return;
  // https / intent / android-app / ios-app App Links for /invite and /promo
  // stash in [appLinkSchemeRedirect] then fall through unmatched — same no-op
  // as the custom scheme. Do not assert: those URIs are OS-delivered.
  if (extractReferralInviteCode(state.uri) != null) return;
  // A non-scheme URL that matches no route is a programming error. Installing
  // onException removes go_router's default error screen, so fail loud where
  // tests and debug builds can see it; in release the user stays on the
  // current screen instead of landing on an error page.
  assert(false, 'No route matches ${state.uri}');
}
