/// Request body for `PUT /v1/realunit/transfer` — the wallet-to-wallet
/// transfer intent. REALU has `decimals = 0`, so [amount] is a whole number of
/// shares.
class RealUnitTransferDto {
  final String toAddress;
  final int amount;

  const RealUnitTransferDto({
    required this.toAddress,
    required this.amount,
  });

  Map<String, dynamic> toJson() {
    return {
      'toAddress': toAddress,
      'amount': amount,
    };
  }
}
