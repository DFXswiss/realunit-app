part of 'pending_transaction_detail_cubit.dart';

abstract class PendingTransactionDetailState extends Equatable {
  const PendingTransactionDetailState();

  @override
  List<Object?> get props => [];
}

class PendingTransactionDetailInitial extends PendingTransactionDetailState {
  const PendingTransactionDetailInitial();
}

class PendingTransactionDetailLoading extends PendingTransactionDetailState {
  const PendingTransactionDetailLoading();
}

class PendingTransactionDetailSuccess extends PendingTransactionDetailState {
  const PendingTransactionDetailSuccess();
}

class PendingTransactionDetailFailure extends PendingTransactionDetailState {
  const PendingTransactionDetailFailure();
}
