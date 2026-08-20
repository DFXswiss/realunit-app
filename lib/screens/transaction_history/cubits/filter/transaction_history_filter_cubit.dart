import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/models/asset.dart';
import 'package:realunit_wallet/models/transaction.dart';
import 'package:realunit_wallet/packages/repository/transaction_repository.dart';

part 'transaction_history_filter_state.dart';

class TransactionHistoryFilterCubit extends Cubit<TransactionHistoryFilterState> {
  TransactionHistoryFilterCubit(
    this._repository, {
    required Asset asset,
    required String walletAddress,
    int? limit,
  }) : super(TransactionHistoryFilterState()) {
    _subscription = _repository.watchTransactionsOfAssets([asset], walletAddress).listen(
      _onTransactionsUpdated,
    );
  }

  final TransactionRepository _repository;
  StreamSubscription<List<Transaction>>? _subscription;

  void _onTransactionsUpdated(List<Transaction> transactions) {
    emit(
      state.copyWith(
        all: transactions,
        filtered: _applyFilter(
          transactions,
          startDate: state.startDate,
          endDate: state.endDate,
        ),
      ),
    );
  }

  void changeFilter({DateTime? startDate, DateTime? endDate}) {
    // Merge the partial picker arg with the state bound so the untouched bound isn't dropped.
    final effectiveStartDate = startDate ?? state.startDate;
    final effectiveEndDate = endDate ?? state.endDate;
    emit(
      state.copyWith(
        startDate: effectiveStartDate,
        endDate: effectiveEndDate,
        filtered: _applyFilter(
          state.all,
          startDate: effectiveStartDate,
          endDate: effectiveEndDate,
        ),
      ),
    );
  }

  List<Transaction> _applyFilter(
    List<Transaction> transactions, {
    DateTime? startDate,
    DateTime? endDate,
  }) {
    // The picker hands over the selected day at local midnight, so an inclusive end bound
    // has to cover that entire day — compare against the next day's midnight exclusively.
    final endBound = endDate == null ? null : _startOfNextLocalDay(endDate);

    return transactions.where((transaction) {
      final transactionDate = transaction.timestamp;
      final afterStart = startDate == null || !transactionDate.isBefore(startDate);
      final beforeEnd = endBound == null || transactionDate.isBefore(endBound);
      return afterStart && beforeEnd;
    }).toList();
  }

  DateTime _startOfNextLocalDay(DateTime date) {
    final local = date.toLocal();
    return DateTime(local.year, local.month, local.day + 1);
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
