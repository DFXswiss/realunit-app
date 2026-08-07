import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/payment/pay_exceptions.dart';
import 'package:realunit_wallet/packages/service/dfx/lnurl_decoder.dart';

part 'pay_scan_state.dart';

/// Decodes a scanned OCP QR into a DFX payment-link id + lnurlp URL. Pure
/// decode — no network. The view advances to the quote step on
/// [PayScanDecoded]; a malformed code keeps the scanner open with an error.
class PayScanCubit extends Cubit<PayScanState> {
  PayScanCubit() : super(const PayScanScanning());

  /// Called once per detected barcode. Guards against re-entry after a
  /// successful decode so a continuously-detecting scanner does not re-emit.
  void onCodeDetected(String raw) {
    if (state is PayScanDecoded) return;
    try {
      final decoded = LnurlDecoder.decode(raw);
      emit(PayScanDecoded(decoded));
    } on InvalidPaymentLinkException catch (e) {
      emit(PayScanInvalid(e.reason));
    }
  }

  /// Dismiss an error and resume scanning.
  void reset() => emit(const PayScanScanning());
}
