import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/setup/error_handling/error_handlers.dart';
import 'package:realunit_wallet/setup/error_handling/realunit_error_view.dart';

void main() {
  // `installErrorHandlers` mutates process-wide statics that the test binding
  // also relies on, so every handler is captured before and restored after each
  // test — otherwise a failure here would leak into unrelated suites.
  late FlutterExceptionHandler? originalFlutterOnError;
  late ErrorWidgetBuilder originalErrorWidgetBuilder;
  late ErrorCallback? originalPlatformOnError;

  setUp(() {
    originalFlutterOnError = FlutterError.onError;
    originalErrorWidgetBuilder = ErrorWidget.builder;
    originalPlatformOnError = PlatformDispatcher.instance.onError;
  });

  tearDown(() {
    FlutterError.onError = originalFlutterOnError;
    ErrorWidget.builder = originalErrorWidgetBuilder;
    PlatformDispatcher.instance.onError = originalPlatformOnError;
  });

  group('installErrorHandlers', () {
    test('installs an async error handler that reports the error onwards', () {
      installErrorHandlers();

      final handler = PlatformDispatcher.instance.onError;
      expect(handler, isNotNull, reason: 'async errors must not go unhandled');

      // The contract that matters: the handler returns false, so the engine's
      // fallback reporting still runs after we log. Returning true would claim
      // the error as handled and suppress that reporting — and since our
      // developer.log is compiled out of release builds, that would leave a
      // release crash reported by nobody at all.
      expect(handler!(Exception('async boom'), StackTrace.current), isFalse);
    });

    test('async handler tolerates an empty stack trace', () {
      installErrorHandlers();

      expect(
        () => PlatformDispatcher.instance.onError!(Exception('boom'), StackTrace.empty),
        returnsNormally,
      );
    });

    test('Flutter error handler delegates to the previously installed handler', () {
      final received = <FlutterErrorDetails>[];
      FlutterError.onError = received.add;

      installErrorHandlers();
      final details = FlutterErrorDetails(exception: Exception('sync boom'));
      FlutterError.onError!(details);

      expect(received, [details], reason: 'the default reporting path must stay intact');
    });

    test('installs the on-brand error widget builder', () {
      installErrorHandlers();

      expect(
        ErrorWidget.builder(FlutterErrorDetails(exception: Exception('boom'))),
        isA<RealUnitErrorView>(),
      );
    });
  });
}
