import 'dart:async';
import 'dart:typed_data';

import 'package:convert/convert.dart' as convert;
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:web3dart/crypto.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_blockchain_api_service.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_faucet_service.dart';
import 'package:realunit_wallet/packages/service/dfx/eip1559_unsigned_tx_decoder.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/bitbox_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/payment/pay_exceptions.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/pay/dto/lnurlp_payment_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/pay/dto/real_unit_ocp_pay_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/pay/dto/real_unit_ocp_pay_submit_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/pay/dto/real_unit_ocp_pay_unsigned_transaction_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/pay/dto/real_unit_swap_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/pay/swap_payment_info.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/dto/broadcast_transaction_request_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_pay_service.dart';
import 'package:realunit_wallet/packages/service/wallet_service.dart';
import 'package:realunit_wallet/packages/utils/plain_decimal.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';

part 'pay_process_state.dart';

/// Orchestrates the on-chain half of the OCP pay flow after the user confirms a
/// quote: check ETH gas → swap REALU→ZCHF (sign + broadcast) → re-fetch the OCP
/// quote (fresh quoteId, guards expiry between swap and pay) → pay (sign +
/// submit) → poll status until terminal.
///
/// Signing uses the unified raw-payload path (`signToSignature` → r/s/v) for
/// BOTH software and BitBox wallets — the backend returns the unsigned txs, the
/// app signs them the same way regardless of wallet mode. The flow is NOT
/// branched on `walletType`; only the genuine capability gap (a debug wallet
/// that cannot sign) is gated, surfacing [PaySignaturePending] →
/// [PaySignatureUnsupportedException].
class PayProcessCubit extends Cubit<PayProcessState> {
  final RealUnitPayService _payService;
  final DfxFaucetService _faucetService;
  final DfxBlockchainApiService _blockchainService;
  final WalletService _walletService;
  final AppStore _appStore;

  final String _paymentLinkId;
  final double _zchfNeeded;

  SwapPaymentInfo? _swap;

  /// Set once the REALU→ZCHF swap has been broadcast successfully. From this
  /// point the user holds ZCHF and recovery must NEVER re-swap — the pay leg is
  /// retried on its own via [retryPay].
  bool _swapCompleted = false;

  /// Guards overlapping ETH-poll ticks from each calling [_executeSwap]. Set
  /// synchronously before the first await in a tick; released in `finally` on
  /// every path out of a tick (success, max-attempts, isClosed, transient
  /// error) so a later polling cycle never starts with a stuck `true`.
  bool _swapInFlight = false;

  /// Test-only visibility into the ETH-poll re-entrancy guard — lets tests prove it is released on
  /// every abort/end path of a poll tick (see [_startEthPolling]) instead of only inferring it
  /// indirectly from timer behavior.
  @visibleForTesting
  bool get debugSwapInFlight => _swapInFlight;

  /// ZCHF acquired by the (completed) swap — the backend `estimatedAmount` of
  /// the swap quote. Used to detect when a freshly re-fetched settlement amount
  /// can no longer be covered by what we actually hold.
  double _acquiredZchf = 0;

  Timer? _ethPollingTimer;
  Timer? _statusPollingTimer;

  /// 24 attempts * 5s interval ≈ 2 minutes, mirrors the status-poll budget.
  /// Bounds ETH-balance polling so a faucet that never funds (or a hung
  /// balance RPC) cannot leave [_swapInFlight] wedged indefinitely.
  static const _ethPollMaxAttempts = 24;

  /// Per-request cap on [DfxBlockchainApiService.getEthBalance] so a hung HTTP
  /// layer always resolves (as [TimeoutException], treated as transient by the
  /// catch path) instead of blocking every subsequent poll tick.
  static const _ethPollTimeout = Duration(seconds: 10);

  int _ethPollAttempts = 0;

  /// 40 attempts * 3s interval = 2 minutes. Bounds the poll so a status that
  /// never turns terminal (or a backend that keeps erroring) cannot poll
  /// forever; beyond this the swap already left the user holding ZCHF, so it
  /// surfaces the existing pay-only retry state rather than a new failure mode.
  static const _statusPollMaxAttempts = 40;

  /// Bumped every [_startStatusPolling] call. A tick captures the generation
  /// active when it starts; if that generation is stale by the time its
  /// (possibly slow) request returns, the tick is a leftover from an earlier
  /// polling cycle and must not act on the timer/state of a newer cycle.
  int _statusPollGeneration = 0;
  int _statusPollAttempts = 0;
  bool _statusPollInFlight = false;

