import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:realunit_wallet/setup/error_handling/crash_reporting.dart';

void main() {
  group('initCrashReporting', () {
    test('stays a no-op when no DSN is injected', () async {
      var initCalls = 0;

      await initCrashReporting(
        dsn: '',
        init: (_) async => initCalls++,
      );

      expect(initCalls, 0);
    });

    test('starts the reporter exactly once when a DSN is injected', () async {
      var initCalls = 0;

      await initCrashReporting(
        dsn: 'https://key@reporting.invalid/1',
        init: (_) async => initCalls++,
      );

      expect(initCalls, 1);
    });

    test('applies the pinned option set', () async {
      final options = SentryFlutterOptions();
      late FlutterOptionsConfiguration configuration;

      await initCrashReporting(
        dsn: 'https://key@reporting.invalid/1',
        init: (config) async => configuration = config,
      );
      await configuration(options);

      expect(options.dsn, 'https://key@reporting.invalid/1');
      expect(options.environment, crashReportingEnvironment);
      expect(options.sendDefaultPii, isFalse);
      expect(options.attachScreenshot, isFalse);
      expect(options.enableAutoSessionTracking, isFalse);
      expect(options.tracesSampleRate, isNull);
    });

    test('swallows a failing reporter init instead of blocking startup', () async {
      await expectLater(
        initCrashReporting(
          dsn: 'https://key@reporting.invalid/1',
          init: (_) async => throw StateError('native binding unavailable'),
        ),
        completes,
      );
    });
  });

  group('reportNonFatal', () {
    // Same contract as the init above: reporting infrastructure must never be
    // able to take the app down. Without an injected DSN the reporter never
    // started, so the call has to fall through to the log line and return.
    test('is inert and non-throwing when the reporter never started', () {
      expect(crashReportingDsn, isEmpty);
      expect(() => reportNonFatal(StateError('nothing is listening')), returnsNormally);
    });
  });
}
