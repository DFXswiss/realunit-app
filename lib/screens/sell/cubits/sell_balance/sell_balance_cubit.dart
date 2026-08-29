import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/models/balance.dart';
import 'package:realunit_wallet/packages/repository/balance_repository.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';

class SellBalanceCubit extends Cubit<Balance> {
  SellBalanceCubit(
    BalanceRepository repository,
    AppStore appStore,
  ) : _repository = repository,
      super(
        Balance(
          chainId: appStore.apiConfig.asset.chainId,
          contractAddress: appStore.apiConfig.asset.address,
          walletAddress: appStore.primaryAddress,
          balance: BigInt.zero,
          asset: appStore.apiConfig.asset,
        ),
      ) {
    // Register an onError handler so a balance-stream error is logged instead
    // of escaping as an unhandled async error that silently stops the sell
    // balance (issue #657 P4 S6). cancelOnError defaults to false, so the
    // subscription stays alive and later balances still update.
    _subscription = _repository.watchBalance(state).listen(
      emit,
      onError: (Object error, StackTrace stackTrace) {
        developer.log(
          'sell balance stream error',
          name: '$SellBalanceCubit',
          error: error,
          stackTrace: stackTrace,
        );
      },
    );
  }

  final BalanceRepository _repository;
  StreamSubscription<Balance>? _subscription;

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