  /// Headroom over the OCP ZCHF amount when sizing the swap target. The swap is
  /// quoted/broadcast against the ORIGINAL OCP quote, but the pay step settles
  /// the EXACT amount of a FRESHLY re-fetched quote; in between, the OCP price
  /// (CHF→ZCHF) and the swap rate can both move. A 1% buffer left no margin for
  /// the common case (a few minutes of drift + the OCP/swap fees), so any
  /// adverse move stranded the user in ZCHF that could not cover settlement.
  /// 3% is a pragmatic headroom that absorbs ordinary drift while keeping the
  /// over-swap small (leftover ZCHF simply stays in the wallet); a larger move
  /// is caught explicitly and surfaced as a retryable
  /// [PayRetryReason.insufficientZchf] rather than a server-side failure.
  static const _slippageBuffer = 1.03;

  /// Local cap on the pay-leg tx's gasLimit. An ERC20 `transfer` costs roughly
  /// 60–80k gas; 200k gives >2× headroom so a legitimate tx is never rejected
  /// while still bounding a compromised backend that would set an absurd limit.
  static const _maxGasLimit = 200000;

  /// Local cap on the pay-leg tx's declared max total fee
  /// (`maxFeePerGas * gasLimit`), in wei (0.05 ETH). Combined with
  /// [_maxGasLimit] this still tolerates fee spikes up to ~250 gwei/gas, well
  /// above ordinary mainnet congestion, while ensuring a compromised backend
  /// can never make the app commit to burning more than 0.05 ETH in fees.
  /// `static final` (not `const`): BigInt is not const-constructible in Dart.
  static final _maxTotalFeeWei = BigInt.parse('50000000000000000');

  static const _ethPollInterval = Duration(seconds: 5);
  static const _statusPollInterval = Duration(seconds: 3);

  PayProcessCubit({
    required RealUnitPayService payService,
    required DfxFaucetService faucetService,
    required DfxBlockchainApiService blockchainService,
    required WalletService walletService,
    required AppStore appStore,
    required String paymentLinkId,
    required double zchfNeeded,
  }) : _payService = payService,
       _faucetService = faucetService,
       _blockchainService = blockchainService,
       _walletService = walletService,
       _appStore = appStore,
       _paymentLinkId = paymentLinkId,
       _zchfNeeded = zchfNeeded,
       super(const PayProcessInitial());

  /// Entry point — called by the view once the user confirms the quote.
  Future<void> start() async {
    // Capability gate — checked BEFORE any on-chain action: the debug wallet
    // cannot produce EIP-1559 signatures, so the irreversible REALU→ZCHF swap
    // must never run on it. The backend settles OCP on every environment
    // (Sepolia off-PRD, mainnet+L2 on PRD), so there is no environment gate
    // here — the flow requests the real quote and surfaces a typed backend
    // error if one ever comes back.
    if (_appStore.wallet.walletType == WalletType.debug) {
      emit(const PayProcessFailure(PayProcessFailureReason.signatureUnsupported));
      return;
    }
    await _requestSwapQuote();
  }

  Future<void> _requestSwapQuote() async {
    try {
      emit(const PayProcessPreparingSwap());
      final swap = await _payService.getSwapPaymentInfo(
        RealUnitSwapDto.fromTargetAmount(_zchfNeeded * _slippageBuffer),
      );
      if (isClosed) return;
      _swap = swap;

      // The API is the authority on whether the swap is fundable; render its
      // signal rather than recomputing limits locally.
      if (!swap.isValid) {
        emit(const PayProcessFailure(PayProcessFailureReason.insufficientZchf));
        return;
      }

      await _checkEthBalance(swap);
    } catch (e) {
      if (isClosed) return;
      emit(PayProcessFailure(PayProcessFailureReason.generic, message: e.toString()));
    }
  }

  Future<void> _checkEthBalance(SwapPaymentInfo swap) async {
    if (swap.ethBalance >= swap.requiredGasEth) {
      await _executeSwap();
      return;
    }
    await _requestFaucet(swap);
  }

  Future<void> _requestFaucet(SwapPaymentInfo swap) async {
    try {
      emit(const PayProcessWaitingForEth());
      await _faucetService.requestFaucet();
      if (isClosed) return;
      _startEthPolling(swap);
    } catch (e) {
      if (isClosed) return;
      emit(PayProcessFailure(PayProcessFailureReason.insufficientEth, message: e.toString()));
    }
  }

