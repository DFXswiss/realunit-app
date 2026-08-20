/// Parses user-typed fiat text, accepting a comma as the decimal separator.
/// Rejects grouping-ambiguous input — a lone separator followed by exactly
/// three digits (`1,000` / `1.000`) usually means a thousands group, and
/// reading it as a decimal would quote 1/1000th of the intended amount.
double? tryParseFiatAmount(String input) {
  if (RegExp(r'^\d+[.,]\d{3}$').hasMatch(input)) return null;
  return double.tryParse(input.replaceAll(',', '.'));
}

/// Strips thousands grouping (`1.000` / `1,000` / `1.000.000` → integer).
///
/// EUR and CHF have two decimal places, so a separator followed by exactly
/// three digits cannot be a decimal. Consecutive groups with the same
/// separator are unambiguous thousands grouping, so a paste of `1.000.000`
/// matches what typing the same characters one by one already produced.
/// Mixed thousands + 1–2 decimal digits of the other separator (`1.000,50` /
/// `1,000.50`) drop the thousands separator and keep the decimal, so paste
/// matches typing. Real decimals (`300,75`) and partials (`1.`, `1.0`,
/// `1.00`) are returned unchanged, as is mixed input that is not uniquely
/// thousands-then-decimal (`1.000,000`, `3,5,7`).
String normalizeFiatInput(String input) {
  if (RegExp(r'^(\d+)([.,])(\d{3}(?:\2\d{3})*)$').hasMatch(input)) {
    return input.replaceAll('.', '').replaceAll(',', '');
  }
  final mixed = RegExp(r'^(\d+)([.,])(\d{3}(?:\2\d{3})*)([.,])(\d{1,2})$').firstMatch(input);
  if (mixed != null && mixed[2] != mixed[4]) {
    return input.replaceAll(mixed[2]!, '');
  }
  return input;
}

/// The whole-currency integer the backend charges for the raw [input] the user
/// typed (e.g. `300,75` → `301`); empty input counts as zero.
int chargedFiatAmount(String input) {
  final amount = tryParseFiatAmount(input.isEmpty ? '0' : input);
  if (amount == null) throw FormatException('Invalid fiat amount', input);
  return amount.round();
}
