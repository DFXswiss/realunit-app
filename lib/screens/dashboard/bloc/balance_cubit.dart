import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/models/asset.dart';
import 'package:realunit_wallet/models/balance.dart';
import 'package:realunit_wallet/packages/repository/balance_repository.dart';

class BalanceCubit extends Cubit<Balance> {
  BalanceCubit(
    this._repository, {
    required this.asset,
    required String walletAddress,
  }) : super(
         Balance(
           chainId: asset.chainId,
           contractAddress: asset.address,
           walletAddress: walletAddress,
           balance: BigInt.zero,
           asset: asset,
         ),
       ) {
    // Register an onError handler so a balance-stream error is logged instead
    // of escaping as an unhandled async error that silently freezes the
    // balance (issue #657 P3 #14). cancelOnError defaults to false, so the
    // subscription stays alive and later balances still update the UI.
    _subscription = _repository.watchBalance(state).listen(
      emit,
      onError: (Object error, StackTrace stackTrace) {
        developer.log(
          'balance stream error',
          name: '$BalanceCubit',
          error: error,
          stackTrace: stackTrace,
        );
      },
    );
  }

  final BalanceRepository _repository;
  final Asset asset;
  StreamSubscription<Balance>? _subscription;

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
