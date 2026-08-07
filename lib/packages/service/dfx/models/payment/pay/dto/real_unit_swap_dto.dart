/// Request body for `PUT /v1/realunit/swap`. The backend enforces the `amount`
/// XOR `targetAmount` rule; the app sends exactly one. `amount` is in REALU
/// shares, `targetAmount` is in ZCHF. IBAN-free by design (proceeds stay in the
/// user wallet).
class RealUnitSwapDto {
  /// Amount of REALU shares to swap.
  final int? amount;

  /// Target amount in ZCHF (alternative to [amount]).
  final double? targetAmount;

  // The OCP pay flow always sizes the swap by ZCHF target (fromTargetAmount);
  // `amount` stays in the body only to document the backend's XOR contract and
  // is always null on the wire here.
  const RealUnitSwapDto.fromTargetAmount(double this.targetAmount) : amount = null;

  Map<String, dynamic> toJson() => {
    if (amount != null) 'amount': amount,
    if (targetAmount != null) 'targetAmount': targetAmount,
  };
}
