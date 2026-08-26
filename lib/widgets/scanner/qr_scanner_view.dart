// @no-integration-test: the QR scanner is camera/MethodChannel-coupled
// (mobile_scanner) and can only be exercised on a real device with a live
// camera. This widget is the shared camera-preview wrapper reused by the OCP
// pay flow (LNURL decode) and the wallet-to-wallet send flow (EVM address
// decode); the per-flow decode logic it feeds is unit-tested in the respective
// cubit tests.
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:realunit_wallet/styles/colors.dart';

/// Compact icon-only error placeholder used when [QrScannerView.errorBuilder]
/// is null. Replaces mobile_scanner 7.x's own (taller, textScale-scaling)
/// default to avoid overflow in bounded layouts like send_recipient_page.dart's
/// Expanded.
Widget _defaultErrorBuilder(BuildContext context, MobileScannerException error) {
  return ColoredBox(
    color: RealUnitColors.basic.black,
    child: Center(
      child: Icon(
        Icons.error_outline,
        size: 48,
        color: RealUnitColors.status.red600,
      ),
    ),
  );
}

/// Thin wrapper around [MobileScanner] that surfaces the first raw barcode
/// value of each capture via [onDetect]. Keeping the camera/MethodChannel
/// wiring in one widget lets every flow reuse the scanner without duplicating
/// it — each flow decides what the scanned payload means in its own cubit.
///
/// **Every camera frame is forwarded** while a barcode is in view — this is
/// not a one-shot capture. Consumers that [Navigator.push] from a scan result
/// **must** use [pushThenRearm] so the scanner cubit is re-armed only after
/// that route pops; resetting in the same turn as the push drops the cubit's
/// "already decoded" guard and double-pushes the next page.
class QrScannerView extends StatelessWidget {
  /// Invoked with the raw string value of the first detected barcode in a
  /// capture. Null raw values are filtered out before this is called. Called
  /// on every frame while a barcode remains visible — not once.
  final ValueChanged<String> onDetect;

  /// Optional error UI builder forwarded to [MobileScanner.errorBuilder].
  /// When null, this compact icon-only placeholder is used instead of
  /// mobile_scanner 7.x's own (taller, textScale-scaling) default, to avoid
  /// overflow in bounded layouts like send_recipient_page.dart's Expanded.
  final Widget Function(BuildContext, MobileScannerException)? errorBuilder;

  const QrScannerView({
    super.key,
    required this.onDetect,
    this.errorBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return MobileScanner(
      onDetect: (capture) {
        final raw = capture.barcodes.firstOrNull?.rawValue;
        if (raw != null) onDetect(raw);
      },
      errorBuilder: errorBuilder ?? _defaultErrorBuilder,
    );
  }
}
