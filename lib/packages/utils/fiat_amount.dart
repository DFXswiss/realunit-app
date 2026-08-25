/// Parses user-typed fiat text for CHF/EUR (at most two decimal places).
///
/// Swiss apostrophes and spaces are thousands marks. A single `.` or `,`
/// followed by exactly three digits is a thousands group (`105.000` /
/// `90,000` → 105000 / 90000), not a 3-decimal fraction — quoting that as
/// 105.0 would silently buy a thousandth of the intended amount. One or two
/// digits after the separator stay a decimal (`300,75` → 300.75).
double? tryParseFiatAmount(String input) {
  final trimmed = input.trim().replaceAll(' ', '');
  if (trimmed.isEmpty) return null;

  // Swiss apostrophes are thousands marks only (`90'000`, `105'000.50`).
  // Strip them only after the grouping shape is valid — otherwise `0'105`
  // becomes `0105` → 105 and `1'23` becomes 123.
  if (trimmed.contains("'")) {
    if (!RegExp(r"^[1-9]\d{0,2}('\d{3})+([.,]\d{1,2})?$").hasMatch(trimmed)) {
      return null;
    }
    return tryParseFiatAmount(trimmed.replaceAll("'", ''));
  }

  // 105.000 / 1,000,000 — same separator throughout. First group has no
  // leading zero (`0.105` is three fractional digits, not one hundred five).
  if (RegExp(r'^[1-9]\d{0,2}([.,])(\d{3}(?:\1\d{3})*)$').hasMatch(trimmed)) {
    return double.tryParse(trimmed.replaceAll(RegExp('[.,]'), ''));
  }

  // 300,75 / 300.75 / 0,5 — decimal with at most Rappen/cent precision.
  // Optional leading minus keeps the sell-cubit contract (`-100` is still
  // parsed; the UI digitsOnly formatter already prevents typing it).
  if (RegExp(r'^-?\d+[.,]\d{1,2}$').hasMatch(trimmed)) {
    return double.tryParse(trimmed.replaceAll(',', '.'));
  }

  if (RegExp(r'^-?\d+$').hasMatch(trimmed)) {
    return double.tryParse(trimmed);
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
