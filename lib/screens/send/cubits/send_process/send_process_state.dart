part of 'send_process_cubit.dart';

/// Why the transfer failed. Each reason maps to a localized, user-facing message
/// in the view — the cubit carries the reason, not the copy.
enum SendProcessFailureReason {
  /// The active wallet mode cannot sign the gasless EIP-7702 transfer (debug or
  /// BitBox wallet, or a debug credential detected at sign time).
  signatureUnsupported,

  /// The user cancelled the signature (or the signing device dropped the link).
  signatureCancelled,

  /// DFX cannot currently fund gas for the transfer (the API's 503). The user's
  /// REALU is untouched — this is a transient "temporarily unavailable" state.
  gasFundingUnavailable,

  /// The API rejected the prepare request (invalid recipient, self-transfer,
  /// token-contract recipient, non-integer amount, or insufficient REALU). The
  /// API message carries the specific detail.
  invalidRequest,

  /// The API requires the user to complete registration or a higher KYC level
  /// before this transfer can proceed (403 REGISTRATION_REQUIRED /
  /// KYC_LEVEL_REQUIRED).
  registrationOrKycRequired,

  /// The prepare response's recipient/amount did not match what the user
  /// confirmed on-screen. Fail-closed before signing; not retryable with the
  /// same prepared intent (the server-echoed data itself is wrong).
  confirmMismatch,

  /// Any other unexpected error.
  generic,
}

sealed class SendProcessState extends Equatable {
  const SendProcessState();

  @override
  List<Object?> get props => [];
}

class SendProcessInitial extends SendProcessState {
  const SendProcessInitial();
}

/// `PUT /transfer` in flight — preparing the intent + EIP-7702 delegation data.
class SendProcessPreparing extends SendProcessState {
  const SendProcessPreparing();
}

/// Signing the EIP-712 delegation + EIP-7702 authorization and confirming.
class SendProcessSigning extends SendProcessState {
  const SendProcessSigning();
}

class SendProcessSuccess extends SendProcessState {
  final String txHash;

  const SendProcessSuccess(this.txHash);

  @override
  List<Object?> get props => [txHash];
}

class SendProcessFailure extends SendProcessState {
  final SendProcessFailureReason reason;

  /// Diagnostic detail for logs — not the user-facing copy.
  final String? message;

  /// When true, the prepared transfer `id` is retained and the user may call
  /// [SendProcessCubit.retryConfirm] to re-sign and re-PUT `/confirm` for the
  /// same intent (no new prepare). Defaults to false — a UI affordance flag,
  /// not a data-correctness fallback.
  final bool canRetry;

  const SendProcessFailure(this.reason, {this.message, this.canRetry = false});

  @override
  List<Object?> get props => [reason, message, canRetry];
}
