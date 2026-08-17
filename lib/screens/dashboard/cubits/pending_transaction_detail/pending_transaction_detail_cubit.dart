import 'dart:developer' as developer;

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/packages/service/dfx/models/transactions/dto/transactions_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_buy_payment_info_service.dart';

part 'pending_transaction_detail_state.dart';

class PendingTransactionDetailCubit extends Cubit<PendingTransactionDetailState> {
  final RealUnitBuyPaymentInfoService _buyPaymentInfoService;

  PendingTransactionDetailCubit(RealUnitBuyPaymentInfoService buyPaymentInfoService)
    : _buyPaymentInfoService = buyPaymentInfoService,
      super(const PendingTransactionDetailInitial());

  /// Cancels a binding buy quote that is still waiting for payment.
  ///
  /// No-ops when the transaction is not a buy in `waitingForPayment`, or when
  /// both `id` and `uid` are empty. Uses `id ?? uid` as the deactivate path id.
  Future<void> deactivate(TransactionDto transaction) async {
    if (transaction.type != TransactionType.buy ||
        transaction.state != TransactionState.waitingForPayment) {
      return;
    }
    final idOrUid = transaction.id?.toString() ?? transaction.uid;
    if (idOrUid == null || idOrUid.isEmpty) return;
    if (state is PendingTransactionDetailLoading) return;

    try {
      emit(const PendingTransactionDetailLoading());
      await _buyPaymentInfoService.deactivateQuote(idOrUid);
      if (isClosed) return;
      emit(const PendingTransactionDetailSuccess());
    } catch (e) {
      developer.log(e.toString());
      if (isClosed) return;
      emit(const PendingTransactionDetailFailure());
    }
  }
}
