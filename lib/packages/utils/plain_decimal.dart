/// Exact comparison of plain (non-scientific) decimal number strings via
/// [BigInt], without floating-point conversion. Dependency-free (`dart:core`
/// only) — used where money amounts must be ordered without binary-double drift.
///
/// Accepts an optional leading `+`/`-`, an integer part, an optional fractional
/// part, and nothing else. Scientific notation (`1e3`, `1E-2`) and any other
/// malformed input throw [FormatException] — fail closed, never coerced.
library;

/// Returns a negative value if [a] < [b], zero if equal, positive if [a] > [b].
int comparePlainDecimalStrings(String a, String b) {
  final parsedA = _parsePlainDecimal(a);
  final parsedB = _parsePlainDecimal(b);

  // Different signs: negative is always smaller (and -0 == +0 is handled below
  // once both sides are scaled to integer magnitude).
  if (parsedA.negative != parsedB.negative) {
    final aZero = parsedA.integerDigits == '0' && parsedA.fractionDigits.isEmpty;
    final bZero = parsedB.integerDigits == '0' && parsedB.fractionDigits.isEmpty;
    if (aZero && bZero) return 0;
    return parsedA.negative ? -1 : 1;
  }

  final scale = parsedA.fractionDigits.length > parsedB.fractionDigits.length
      ? parsedA.fractionDigits.length
      : parsedB.fractionDigits.length;
  final scaledA = _toScaledInteger(parsedA, scale);
  final scaledB = _toScaledInteger(parsedB, scale);

  final cmp = scaledA.compareTo(scaledB);
  // Same sign: if both negative, the larger magnitude is the smaller number.
  return parsedA.negative ? -cmp : cmp;
}

({bool negative, String integerDigits, String fractionDigits}) _parsePlainDecimal(
  String raw,
) {
  var s = raw.trim();
  if (s.isEmpty) {
    throw FormatException('plain decimal is empty: $raw');
  }
  // Reject scientific notation and any non-decimal characters up front.
  if (s.contains('e') || s.contains('E')) {
    throw FormatException('plain decimal must not use scientific notation: $raw');
  }

  var negative = false;
  if (s.startsWith('-')) {
    negative = true;
    s = s.substring(1);
  } else if (s.startsWith('+')) {
    s = s.substring(1);
  }
  if (s.isEmpty) {
    throw FormatException('plain decimal has no digits: $raw');
  }

  final parts = s.split('.');
  if (parts.length > 2) {
    throw FormatException('plain decimal has too many decimal points: $raw');
  }
  final integerPart = parts[0];
  final fractionPart = parts.length == 2 ? parts[1] : '';

  // Integer part may be empty only when a fraction is present (".5"); fraction
  // may be empty ("42." / "42"). At least one side must carry a digit.
  if (integerPart.isEmpty && fractionPart.isEmpty) {
    throw FormatException('plain decimal has no digits: $raw');
  }
  if (integerPart.isNotEmpty && !_isAllDigits(integerPart)) {
    throw FormatException('plain decimal has non-digit characters: $raw');
  }
  if (fractionPart.isNotEmpty && !_isAllDigits(fractionPart)) {
    throw FormatException('plain decimal has non-digit characters: $raw');
  }

  // Normalize integer digits: strip leading zeros but keep a single "0" when
  // the integer magnitude is zero (including ".5" → integer "0").
  final integerDigits = integerPart.isEmpty
      ? '0'
      : (BigInt.parse(integerPart).toString()); // drops leading zeros
  // Strip trailing zeros from the fraction so "1.50" and "1.5" compare equal
  // without needing a shared scale for zero-equality of the fractional tail.
  final fractionDigits = _stripTrailingZeros(fractionPart);

  // -0 and +0: treat as non-negative zero so sign handling above is clean.
  if (integerDigits == '0' && fractionDigits.isEmpty) {
    return (negative: false, integerDigits: '0', fractionDigits: '');
  }

  return (
    negative: negative,
    integerDigits: integerDigits,
    fractionDigits: fractionDigits,
  );
}

BigInt _toScaledInteger(
  ({bool negative, String integerDigits, String fractionDigits}) parsed,
  int scale,
) {
  final fraction = parsed.fractionDigits.padRight(scale, '0');
  final combined = '${parsed.integerDigits}$fraction';
  // combined is digits-only (possibly empty only if both parts empty — already
  // rejected). BigInt.parse('0' * n) is fine; empty cannot happen here.
  return BigInt.parse(combined.isEmpty ? '0' : combined);
}

bool _isAllDigits(String s) {
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c < 0x30 || c > 0x39) return false;
  }
  return true;
}

String _stripTrailingZeros(String fraction) {
  if (fraction.isEmpty) return fraction;
  var end = fraction.length;
  while (end > 0 && fraction.codeUnitAt(end - 1) == 0x30) {
    end--;
  }
  return fraction.substring(0, end);
}