  void _startEthPolling(SwapPaymentInfo swap) {
    _ethPollingTimer?.cancel();
    _ethPollAttempts = 0;
    _ethPollingTimer = Timer.periodic(_ethPollInterval, (_) async {
      if (_swapInFlight) return;
      _swapInFlight = true;
      _ethPollAttempts++;
      try {
        final balance = await _blockchainService
            .getEthBalance(_appStore.primaryAddress)
            .timeout(_ethPollTimeout);
        if (isClosed) return;
        if (balance >= swap.requiredGasEth) {
          _ethPollingTimer?.cancel();
          await _executeSwap();
        } else if (_ethPollAttempts >= _ethPollMaxAttempts) {
          _ethPollingTimer?.cancel();
          emit(
            const PayProcessFailure(
              PayProcessFailureReason.insufficientEth,
              message: 'eth balance polling exceeded max attempts',
            ),
          );
        }
        // else: balance still short — falls through to `finally`, which releases
        // `_swapInFlight` so the next tick can retry.
      } catch (_) {
        if (isClosed) return;
        if (_ethPollAttempts >= _ethPollMaxAttempts) {
          _ethPollingTimer?.cancel();
          emit(
            const PayProcessFailure(
              PayProcessFailureReason.insufficientEth,
              message: 'eth balance polling exceeded max attempts',
            ),
          );
          return;
        }
        // keep polling on transient errors (including per-request timeout) — `finally` below
        // releases `_swapInFlight`.
      } finally {
        // Every path out of this tick (success+swap-triggered, max-attempts emit, isClosed
        // abort, transient-error retry) must release the guard — otherwise a stuck `true` from
        // one polling cycle silently wedges every tick of a LATER cycle (`_startEthPolling`
        // never resets this itself). Safe even on the swap-triggered success path: the timer for
        // THIS cycle is already cancelled above before `_executeSwap()` runs.
        _swapInFlight = false;
      }
    });
  }

  Future<void> _executeSwap() async {
    final swap = _swap;
    if (swap == null) return;
    try {
      emit(const PayProcessSwapping());
      final unsigned = await _payService.createSwapUnsignedTransaction(swap.id);
      if (isClosed) return;
      final signed = await _signTransaction(unsigned.swap);
      if (isClosed) return;
      await _payService.broadcastSwapTransaction(swap.id, signed);
      if (isClosed) return;
      // The swap is now irreversible — the user holds ZCHF. From here every
      // recovery path retries the PAY leg only; the swap is never redone.
      _swapCompleted = true;
      _acquiredZchf = swap.estimatedAmount;
      await _refreshQuoteAndPay();
    } on PaySignatureUnsupportedException {
      if (isClosed) return;
      emit(const PayProcessFailure(PayProcessFailureReason.signatureUnsupported));
    } on BitboxNotConnectedException {
      if (isClosed) return;
      emit(const PayProcessFailure(PayProcessFailureReason.bitboxRequired));
    } catch (e) {
      if (isClosed) return;
      emit(PayProcessFailure(PayProcessFailureReason.generic, message: e.toString()));
    }
  }

  /// Retries the pay leg ONLY, after a successful swap. Re-fetches the OCP quote
  /// and re-runs sign + submit; it never re-swaps (guarded by [_swapCompleted]),
  /// so the ZCHF already in the wallet is reused and REALU is never
  /// double-converted. Wired to the retry action on [PayProcessPayRetry].
  Future<void> retryPay() async {
    if (!_swapCompleted) return;
    await _refreshQuoteAndPay();
  }

