import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _noScreenshotChannel = MethodChannel('com.flutterplaza.no_screenshot_methods');

/// Stub the `no_screenshot` plugin's method channel so calls to
/// `screenshotOff` / `screenshotOn` / `screenshotStream` do not throw
/// `MissingPluginException` in headless golden tests.
///
/// Call from `setUpAll`. Pass [calls] to record the invoked method names
/// (for tests asserting the off/on contract).
void stubNoScreenshotChannel({List<String>? calls}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    _noScreenshotChannel,
    (call) async {
      calls?.add(call.method);
      return true;
    },
  );
}

/// Remove the stub installed by [stubNoScreenshotChannel].
void unstubNoScreenshotChannel() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
    _noScreenshotChannel,
    null,
  );
}

/// Stub the `mobile_scanner` plugin's method + event channels so the camera
/// preview renders a deterministic state in headless widget/golden tests.
///
/// The QR scanner is camera/MethodChannel-coupled — the live preview has no
/// headless representation and `MobileScanner.initState` fires
/// `controller.start()` against the platform channel. This stub answers the
/// permission handshake (`state` → undetermined, `request` → not granted) so
/// `MobileScannerController.start()` settles into its permission-denied error
/// state. The widget then paints its default error placeholder (a black
/// `ColoredBox` with a centered error icon) instead of throwing
/// `MissingPluginException` — a stable, deterministic preview-placeholder
/// state that mirrors the `@no-integration-test` note on `pay_scan_page.dart`
/// (the live camera is exercised only on a real device).
///
/// Call from `setUpAll`.
void stubMobileScannerChannel() {
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('dev.steenbakker.mobile_scanner/scanner/method'),
    (call) async {
      switch (call.method) {
        // Camera authorization is undetermined …
        case 'state':
          return 0;
        // … and the follow-up request is not granted, so start() settles into
        // the permission-denied placeholder without touching a real camera.
        case 'request':
          return false;
        default:
          return null;
      }
    },
  );
  // PayScanView wires an onDetect callback, so MobileScanner subscribes to the
  // controller's barcode stream (the event channel) in initState. Install a
  // no-op stream handler that never emits, so the `listen` does not throw
  // MissingPluginException and no synthetic barcode ever fires.
  messenger.setMockStreamHandler(
    const EventChannel('dev.steenbakker.mobile_scanner/scanner/event'),
    MockStreamHandler.inline(onListen: (arguments, sink) {}),
  );
  // mobile_scanner 7.x additionally subscribes to a device-orientation event
  // stream; stub it as a no-op so `listen`/`cancel` don't throw MissingPluginException.
  messenger.setMockStreamHandler(
    const EventChannel('dev.steenbakker.mobile_scanner/scanner/deviceOrientation'),
    MockStreamHandler.inline(onListen: (arguments, sink) {}),
  );
}
