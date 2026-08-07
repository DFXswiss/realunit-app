/// Response of `PUT /v1/realunit/pay/unsigned-transaction` — the serialized
/// unsigned EIP-1559 ZCHF transfer transaction to the OCP recipient, plus the
/// metadata the app shows / can sanity-check before signing.
class RealUnitOcpPayUnsignedTransactionDto {
  final String unsignedTx;
  final String tokenAddress;
  final String recipient;
  final String amountWei;
  final int chainId;

  const RealUnitOcpPayUnsignedTransactionDto({
    required this.unsignedTx,
    required this.tokenAddress,
    required this.recipient,
    required this.amountWei,
    required this.chainId,
  });

  factory RealUnitOcpPayUnsignedTransactionDto.fromJson(Map<String, dynamic> json) {
    return RealUnitOcpPayUnsignedTransactionDto(
      unsignedTx: json['unsignedTx'] as String,
      tokenAddress: json['tokenAddress'] as String,
      recipient: json['recipient'] as String,
      amountWei: json['amountWei'] as String,
      chainId: json['chainId'] as int,
    );
  }
}
