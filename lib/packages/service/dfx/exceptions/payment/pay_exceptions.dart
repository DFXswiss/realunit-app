// Typed failures for the OCP pay flow (scan → swap → pay). Each one renders a
// human-readable string (see `exception_surface_test.dart`) so it can surface
// cleanly in logs, Sentry, and user-facing error states instead of the Dart
// default `Instance of '...'`.

/// The scanned QR / pasted code is not a DFX Open CryptoPay payment link.
class InvalidPaymentLinkException implements Exception {
  final String reason;

  const InvalidPaymentLinkException(this.reason);

  @override
  String toString() => 'InvalidPaymentLinkException: $reason';
}

/// The loaded wallet cannot produce EIP-1559 signatures (today: the debug
/// wallet). The pay flow needs to sign the swap and pay transactions locally,
/// so it cannot proceed in this wallet mode.
class PaySignatureUnsupportedException implements Exception {
  // Only ever thrown / constructed as a const expression, so the zero-arg
  // body never registers a runtime line hit; toString() below is exercised.
  const PaySignatureUnsupportedException(); // coverage:ignore-line

  @override
  String toString() =>
      'PaySignatureUnsupportedException: this wallet mode cannot sign transactions';
}

/// The unsigned pay-leg (ZCHF ERC20-transfer) transaction the backend returned for signing does
/// not match its accompanying security metadata (`tokenAddress`, `recipient`, `amountWei`,
/// `chainId`), exceeds local gas/fee caps, mismatches the app's locally configured chainId, or
/// could not be parsed as the expected EIP-1559 ERC20-transfer shape. Thrown by
/// Eip1559UnsignedTxDecoder / Erc20TransferCalldataDecoder and
/// PayProcessCubit._validatePayUnsignedTx BEFORE any pay-leg signing happens, so a
/// malformed/compromised backend pay response can never be blindly signed.
///
/// Scope is the pay leg only. The earlier REALU→ZCHF swap leg
/// (`RealUnitSwapUnsignedTransactionDto`) is signed without this validation today (that DTO
/// has no comparable metadata); closing that gap needs a backend DTO extension.
class PayUnsignedTxMismatchException implements Exception {
  final String reason;

  const PayUnsignedTxMismatchException(this.reason);

  @override
  String toString() => 'PayUnsignedTxMismatchException: $reason';
}
