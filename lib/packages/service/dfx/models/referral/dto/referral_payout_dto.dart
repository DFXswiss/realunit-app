/// One referral payout row from `GET /v1/realunit/referral/payouts`.
/// [chfValue] is the CHF amount frozen at credit — never recompute from current price.
class ReferralPayoutDto {
  final int id;
  final num amount;
  final num chfValue;
  final DateTime created;
  final String kind;
  final String status;
  final String? txHash;

  const ReferralPayoutDto({
    required this.id,
    required this.amount,
    required this.chfValue,
    required this.created,
    required this.kind,
    required this.status,
    this.txHash,
  });

  factory ReferralPayoutDto.fromJson(Map<String, dynamic> json) {
    return ReferralPayoutDto(
      id: (json['id'] as num).toInt(),
      amount: json['amount'] as num,
      chfValue: json['chfValue'] as num,
      created: DateTime.parse(json['created'] as String),
      kind: json['kind'] as String,
      status: json['status'] as String,
      txHash: json['txHash'] as String?,
    );
  }
}
