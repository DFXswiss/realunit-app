/// Response of `PUT /v1/realunit/swap/:id/unsigned-transaction` — the
/// serialized unsigned EIP-1559 REALU `transferAndCall` swap transaction hex
/// (no deposit sweep; ZCHF lands in the user wallet).
class RealUnitSwapUnsignedTransactionDto {
  final String swap;

  const RealUnitSwapUnsignedTransactionDto({required this.swap});

  factory RealUnitSwapUnsignedTransactionDto.fromJson(Map<String, dynamic> json) {
    return RealUnitSwapUnsignedTransactionDto(swap: json['swap'] as String);
  }
}
