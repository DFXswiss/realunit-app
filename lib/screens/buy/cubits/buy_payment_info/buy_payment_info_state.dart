part of 'buy_payment_info_cubit.dart';

abstract class BuyPaymentInfoState extends Equatable {
  const BuyPaymentInfoState();

  @override
  List<Object?> get props => [];
}

class BuyPaymentInfoInitial extends BuyPaymentInfoState {
  const BuyPaymentInfoInitial();
}

class BuyPaymentInfoLoading extends BuyPaymentInfoState {
  const BuyPaymentInfoLoading();
}

class BuyPaymentInfoSuccess extends BuyPaymentInfoState {
  final BuyPaymentInfo buyPaymentInfo;

  const BuyPaymentInfoSuccess(this.buyPaymentInfo);

  @override
  List<Object?> get props => [buyPaymentInfo];
}

class BuyPaymentInfoFailure extends BuyPaymentInfoState {
  final PaymentInfoError error;
  final int? requiredLevel;
  final String? context;

  /// User-facing API error text when this failure came from an API body.
  /// Empty for local hardware gates (BitBox) and for quote-code routing
  /// that has its own structured UI (KYC / registration / min / max amount).
  final String message;

  const BuyPaymentInfoFailure(
    this.error, {
    this.requiredLevel,
    this.context,
    this.message = '',
  });

  @override
  List<Object?> get props => [error, requiredLevel, context, message];
}

class BuyPaymentInfoMinAmountNotMetFailure extends BuyPaymentInfoFailure {
  final double minAmount;

  const BuyPaymentInfoMinAmountNotMetFailure(super.error, {required this.minAmount});

  @override
  List<Object?> get props => [error, minAmount];
}

class BuyPaymentInfoMaxAmountExceededFailure extends BuyPaymentInfoFailure {
  final double maxAmount;

  const BuyPaymentInfoMaxAmountExceededFailure(super.error, {required this.maxAmount});

  @override
  List<Object?> get props => [error, maxAmount];
}
