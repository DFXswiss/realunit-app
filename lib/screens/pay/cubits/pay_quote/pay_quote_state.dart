part of 'pay_quote_cubit.dart';

sealed class PayQuoteState extends Equatable {
  const PayQuoteState();

  @override
  List<Object?> get props => [];
}

class PayQuoteLoading extends PayQuoteState {
  const PayQuoteLoading();
}

class PayQuoteReady extends PayQuoteState {
  final String paymentLinkId;
  final String quoteId;
  final String fiatAsset;
  final double fiatAmount;
  final double zchfAmount;
  final String? merchantName;
  final String? merchantCity;
  final double? realuAmount;
  final double? realuEstimatedZchf;
  final double? realuFeesTotal;

  const PayQuoteReady({
    required this.paymentLinkId,
    required this.quoteId,
    required this.fiatAsset,
    required this.fiatAmount,
    required this.zchfAmount,
    this.merchantName,
    this.merchantCity,
    this.realuAmount,
    this.realuEstimatedZchf,
    this.realuFeesTotal,
  });

  @override
  List<Object?> get props => [
    paymentLinkId,
    quoteId,
    fiatAsset,
    fiatAmount,
    zchfAmount,
    merchantName,
    merchantCity,
    realuAmount,
    realuEstimatedZchf,
    realuFeesTotal,
  ];
}

/// The quote attached to the scanned link has expired — the user must re-scan.
class PayQuoteExpired extends PayQuoteState {
  const PayQuoteExpired();
}

/// The payment link offers no Ethereum/ZCHF transfer method.
class PayQuoteUnavailable extends PayQuoteState {
  const PayQuoteUnavailable();
}

class PayQuoteError extends PayQuoteState {
  final String message;

  const PayQuoteError(this.message);

  @override
  List<Object?> get props => [message];
}
