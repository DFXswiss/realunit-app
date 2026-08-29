import 'dart:developer' as developer show log;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/packages/service/dfx/models/transactions/dto/transactions_dto.dart';
import 'package:realunit_wallet/packages/service/transaction_history_service.dart';

class PendingTransactionsCubit extends Cubit<List<TransactionDto>> {
  PendingTransactionsCubit(this._transactionHistoryService) : super([]) {
    _loadPendingTransactions();
  }

  final TransactionHistoryService _transactionHistoryService;

  Future<void> _loadPendingTransactions() async {
    try {
      final transactions = await _transactionHistoryService.fetchPendingTransactions();
      // The fetch is started in the constructor and not awaited, so the cubit
      // can be closed (page popped) before it resolves. Guard the emit to avoid
      // a StateError after close (issue #657 P3 #16).
      if (isClosed) return;
      emit(transactions);
    } catch (e) {
      developer.log('Failed to load pending transactions: $e', name: '$PendingTransactionsCubit');
      if (isClosed) return;
      emit([]);
    }
  }
}
