import 'dart:developer' as developer show log;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/packages/service/dfx/models/transactions/dto/transactions_dto.dart';
import 'package:realunit_wallet/packages/service/transaction_history_service.dart';

class PendingTransactionsCubit extends Cubit<List<TransactionDto>> {
  PendingTransactionsCubit(this._transactionHistoryService) : super([]) {
    _loadPendingTransactions();
  }

  final TransactionHistoryService _transactionHistoryService;
  int _loadGeneration = 0;

  Future<void> reload() => _loadPendingTransactions();

  /// Drops a quote from the local list after a successful cancel on the
  /// detail page, so a failed reload cannot bring the cancelled row back.
  void drop(String idOrUid) {
    if (idOrUid.isEmpty) return;
    emit(state.where((t) => (t.id?.toString() ?? t.uid) != idOrUid).toList());
  }

  Future<void> _loadPendingTransactions() async {
    final generation = ++_loadGeneration;
    try {
      final transactions = await _transactionHistoryService.fetchPendingTransactions();
      if (isClosed || generation != _loadGeneration) return;
      emit(transactions);
    } catch (e) {
      developer.log('Failed to load pending transactions: $e', name: '$PendingTransactionsCubit');
      if (isClosed || generation != _loadGeneration) return;
      if (state.isEmpty) emit([]);
    }
  }
}
