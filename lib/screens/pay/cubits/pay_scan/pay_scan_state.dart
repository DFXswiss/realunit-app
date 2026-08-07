part of 'pay_scan_cubit.dart';

sealed class PayScanState extends Equatable {
  const PayScanState();

  @override
  List<Object?> get props => [];
}

class PayScanScanning extends PayScanState {
  const PayScanScanning();
}

class PayScanInvalid extends PayScanState {
  final String reason;

  const PayScanInvalid(this.reason);

  @override
  List<Object?> get props => [reason];
}

class PayScanDecoded extends PayScanState {
  final DecodedPaymentLink link;

  const PayScanDecoded(this.link);

  @override
  List<Object?> get props => [link.id, link.lnurlpUrl];
}