  /// Re-reads the OCP quote so the pay step uses a fresh quoteId — the swap may
  /// have taken longer than the original quote's validity window. Runs both on
  /// the first pay attempt (right after the swap) and on every [retryPay].
  ///
  /// A GENUINE expiry (the explicit `expiration.isBefore(now)` check) and a
  /// TRANSIENT fetch error are kept distinct: both are recoverable by retrying
  /// the pay leg, so neither forces a re-scan → re-swap.
  Future<void> _refreshQuoteAndPay() async {
    final LnurlpPaymentDto details;
    try {
      emit(const PayProcessRefreshingQuote());
      details = await _payService.getPaymentDetails(_paymentLinkId);
    } catch (e) {
      // Transient/network error fetching the quote — NOT a genuine expiry.
      // Retry the pay leg; the swapped ZCHF stays in the wallet.
      if (isClosed) return;
      emit(PayProcessPayRetry(PayRetryReason.transient, message: e.toString()));
      return;
    }

    if (isClosed) return;

    if (details.quote.expiration.isBefore(DateTime.now())) {
      emit(const PayProcessPayRetry(PayRetryReason.quoteExpired));
      return;
    }

    // Guard the slippage boundary: the swap acquired [_acquiredZchf], but the
    // fresh quote may now demand more ZCHF than that. Settling it would fail
    // server-side AFTER the irreversible swap, so surface a typed, retryable
    // state (re-quote may land within the held ZCHF) instead of an opaque
    // failure. The leftover ZCHF stays in the wallet.
    //
    // Comparison prefers exact plain-decimal strings on the fresh side
    // ([LnurlpTransferAssetDto.rawAmount]) vs. [_acquiredZchf].toString(). Note
    // that [_acquiredZchf] is still ultimately double-derived upstream
    // (swap.estimatedAmount via RealUnitSwapPaymentInfoDto — out of this fix's
    // scope); this only removes binary-comparison artifacts at the comparison
    // site itself and gives exact precision on the freshZchf side, without
    // pretending end-to-end exactness. When the raw string is missing or a plain-decimal
    // comparison cannot be performed (parsing throws), the comparison is fail-closed:
    // [_settlementExceedsAcquired] returns `true` (= exceeds acquired), triggering the
    // [PayRetryReason.insufficientZchf] retry — never treated as "covered".
    final freshZchf = _zchfTransferAmount(details);
    if (freshZchf != null &&
        _settlementExceedsAcquired(freshZchf.amount, freshZchf.raw, _acquiredZchf)) {
      emit(
        PayProcessPayRetry(
          PayRetryReason.insufficientZchf,
          message:
              'fresh settlement ${freshZchf.amount} ZCHF exceeds acquired $_acquiredZchf ZCHF',
        ),
      );
      return;
    }

    await _executePay(details.quote.id);
  }

  Future<void> _executePay(String quoteId) async {
    try {
      emit(const PayProcessPaying());
      final RealUnitOcpPayUnsignedTransactionDto unsigned = await _payService
          .createPayUnsignedTransaction(
            RealUnitOcpPayDto(paymentLinkId: _paymentLinkId, quoteId: quoteId),
          );
      if (isClosed) return;
      _validatePayUnsignedTx(unsigned);
      final signed = await _signTransaction(unsigned.unsignedTx);
      if (isClosed) return;
      final txId = await _payService.submitPay(
        RealUnitOcpPaySubmitDto(
          unsignedTx: signed.unsignedTx,
          r: signed.r,
          s: signed.s,
          v: signed.v,
          paymentLinkId: _paymentLinkId,
          quoteId: quoteId,
        ),
      );
      if (isClosed) return;
      emit(PayProcessAwaitingSettlement(txId));
      _startStatusPolling();
    } on PayUnsignedTxMismatchException catch (e) {
      // The backend's own unsigned tx does not match its own metadata — never sign it. The swap
      // already happened; recovery retries the pay leg, which re-fetches AND re-validates a fresh
      // unsigned tx from scratch, so a bad tx can never slip through on retry.
      if (isClosed) return;
      emit(PayProcessPayRetry(PayRetryReason.unsignedTxMismatch, message: e.toString()));
    } catch (e) {
      // The swap already happened; the user holds ZCHF. Any pay-leg failure here (signing
      // dropped, BitBox disconnect, transient submit error, settlement rejected) is recoverable
      // by retrying the pay leg — never by re-swapping. Surface the retryable state rather than a
      // terminal failure.
      if (isClosed) return;
      emit(PayProcessPayRetry(PayRetryReason.transient, message: e.toString()));
    }
  }

  /// The ZCHF amount listed for the Ethereum transfer method in a fresh quote,
  /// or null if the link no longer offers a priced Ethereum/ZCHF method. Mirrors
  /// [PayQuoteCubit]'s selection — the app never computes the amount locally.
  /// Also surfaces the raw JSON amount string when present for exact decimal
  /// comparison (see [_settlementExceedsAcquired]).
  static ({double amount, String? raw})? _zchfTransferAmount(LnurlpPaymentDto details) {
    for (final transfer in details.transferAmounts) {
      if (transfer.method.toLowerCase() != 'ethereum') continue;
      for (final asset in transfer.assets) {
        if (asset.asset.toUpperCase() != 'ZCHF') continue;
        final amount = asset.amount;
        if (amount == null) return null;
        return (amount: amount, raw: asset.rawAmount);
      }
    }
    return null;
  }

