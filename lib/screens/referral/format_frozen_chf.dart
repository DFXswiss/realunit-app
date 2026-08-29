import 'package:realunit_wallet/packages/service/dfx/models/referral/referral_json_list.dart';
import 'package:realunit_wallet/packages/utils/format_fixed.dart';

/// Formats the CHF amount frozen at credit for history and dashboard rows.
/// The ARB string already prefixes `CHF`, so this is the numeric part only.
/// A DE/CH decimal comma (`246,5`), Swiss thousands apostrophes
/// (`1'246.50`), and a `CHF` prefix are accepted.
String formatFrozenChfAmount(String raw) {
  final n = parseReferralDecimal(raw);
  if (n == null) return raw;
  return n.toStringAsFixed(2);
}

/// Matches [HideAmountText] for a whole-REALU prize (+ 20 REALU / + ***.**).
String referralPayoutAmountText({
  required bool hideAmounts,
  required BigInt amount,
  required int decimals,
  required String symbol,
}) {
  if (hideAmounts) return '+ ***.**';
  return '+ ${formatFixed(amount, decimals, fractionalDigits: 0, trimZeros: false)} $symbol';
}

/// One VoiceOver name: title, date, frozen CHF, amount.
String referralPayoutSemanticsLabel({
  required String title,
  required String date,
  required String amount,
  String? chfLine,
}) {
  return [
    title,
    date,
    if (chfLine != null && chfLine.isNotEmpty) chfLine,
    amount,
  ].join('. ');
}
