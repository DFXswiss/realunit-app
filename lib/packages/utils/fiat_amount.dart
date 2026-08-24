/// Parses user-typed fiat text for CHF/EUR (at most two decimal places).
///
/// Swiss apostrophes and spaces are thousands marks. A single `.` or `,`
/// followed by exactly three digits is a thousands group (`105.000` /
/// `90,000` → 105000 / 90000), not a 3-decimal fraction — quoting that as
/// 105.0 would silently buy a thousandth of the intended amount. One or two
/// digits after the separator stay a decimal (`300,75` → 300.75).
double? tryParseFiatAmount(String input) {
  final compact = input.trim().replaceAll("'", '').replaceAll(' ', '');
  if (compact.isEmpty) return null;

  // 105.000 / 1.000.000 / 90,000 — grouping only. The first group must not be
  // a leading zero (`0.105` is three fractional digits, not one hundred five).
  if (RegExp(r'^[1-9]\d{0,2}([.,]\d{3})+$').hasMatch(compact)) {
    return double.tryParse(compact.replaceAll(RegExp('[.,]'), ''));
  }

  // 300,75 / 300.75 / 0,5 — decimal with at most Rappen/cent precision.
  if (RegExp(r'^\d+[.,]\d{1,2}$').hasMatch(compact)) {
    return double.tryParse(compact.replaceAll(',', '.'));
  }

  if (RegExp(r'^\d+$').hasMatch(compact)) {
    return double.tryParse(compact);
  }

  return null;
}

/// Rappen-snapped major units the backend is asked to quote (e.g. `300,75` →
/// `300.75`). Never rounds to whole currency. Empty input counts as zero.
double chargedFiatAmount(String input) {
  final amount = tryParseFiatAmount(input.isEmpty ? '0' : input);
  if (amount == null) throw FormatException('Invalid fiat amount', input);
  return (amount * 100).round() / 100;
}
