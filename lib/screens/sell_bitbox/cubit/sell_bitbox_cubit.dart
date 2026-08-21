import 'dart:async';
import 'dart:typed_data';

import 'package:convert/convert.dart' as convert;
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/packages/hardware_wallet/bitbox_credentials.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_blockchain_api_service.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_faucet_service.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/bitbox_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/payment/sell_exceptions.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/dto/broadcast_transaction_request_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/sell_payment_info.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_sell_payment_info_service.dart';

part 'sell_bitbox_state.dart';

class SellBitboxCubit extends Cubit<SellBitboxState> {
  final SellPaymentInfo _paymentInfo;
  final DfxFaucetService _faucetService;
  final DfxBlockchainApiService _blockchainService;
  final RealUnitSellPaymentInfoService _sellService;
  final AppStore _appStore;

  Timer? _ethPollingTimer;

  SellBitboxCubit({
    required SellPaymentInfo paymentInfo,
    required DfxFaucetService faucetService,
    required DfxBlockchainApiService blockchainService,
    required RealUnitSellPaymentInfoService sellService,
    required AppStore appStore,
  }) : _paymentInfo = paymentInfo,
       _faucetService = faucetService,
       _blockchainService = blockchainService,
       _sellService = sellService,
       _appStore = appStore,
       super(SellBitboxCheckingEth()) {
    scheduleMicrotask(_checkEthBalance);
  }

  Future<void> _checkEthBalance() async {
    try {
      emit(SellBitboxCheckingEth());
      final credentials = _appStore.wallet.currentAccount.primaryAddress;
      if (credentials is BitboxCredentials && !credentials.isConnected) {
        emit(SellBitboxBitboxRequired());
        return;
      }

      if (_paymentInfo.ethBalance >= _paymentInfo.requiredGasEth) {
        emit(SellBitboxEthReady());
      } else {
        await _requestFaucet();
      }
    } catch (e) {
      emit(SellBitboxError(ApiException.userFacingMessage(e)));
    }
  }

  Future<void> retryAfterConnection() => _checkEthBalance();

  Future<void> _requestFaucet() async {
    try {
      emit(SellBitboxRequestingFaucet());
      await _faucetService.requestFaucet();
      emit(SellBitboxWaitingForEth());
      _startEthPolling();
    } catch (e) {
      emit(SellBitboxError(ApiException.userFacingMessage(e)));
    }
  }

  void _startEthPolling() {
    // Cancel any prior timer first — retryAfterConnection can re-enter the
    // faucet/polling branch while a previous timer is still alive.
    _ethPollingTimer?.cancel();
    _ethPollingTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
        final balance = await _blockchainService.getEthBalance(_appStore.primaryAddress);
        if (balance >= _paymentInfo.requiredGasEth) {
          _ethPollingTimer?.cancel();
          emit(SellBitboxEthReady());
        }
      } catch (_) {
        // keep polling on transient errors
      }
    });
  }

  Future<void> proceedToSwap() async {
    try {
      emit(SellBitboxPreparingSwap());
      final transactions = await _sellService.createUnsignedTransactions(_paymentInfo.id);
      emit(SellBitboxAwaitingSwapConfirm(transactions.swap, transactions.deposit));
    } catch (e) {
      emit(SellBitboxError(ApiException.userFacingMessage(e)));
    }
  }

  Future<void> confirmSwap() async {
    final swapState = state;
    if (swapState is! SellBitboxAwaitingSwapConfirm) return;

    final credentials = _appStore.wallet.currentAccount.primaryAddress;
    if (credentials is! BitboxCredentials) {
      emit(SellBitboxError('BitBox wallet not connected'));
      return;
    }

    try {
      emit(SellBitboxSwapping());
      final signedSwap = await _signTransaction(swapState.rawSwapTransaction, credentials);
      emit(SellBitboxAwaitingDepositConfirm(signedSwap, swapState.rawDepositTransaction));
    } on BitboxNotConnectedException {
      emit(SellBitboxBitboxRequired());
    } catch (e) {
      emit(SellBitboxError(ApiException.userFacingMessage(e)));
    }
  }

  Future<void> confirmDeposit() async {
    final depositState = state;
    if (depositState is! SellBitboxAwaitingDepositConfirm) return;

    final credentials = _appStore.wallet.currentAccount.primaryAddress;
    if (credentials is! BitboxCredentials) {
      emit(SellBitboxError('BitBox wallet not connected'));
      return;
    }

    try {
      emit(SellBitboxDepositing());
      final signedDeposit = await _signTransaction(depositState.rawDepositTransaction, credentials);
      await _sellService.broadcastTransaction(
        _paymentInfo.id,
        depositState.signedSwapTransaction,
      );
      await _broadcastDepositAndConfirm(depositState.signedSwapTransaction, signedDeposit);
    } on BitboxNotConnectedException {
      emit(SellBitboxBitboxRequired());
    } catch (e) {
      emit(SellBitboxError(ApiException.userFacingMessage(e)));
    }
  }

  Future<void> retryDeposit() async {
    final retryState = state;
    if (retryState is! SellBitboxDepositRetry) return;

    emit(SellBitboxRetryingDeposit());
    await _broadcastDepositAndConfirm(
      retryState.signedSwapTransaction,
      retryState.signedDepositTransaction,
      knownTxHash: retryState.broadcastTxHash,
    );
  }

  Future<void> _broadcastDepositAndConfirm(
    BroadcastTransactionRequestDto signedSwap,
    BroadcastTransactionRequestDto signedDeposit, {
    String? knownTxHash,
  }) async {
    final String txHash;
    if (knownTxHash != null) {
      txHash = knownTxHash;
    } else {
      try {
        txHash = await _sellService.broadcastTransaction(_paymentInfo.id, signedDeposit);
      } catch (e) {
        // The tx may or may not be on-chain; retry re-sends the same signed bytes — never re-sign.
        emit(SellBitboxDepositRetry(signedSwap, signedDeposit, ApiException.userFacingMessage(e)));
        return;
      }
    }
    try {
      await _sellService.confirmPaymentWithTxHash(_paymentInfo, txHash);
      emit(SellBitboxSuccess());
    } on AlreadyConfirmedException {
      emit(SellBitboxSuccess());
    } catch (e) {
      emit(
        SellBitboxDepositRetry(
          signedSwap,
          signedDeposit,
          ApiException.userFacingMessage(e),
          broadcastTxHash: txHash,
        ),
      );
    }
  }

  Future<BroadcastTransactionRequestDto> _signTransaction(
    String rawTransaction,
    BitboxCredentials credentials,
  ) async {
    final payload = Uint8List.fromList(
      convert.hex.decode(
        rawTransaction.startsWith('0x') ? rawTransaction.substring(2) : rawTransaction,
      ),
    );
    final sig = await credentials.signToSignature(
      payload,
      chainId: _appStore.apiConfig.asset.chainId,
      isEIP1559: true,
    );
    final r = sig.r.toRadixString(16).padLeft(64, '0');
    final s = sig.s.toRadixString(16).padLeft(64, '0');
    return BroadcastTransactionRequestDto(
      unsignedTx: rawTransaction,
      r: '0x$r',
      s: '0x$s',
      v: sig.v,
    );
  }

  @override
  Future<void> close() {
    _ethPollingTimer?.cancel();
    return super.close();
  }
}
