import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// The crash-reporting DSN, injected at build time via
/// `--dart-define=SENTRY_DSN=...`. Local and CI builds that do not inject a
/// DSN get the empty default, which keeps crash reporting fully disabled —
/// no SDK start, no network traffic. The DSN points at the company-operated
/// crash-reporting service; see CONTRIBUTING § API Access for why this is the
/// one sanctioned non-API endpoint.
const crashReportingDsn = String.fromEnvironment('SENTRY_DSN');

/// Reported as the Sentry environment. Only release builds carrying a DSN
/// report at all, so the default names the production environment; testnet
/// builds can override via `--dart-define=SENTRY_ENVIRONMENT=...`.
const crashReportingEnvironment = String.fromEnvironment(
  'SENTRY_ENVIRONMENT',
  defaultValue: 'production',
);

/// Matches the shape of [SentryFlutter.init] so tests can swap in a recording
/// fake without touching the native SDK.
typedef CrashReporterInit = Future<void> Function(FlutterOptionsConfiguration configuration);

/// Starts crash reporting when a DSN was injected at build time; a no-op
/// otherwise.
///
/// Must run AFTER [installErrorHandlers]: the SDK chains the then-current
/// [FlutterError.onError] and [PlatformDispatcher.onError] (capture first,
/// then delegate), while [installErrorHandlers] overwrites
/// [PlatformDispatcher.onError] without chaining — in the reverse order the
/// SDK's async-error hook would be silently dropped.
///
/// @no-integration-test: the native SDK only starts in a build that injects a
/// DSN, which no test build does; the DSN gate and the option hardening are
/// covered by unit tests via the injectable [init].
Future<void> initCrashReporting({
  String dsn = crashReportingDsn,
  CrashReporterInit init = SentryFlutter.init,
}) async {
  if (dsn.isEmpty) return;
  await init((options) => configureCrashReporting(options, dsn: dsn));
}

/// Applies the hardened option set. Pinned explicitly (even where it matches
/// today's SDK defaults) so an upstream default flip can never widen what a
/// wallet build sends: no PII, no screenshots, no performance tracing — error
/// events only. (View-hierarchy attachment stays off by SDK default; its
/// option is experimental and deliberately not referenced here.)
@visibleForTesting
void configureCrashReporting(SentryFlutterOptions options, {required String dsn}) {
  options
    ..dsn = dsn
    ..environment = crashReportingEnvironment
    ..sendDefaultPii = false
    ..attachScreenshot = false
    ..tracesSampleRate = null;
}
