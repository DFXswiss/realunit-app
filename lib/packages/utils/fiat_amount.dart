/// Parses user-typed fiat text, accepting a comma as the decimal separator.
/// Rejects grouping-ambiguous input — a lone separator followed by exactly
/// three digits (`1,000` / `1.000`) usually means a thousands group, and
/// reading it as a decimal would quote 1/1000th of the intended amount.
double? tryParseFiatAmount(String input) {
  if (RegExp(r'^\d+[.,]\d{3}$').hasMatch(input)) return null;
  return double.tryParse(input.replaceAll(',', '.'));
}

/// Rappen-snapped major units the backend is asked to quote (e.g. `300,75` →
/// `300.75`). Never rounds to whole currency. Empty input counts as zero.
double chargedFiatAmount(String input) {
  final amount = tryParseFiatAmount(input.isEmpty ? '0' : input);
  if (amount == null) throw FormatException('Invalid fiat amount', input);
  return (amount * 100).round() / 100;
}
