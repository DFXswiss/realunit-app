part of 'buy_confirm_cubit.dart';

abstract class BuyConfirmState extends Equatable {
  const BuyConfirmState();

  @override
  List<Object?> get props => [];
}

class BuyConfirmInitial extends BuyConfirmState {
  const BuyConfirmInitial();
}

class BuyConfirmLoading extends BuyConfirmState {
  const BuyConfirmLoading();
}

class BuyConfirmSuccess extends BuyConfirmState {
  // `reference` is always returned by the confirm endpoint and is the
  // purpose-of-payment fallback. `remittanceInfo` is the API-designated purpose
  // once available (then equal to `reference`); `paymentRequest` is the QR.
  final String reference;
  final String? remittanceInfo;
  final String? paymentRequest;

  const BuyConfirmSuccess({
    required this.reference,
    this.remittanceInfo,
    this.paymentRequest,
  });

  @override
  List<Object?> get props => [reference, remittanceInfo, paymentRequest];
}

class BuyConfirmFailure extends BuyConfirmState {
  /// User-facing text from the API error body. The app does not substitute copy.
  final String message;

  const BuyConfirmFailure(this.message);

  @override
  List<Object?> get props => [message];
}