  /// True when [freshAmount] strictly exceeds [acquired] — or when an exact plain-decimal
  /// comparison cannot be established at all. Never falls back to a rounding-prone double `>`
  /// comparison: doing so could wrongly report "not exceeding" (falsely "covered") when the true
  /// decimal values differ. Fail-closed: any inability to prove exact coverage is treated as
  /// "exceeds acquired", which routes the caller into the existing retryable
  /// [PayRetryReason.insufficientZchf] path rather than risking an under-swapped settlement.
  static bool _settlementExceedsAcquired(
    double freshAmount,
    String? freshRaw,
    double acquired,
  ) {
    if (freshRaw == null) {
      return true;
    }
    final acquiredRaw = acquired.toString();
    try {
      return comparePlainDecimalStrings(freshRaw, acquiredRaw) > 0;
    } on FormatException {
      // Not a plain decimal on one/both sides (e.g. scientific notation from double.toString) —
      // cannot prove exact coverage. Fail closed rather than falling back to a rounding-prone
      // double comparison that could wrongly say "covered".
      return true;
    }
  }

  /// Locally re-derives the security-relevant fields of the pay-leg [unsigned] raw tx (the ZCHF
  /// ERC20-transfer `to`/recipient/amount/chainId/gas/fees) from the RLP bytes themselves and
  /// checks them against the DTO metadata, the app's locally configured chainId
  /// (`apiConfig.asset.chainId`), and local gas/fee caps BEFORE the pay tx is signed. Scope is
  /// the pay leg only — the earlier REALU→ZCHF swap (`RealUnitSwapUnsignedTransactionDto`) is
  /// signed without an equivalent decode+validate step today (that DTO has no comparable
  /// metadata; closing the gap needs a backend extension). The backend is untrusted for this: a
  /// compromised/buggy backend must never be able to make the app sign a pay transfer to the
  /// wrong token, recipient, amount, chain, or with unbounded fees. Throws
  /// [PayUnsignedTxMismatchException] fail-closed on any mismatch or structural anomaly.
  void _validatePayUnsignedTx(RealUnitOcpPayUnsignedTransactionDto unsigned) {
    final tx = Eip1559UnsignedTxDecoder.decode(unsigned.unsignedTx);

    // Network + fee sanity (DTO self-consistency, local trusted chain, gas/fee caps)
    // before content checks (to / recipient / amount).
    final expectedChainId = BigInt.from(unsigned.chainId);
    if (tx.chainId != expectedChainId) {
      throw PayUnsignedTxMismatchException(
        'chainId mismatch: tx=${tx.chainId} dto=${unsigned.chainId}',
      );
    }

    // Independent of the DTO: bind against the chainId baked into the app build
    // (same value `_signTransaction` passes to `signToSignature`). A compromised
    // backend that returns a self-consistent but wrong chainId cannot pass this.
    final localChainId = BigInt.from(_appStore.apiConfig.asset.chainId);
    if (tx.chainId != localChainId) {
      throw PayUnsignedTxMismatchException(
        'chainId ${tx.chainId} does not match locally configured chain $localChainId '
        '(apiConfig.asset.chainId) — refusing to sign for an unexpected network',
      );
    }

    if (tx.gasLimit > BigInt.from(_maxGasLimit)) {
      throw PayUnsignedTxMismatchException(
        'unsigned tx gasLimit ${tx.gasLimit} exceeds local cap $_maxGasLimit',
      );
    }
    final totalFeeWei = tx.maxFeePerGas * tx.gasLimit;
    if (totalFeeWei > _maxTotalFeeWei) {
      throw PayUnsignedTxMismatchException(
        'unsigned tx max total fee $totalFeeWei wei exceeds local cap $_maxTotalFeeWei wei',
      );
    }

    if (tx.value != BigInt.zero) {
      throw PayUnsignedTxMismatchException(
        'unsigned tx sends native value ${tx.value}, expected 0',
      );
    }

    final expectedToken = _normalizeAddress(unsigned.tokenAddress, 'tokenAddress');
    if (tx.to != expectedToken) {
      throw PayUnsignedTxMismatchException(
        'tokenAddress mismatch: tx.to=${tx.to} dto.tokenAddress=${unsigned.tokenAddress}',
      );
    }

    final transfer = Erc20TransferCalldataDecoder.decode(tx.data);

    final expectedRecipient = _normalizeAddress(unsigned.recipient, 'recipient');
    if (transfer.recipient != expectedRecipient) {
      throw PayUnsignedTxMismatchException(
        'recipient mismatch: calldata=${transfer.recipient} dto.recipient=${unsigned.recipient}',
      );
    }

    final BigInt expectedAmount;
    try {
      expectedAmount = BigInt.parse(unsigned.amountWei);
    } on FormatException {
      throw PayUnsignedTxMismatchException('amountWei is not a valid integer: ${unsigned.amountWei}');
    }
    if (transfer.amountWei != expectedAmount) {
      throw PayUnsignedTxMismatchException(
        'amount mismatch: calldata=${transfer.amountWei} dto.amountWei=${unsigned.amountWei}',
      );
    }
  }

