import 'dart:async';
import 'dart:developer' as developer;

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
/// otherwise. Best-effort by design: a malformed DSN or a failing native
/// binding is logged and swallowed — reporting infrastructure must never keep
/// the wallet from starting.
///
/// Must run AFTER [installErrorHandlers]: that installer overwrites
/// `PlatformDispatcher.onError` without chaining, so in the reverse order the
/// SDK's async-error hook would be silently dropped. The SDK itself chains
/// both handlers it wraps — `FlutterError.onError` captures first and then
/// delegates to the handler installed before it; `PlatformDispatcher.onError`
/// delegates first and then captures.
///
/// @no-integration-test: the native SDK only starts in a build that injects a
/// DSN, which no test build does; the DSN gate, the option pinning and the
/// swallow-on-failure contract are covered by unit tests via the injectable
/// [init].
Future<void> initCrashReporting({
  String dsn = crashReportingDsn,
  CrashReporterInit init = SentryFlutter.init,
}) async {
  if (dsn.isEmpty) return;
  try {
    await init((options) => configureCrashReporting(options, dsn: dsn));
  } catch (error, stackTrace) {
    developer.log(
      'crash reporting init failed: $error',
      name: 'WalletApp',
      error: error,
      stackTrace: stackTrace,
    );
  }
}

/// Sink for a condition the app caught and handled but that should not have
/// happened. Matches [reportNonFatal] so a caller can hold the seam as a field
/// and a test can record instead of report.
typedef NonFatalReporter = void Function(Object error);

/// Records [error] as a non-fatal event: a `developer.log` line for an attached
/// developer plus, when the crash reporter is running, an error event carrying
/// the same object.
///
/// Same channel and same pinned option surface as the uncaught-error path — no
/// PII, no attachments, no breadcrumb widening — so callers must pass an error
/// object that describes the condition in its own `toString()` and nothing
/// about the user.
///
/// Gated on the same [crashReportingDsn] that decides whether [initCrashReporting]
/// starts the SDK at all: without an injected DSN — every local and test build —
/// nothing was ever started, and the report is a pure log line.
void reportNonFatal(Object error) {
  developer.log('non-fatal: $error', name: 'WalletApp', error: error);
  if (crashReportingDsn.isEmpty) return;
  unawaited(Sentry.captureException(error));
}

/// Applies the pinned option set. The guarantee is exactly this list — an
/// upstream default flip outside it is not caught here: no PII, no
/// screenshots, no performance tracing, no session telemetry. Native crash
/// handling and ANR detection stay on their SDK defaults deliberately; they
/// produce precisely the error events this reporter exists for.
/// (View-hierarchy attachment also stays off by SDK default; its option is
/// experimental and deliberately not referenced here.)
@visibleForTesting
void configureCrashReporting(SentryFlutterOptions options, {required String dsn}) {
  options
    ..dsn = dsn
    ..environment = crashReportingEnvironment
    ..sendDefaultPii = false
    ..attachScreenshot = false
    ..enableAutoSessionTracking = false
    ..tracesSampleRate = null;
}
