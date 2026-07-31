import 'dart:developer' as developer;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:realunit_wallet/setup/error_handling/realunit_error_view.dart';

/// Wires up the three process-wide error surfaces. Called once from `main`
/// before any other bootstrap step, so errors thrown during setup are covered.
///
/// - [FlutterError.onError] catches errors raised inside a Flutter callback
///   (build, layout, paint). It logs and then delegates to the previously
///   installed handler, which keeps the framework's own reporting intact.
/// - [ErrorWidget.builder] replaces the bare grey error box with an on-brand
///   surface; see [RealUnitErrorView].
/// - [PlatformDispatcher.onError] catches everything with no Flutter callback
///   on the stack — unhandled `Future`, `Stream` and `Timer` errors in the root
///   isolate — which the two handlers above never see.
///
/// Both handlers log and then hand the error on rather than absorbing it, so
/// nothing that reported an error before reports less of one now.
///
/// Scope, deliberately narrow: [developer.log] writes to the VM service stream,
/// so these calls surface in the DevTools Logging view under the `WalletApp`
/// tag in debug and profile builds only — the VM service is absent from a
/// release build, where the call is compiled out. Returning `false` from
/// [PlatformDispatcher.onError] is what carries release builds: it keeps the
/// engine's own reporting running instead of suppressing it (returning `true`
/// would claim the error as handled while our log is a no-op, i.e. total
/// silence). So this makes async errors *reachable where a developer is already
/// attached*; it adds no release-mode visibility on its own. Getting evidence
/// off a customer's device needs a crash reporter or a persisted log sink —
/// this handler body is the hook such a sink plugs into.
///
/// @no-integration-test: the engine-side fallback reporting that runs after
/// [PlatformDispatcher.onError] returns false is embedder behaviour and is not
/// observable from a Dart test; the handler contract itself is unit-tested.
void installErrorHandlers() {
  final defaultOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    developer.log(
      'uncaught Flutter error: ${details.exceptionAsString()}',
      name: 'WalletApp',
      error: details.exception,
      stackTrace: details.stack,
    );
    defaultOnError?.call(details);
  };
  ErrorWidget.builder = (details) => RealUnitErrorView(details: details);
  PlatformDispatcher.instance.onError = (error, stack) {
    developer.log(
      'uncaught async error: $error',
      name: 'WalletApp',
      error: error,
      stackTrace: stack,
    );
    return false;
  };
}