  /// Normalizes an address DTO field to `0x` + 40 lowercase hex chars, or throws
  /// [PayUnsignedTxMismatchException] if it isn't one — refusing to compare against a malformed
  /// address is safer than silently truncating/padding it.
  static String _normalizeAddress(String raw, String fieldName) {
    final hex = (raw.startsWith('0x') || raw.startsWith('0X')) ? raw.substring(2) : raw;
    if (!RegExp(r'^[0-9a-fA-F]{40}$').hasMatch(hex)) {
      throw PayUnsignedTxMismatchException('$fieldName is not a valid 20-byte address: $raw');
    }
    return '0x${hex.toLowerCase()}';
  }

  void _startStatusPolling() {
    _statusPollingTimer?.cancel();
    final generation = ++_statusPollGeneration;
    _statusPollAttempts = 0;
    _statusPollInFlight = false;
    _statusPollingTimer = Timer.periodic(_statusPollInterval, (_) async {
      if (generation != _statusPollGeneration || _statusPollInFlight) return;
      _statusPollInFlight = true;
      try {
        final status = await _payService.getPayStatus(_paymentLinkId);
        if (isClosed || generation != _statusPollGeneration) return;
        _statusPollAttempts++;
        if (!status.status.isTerminal) {
          if (_statusPollAttempts >= _statusPollMaxAttempts) {
            _statusPollingTimer?.cancel();
            emit(
              const PayProcessPayRetry(
                PayRetryReason.transient,
                message: 'status polling exceeded max attempts',
              ),
            );
            return;
          }
          _statusPollInFlight = false;
          return;
        }
        _statusPollingTimer?.cancel();
        if (status.status.isCompleted) {
          emit(const PayProcessSuccess());
        } else {
          emit(const PayProcessPayRetry(PayRetryReason.transient));
        }
      } catch (_) {
        if (isClosed || generation != _statusPollGeneration) return;
        _statusPollAttempts++;
        if (_statusPollAttempts >= _statusPollMaxAttempts) {
          _statusPollingTimer?.cancel();
          emit(
            const PayProcessPayRetry(
              PayRetryReason.transient,
              message: 'status polling exceeded max attempts',
            ),
          );
          return;
        }
        _statusPollInFlight = false;
      }
    });
  }

  /// Signs a serialized unsigned EIP-1559 tx with the active wallet credentials
  /// and returns the broadcast envelope (`unsignedTx` + r/s/v). Works for
  /// software and BitBox; a debug wallet's `signToSignature` throws
  /// [UnsupportedError], normalised here to [PaySignatureUnsupportedException].
  Future<BroadcastTransactionRequestDto> _signTransaction(String rawTransaction) async {
    await _walletService.ensureCurrentWalletUnlocked();
    try {
      final credentials = _appStore.wallet.currentAccount.primaryAddress;
      final payload = Uint8List.fromList(
        convert.hex.decode(
          rawTransaction.startsWith('0x') ? rawTransaction.substring(2) : rawTransaction,
        ),
      );
      final MsgSignature sig;
      try {
        sig = await credentials.signToSignature(
          payload,
          chainId: _appStore.apiConfig.asset.chainId,
          isEIP1559: true,
        );
      } on UnsupportedError {
        throw const PaySignatureUnsupportedException();
      }
      final r = sig.r.toRadixString(16).padLeft(64, '0');
      final s = sig.s.toRadixString(16).padLeft(64, '0');
      return BroadcastTransactionRequestDto(
        unsignedTx: rawTransaction,
        r: '0x$r',
        s: '0x$s',
        v: sig.v,
      );
    } finally {
      await _walletService.lockCurrentWallet();
    }
  }

  @override
  Future<void> close() {
    _ethPollingTimer?.cancel();
    _statusPollingTimer?.cancel();
    return super.close();
  }
}
