import 'package:realunit_wallet/packages/service/dfx/models/referral/referral_json_list.dart';

/// One referral payout row from `GET /v1/realunit/referral/payouts`.
/// The API returns Settled public fields only (no `userId` / `inviteId`).
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

  /// History only shows a prize after the on-chain transfer is confirmed
  /// (Offerte Punkt 4). Pending/failed rows stay off the ledger.
  bool get isSettled {
    final s = status.toLowerCase();
    if (s.isEmpty) return true;
    return s == 'complete' ||
        s == 'completed' ||
        s == 'credited' ||
        s == 'success' ||
        s == 'confirmed' ||
        s == 'settled' ||
        s == 'paid' ||
        s == 'done' ||
        s == 'transferred';
  }

  factory ReferralPayoutDto.fromJson(Map<String, dynamic> json) {
    final amount = referralJsonNum(json['amount']);
    final created = referralJsonDate(json['created']);
    if (amount == null || created == null) {
      throw FormatException('referral payout missing amount/created');
    }
    return ReferralPayoutDto(
      id: referralJsonInt(json['id']),
      amount: amount,
      // Garbage/missing frozen CHF is 0.00 (TB Ziff. 6) so Anzahl+Datum
      // still appear; JSON null from a NaN API value must not drop the prize.
      chfValue: referralJsonNum(json['chfValue']) ?? 0,
      created: created,
      kind: referralJsonString(json['kind']) ?? '',
      status: referralJsonString(json['status']) ?? 'Settled',
      txHash: referralJsonString(json['txHash']),
    );
  }
}
