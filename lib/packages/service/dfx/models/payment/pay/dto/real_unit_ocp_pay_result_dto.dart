/// Response of `PUT /v1/realunit/pay/submit` — the blockchain transaction id of
/// the submitted ZCHF payment.
class RealUnitOcpPayResultDto {
  final String txId;

  const RealUnitOcpPayResultDto({required this.txId});

  factory RealUnitOcpPayResultDto.fromJson(Map<String, dynamic> json) {
    return RealUnitOcpPayResultDto(txId: json['txId'] as String);
  }
}
