// Typed failures for the wallet-to-wallet (W2W) RealUnit transfer flow
// (enter/scan recipient → amount → confirm → sign → transfer → confirm). Each
// one renders a human-readable string (enumerated in `exception_surface_test.dart`)
// so it surfaces cleanly in logs and user-facing error states instead of the
// Dart default `Instance of '...'`. Typed failures drive control flow — no
// error-string parsing.

import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';

/// The recipient string the user scanned or pasted is not a syntactically valid
/// EVM address. This is a client-side UX guard only; the API remains the final
/// authority on the address.
class InvalidRecipientAddressException implements Exception {
  /// The rejected raw input, for diagnostics.
  final String input;

  const InvalidRecipientAddressException(this.input);

  @override
  String toString() => 'InvalidRecipientAddressException: $input is not a valid wallet address';
}

/// The active wallet mode cannot produce the EIP-712 delegation + EIP-7702
/// authorization the gasless transfer requires (today: the debug wallet, and
/// hardware wallets whose firmware exposes no raw EIP-7702 signing API). The
/// flow is not branched on wallet type beyond this capability gate.
class TransferSignatureUnsupportedException implements Exception {
  /// Diagnostic detail (e.g. the underlying signer message).
  final String detail;

  const TransferSignatureUnsupportedException([
    this.detail = 'this wallet mode cannot sign gasless transfers',
  ]);

  @override
  String toString() => 'TransferSignatureUnsupportedException: $detail';
}

/// DFX cannot currently fund gas for the gasless transfer (the backend's
/// dedicated W2W gas wallet is unconfigured or below its low-balance
/// threshold). Surfaced from the API's `ServiceUnavailable` (503) as a friendly
/// "temporarily unavailable" state — the user's REALU is untouched.
class TransferGasFundingUnavailableException implements Exception {
  /// Diagnostic detail (e.g. the API message), for logs.
  final String detail;

  const TransferGasFundingUnavailableException([
    this.detail = 'gas funding for transfers is temporarily unavailable',
  ]);

  @override
  String toString() => 'TransferGasFundingUnavailableException: $detail';
}

/// The prepare response's recipient/amount does not match what the user
/// confirmed on-screen. Fail-closed before any signature is produced so a
/// mismatched backend echo cannot be blind-signed.
class TransferConfirmMismatchException implements Exception {
  /// Diagnostic detail (which field diverged), for logs.
  final String detail;

  const TransferConfirmMismatchException([
    this.detail = 'prepare response does not match user-confirmed recipient/amount',
  ]);

  @override
  String toString() => 'TransferConfirmMismatchException: $detail';
}

/// The transfer was already confirmed server-side (HTTP 409 with an
/// "already confirmed" message). An earlier confirm for the same transfer `id`
/// landed but its response was lost (e.g. transport failure after the server
/// processed the request). Callers must treat this as success, not failure —
/// mirrors the sell flow's [AlreadyConfirmedException] for the W2W path.
class TransferAlreadyConfirmedException extends ApiException {
  /// Server-reported tx hash when present on the 409 body; null otherwise.
  final String? txHash;

  const TransferAlreadyConfirmedException({
    super.statusCode,
    required super.code,
    required super.message,
    this.txHash,
  });

  @override
  String toString() => 'TransferAlreadyConfirmedException: $message';
}
