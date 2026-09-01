/// Server-side referral programme summary for the current wallet
/// (`GET /v1/realunit/referral/summary`). `eligible` is the authoritative
/// entry gate — see CONTRIBUTING.md "API as Decision Authority".
class ReferralSummaryDto {
  final bool eligible;
  final bool termsAccepted;
  final num? minHolding;
  final int openCount;
  final int creditedCount;
  final num realuSum;
  final num chfSum;

  const ReferralSummaryDto({
    required this.eligible,
    required this.termsAccepted,
    this.minHolding,
    required this.openCount,
    required this.creditedCount,
    required this.realuSum,
    required this.chfSum,
  });

  factory ReferralSummaryDto.fromJson(Map<String, dynamic> json) {
    return ReferralSummaryDto(
      eligible: json['eligible'] as bool,
      termsAccepted: json['termsAccepted'] as bool,
      minHolding: json['minHolding'] as num?,
      openCount: (json['openCount'] as num).toInt(),
      creditedCount: (json['creditedCount'] as num).toInt(),
      realuSum: json['realuSum'] as num,
      chfSum: json['chfSum'] as num,
    );
  }
}
