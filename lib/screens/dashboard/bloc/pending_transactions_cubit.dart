import 'dart:developer' as developer show log;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/packages/service/dfx/models/transactions/dto/transactions_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_buy_payment_info_service.dart';
import 'package:realunit_wallet/packages/service/transaction_history_service.dart';

class PendingTransactionsCubit extends Cubit<List<TransactionDto>> {
  PendingTransactionsCubit(
    this._transactionHistoryService,
    this._buyPaymentInfoService,
  ) : super([]) {
    _loadPendingTransactions();
  }

  final TransactionHistoryService _transactionHistoryService;
  final RealUnitBuyPaymentInfoService _buyPaymentInfoService;

  Future<void> reload() => _loadPendingTransactions();

  Future<void> deactivate(TransactionDto transaction) async {
    if (transaction.type != TransactionType.buy) return;
    final idOrUid = transaction.id?.toString() ?? transaction.uid;
    if (idOrUid == null || idOrUid.isEmpty) return;
    await _buyPaymentInfoService.deactivateQuote(idOrUid);
    await reload();
  }

  Future<void> _loadPendingTransactions() async {
    try {
      final transactions = await _transactionHistoryService.fetchPendingTransactions();
      emit(transactions);
    } catch (e) {
      developer.log('Failed to load pending transactions: $e', name: '$PendingTransactionsCubit');
      if (state.isEmpty) emit([]);
    }
  }
}
