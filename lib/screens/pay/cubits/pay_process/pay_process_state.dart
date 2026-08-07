part of 'pay_process_cubit.dart';

/// Why the pay flow failed. Each reason maps to a localized, user-facing
/// message in the view — the cubit carries the reason, not the copy.
enum PayProcessFailureReason {
  /// The swap quote came back invalid (e.g. not fundable for the requested
  /// ZCHF amount after the slippage buffer).
  insufficientZchf,

  /// Not enough ETH to cover gas and the faucet top-up did not arrive.
  insufficientEth,

  /// The active wallet mode cannot sign transactions (debug wallet).
  signatureUnsupported,

  /// A BitBox is required but not connected.
  bitboxRequired,

  /// Any other unexpected error.
  generic,
}

/// Why the pay leg failed AFTER the REALU→ZCHF swap already succeeded. The user
/// holds ZCHF, so recovery must retry the pay leg ONLY (re-quote + sign +
/// submit) — never the swap. Each reason maps to a localized message.
enum PayRetryReason {
  /// The OCP quote expired between the swap and the pay step. Re-quoting is
  /// safe — the swapped ZCHF stays in the wallet.
  quoteExpired,

  /// A transient/network error while re-fetching the quote or settling. Not a
  /// genuine expiry; retrying the pay leg is the correct recovery.
  transient,

  /// The freshly re-fetched settlement amount exceeds the ZCHF acquired by the
  /// swap (price moved more than the swap headroom buffer). Re-quoting may land
  /// within the held ZCHF; the leftover ZCHF stays in the wallet meanwhile.
  insufficientZchf,

  /// The unsigned tx the backend returned for signing did not match its own security metadata
  /// (token/recipient/amount/chain) — see [PayUnsignedTxMismatchException]. Never signed. Retrying
  /// re-fetches AND re-validates a fresh unsigned tx from scratch.
  unsignedTxMismatch,
}

sealed class PayProcessState extends Equatable {
  const PayProcessState();

  @override
  List<Object?> get props => [];
}

class PayProcessInitial extends PayProcessState {
  const PayProcessInitial();
}

class PayProcessPreparingSwap extends PayProcessState {
  const PayProcessPreparingSwap();
}

class PayProcessWaitingForEth extends PayProcessState {
  const PayProcessWaitingForEth();
}

class PayProcessSwapping extends PayProcessState {
  const PayProcessSwapping();
}

class PayProcessRefreshingQuote extends PayProcessState {
  const PayProcessRefreshingQuote();
}

class PayProcessPaying extends PayProcessState {
  const PayProcessPaying();
}

/// Pay tx submitted; polling `/pay/:id/status` until it settles.
class PayProcessAwaitingSettlement extends PayProcessState {
  final String txId;

  const PayProcessAwaitingSettlement(this.txId);

  @override
  List<Object?> get props => [txId];
}

class PayProcessSuccess extends PayProcessState {
  const PayProcessSuccess();
}

/// The swap succeeded (ZCHF is in the wallet) but the pay leg failed. Recoverable
/// by retrying the pay leg ONLY — the view calls [PayProcessCubit.retryPay],
/// which re-quotes + signs + submits without ever re-swapping. This is the key
/// fund-safety state: a failed pay no longer forces a re-scan → re-swap (which
/// would double-convert REALU).
class PayProcessPayRetry extends PayProcessState {
  final PayRetryReason reason;

  /// Diagnostic detail for logs — not the user-facing copy.
  final String? message;

  const PayProcessPayRetry(this.reason, {this.message});

  @override
  List<Object?> get props => [reason, message];
}

class PayProcessFailure extends PayProcessState {
  final PayProcessFailureReason reason;

  /// Diagnostic detail for logs — not the user-facing copy.
  final String? message;

  const PayProcessFailure(this.reason, {this.message});

  @override
  List<Object?> get props => [reason, message];
}
