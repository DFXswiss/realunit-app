import 'package:realunit_wallet/packages/service/dfx/models/referral/locale_text.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/referral_json_list.dart';

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
  final String? sharePriceLabel;
  final num? sharePrice;

  const ReferralSummaryDto({
    required this.eligible,
    required this.termsAccepted,
    this.minHolding,
    required this.openCount,
    required this.creditedCount,
    required this.realuSum,
    required this.chfSum,
    this.sharePriceLabel,
    this.sharePrice,
  });

  /// Offerte: total tile may show the running value at Aktienkurs.
  /// History still uses frozen [chfSum] / payout `chfValue`.
  num get tileChf {
    final price = sharePrice;
    if (price != null && price > 0 && realuSum > 0) {
      final whole = realuSum is int ? realuSum : realuSum.truncate();
      return ((whole * price) * 100).round() / 100;
    }
    return chfSum;
  }

  /// Tile label. Empty API fields, «NAV» copy (Offerte draft 5), and the
  /// canonical API token `Aktienkurs` fall back to localized copy
  /// (DE «Aktienkurs», EN «Share price»). Mail Dani 24.08.2026 17:42
  /// forbids «aktueller NAV»; it does not pin the English UI to German.
  String? get tileSharePriceLabel {
    final raw = firstNonEmpty([sharePriceLabel]);
    if (raw == null) return null;
    if (RegExp(r'NAV', caseSensitive: false).hasMatch(raw)) return null;
    if (RegExp(r'^Aktienkurs$', caseSensitive: false).hasMatch(raw)) {
      return null;
    }
    return raw;
  }

  factory ReferralSummaryDto.fromJson(Map<String, dynamic> json) {
    return ReferralSummaryDto(
      eligible: referralJsonBool(json['eligible']),
      termsAccepted: referralJsonBool(json['termsAccepted']),
      minHolding: referralJsonNum(json['minHolding']),
      openCount: referralJsonInt(json['openCount']),
      creditedCount: referralJsonInt(json['creditedCount']),
      realuSum: referralJsonNum(json['realuSum']) ?? 0,
      chfSum: referralJsonNum(json['chfSum']) ?? 0,
      sharePriceLabel: referralJsonString(json['sharePriceLabel']),
      sharePrice: referralJsonNum(json['sharePrice']),
    );
  }
}
