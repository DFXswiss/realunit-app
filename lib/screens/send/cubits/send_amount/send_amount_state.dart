part of 'send_amount_cubit.dart';

/// Validity of the entered amount. Each value maps to a localized hint/error in
/// the view — the cubit carries the status, not the copy.
enum SendAmountStatus {
  /// Nothing entered yet.
  empty,

  /// Not a whole number >= 1.
  invalid,

  /// A valid whole number, but more than the available REALU balance.
  insufficientBalance,

  /// A valid, sendable amount.
  valid,
}

class SendAmountState extends Equatable {
  final String text;

  /// The parsed amount, or null when [text] is empty / not an integer.
  final int? amount;
  final SendAmountStatus status;

  const SendAmountState({
    this.text = '',
    this.amount,
    this.status = SendAmountStatus.empty,
  });

  /// The confirm button binds to this — only a fully valid amount may advance.
  bool get isValid => status == SendAmountStatus.valid && amount != null;

  @override
  List<Object?> get props => [text, amount, status];
}
