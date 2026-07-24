// @no-integration-test: the QR scanner is camera/MethodChannel-coupled
// (mobile_scanner) and can only be exercised on a real device with a live
// camera. The decode logic it feeds is unit-tested in lnurl_decoder_test.dart
// and the cubit behaviour in pay_scan_cubit_test.dart; the camera preview
// itself is out of scope for widget tests.
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/screens/pay/cubits/pay_scan/pay_scan_cubit.dart';
import 'package:realunit_wallet/screens/pay/pay_quote_page.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/scanner/qr_scanner_view.dart';

class PayScanPage extends StatelessWidget {
  /// A DFX OpenCryptoPay payload already extracted from a payment deeplink
  /// (e.g. `lightning:LNURL1...`), fed into the cubit as if it had been
  /// scanned. Null for the normal live-camera entry (dashboard "Pay" button).
  final String? initialPayload;

  const PayScanPage({super.key, this.initialPayload});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => PayScanCubit(),
      child: PayScanView(initialPayload: initialPayload),
    );
  }
}

class PayScanView extends StatefulWidget {
  final String? initialPayload;

  const PayScanView({super.key, this.initialPayload});

  @override
  State<PayScanView> createState() => _PayScanViewState();
}

class _PayScanViewState extends State<PayScanView> {
  /// True while waiting for the one-shot [initialPayload] decode; drives the
  /// spinner so it can be dismissed after invalid/decoded (unlike the
  /// immutable [PayScanView.initialPayload] widget field).
  bool _awaitingInitialDecode = false;

  @override
  void initState() {
    super.initState();
    final payload = widget.initialPayload;
    if (payload == null) return;
    _awaitingInitialDecode = true;
    // Deferred to after the first frame: BlocConsumer below only subscribes
    // during that first build. Calling onCodeDetected synchronously here
    // (before it subscribes) would emit PayScanDecoded/Invalid before
    // anything is listening — BlocConsumer would just pick it up as its
    // INITIAL state on first build, and its `listener` callback never fires
    // for the initial state, only for later transitions. Deferring one frame
    // guarantees the listener is already subscribed when the emission
    // happens, so the PayQuotePage push / invalid-snackbar actually fires.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<PayScanCubit>().onCodeDetected(payload);
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PayScanCubit, PayScanState>(
      listener: (context, state) {
        if (state is PayScanDecoded) {
          setState(() => _awaitingInitialDecode = false);
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PayQuotePage(paymentLinkId: state.link.id),
            ),
          );
          // Reset so returning to the scanner re-arms detection.
          context.read<PayScanCubit>().reset();
        }
        if (state is PayScanInvalid) {
          setState(() => _awaitingInitialDecode = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(S.of(context).payScanInvalid),
              backgroundColor: RealUnitColors.status.red600,
            ),
          );
          context.read<PayScanCubit>().reset();
        }
      },
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(title: Text(S.of(context).payScanTitle)),
          body: _awaitingInitialDecode
              ? const Center(child: CupertinoActivityIndicator())
              : QrScannerView(
                  onDetect: (raw) => context.read<PayScanCubit>().onCodeDetected(raw),
                  errorBuilder: (context, error) {
                    final message = error.errorCode == MobileScannerErrorCode.permissionDenied
                        ? S.of(context).payScanCameraPermissionDenied
                        : S.of(context).payScanCameraUnavailable;
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          message,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: RealUnitColors.neutral500),
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}
