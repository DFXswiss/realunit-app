BigInt parseFixed(String value, int? decimals) {
  decimals ??= 0;
  
  // Input validation: empty string
  if (value.isEmpty) {
    throw Exception('empty input');
  }
  
  // Check for lone minus or invalid starting characters
  if (value == '-') {
    throw Exception('lone minus sign');
  }
  
  // Check for leading dot (invalid)
  if (value.startsWith('.')) {
    throw Exception('leading dot not allowed');
  }
  
  // Check for invalid characters (non-numeric except minus and dot)
  final validPattern = RegExp(r'^-?[0-9]+(\.[0-9]*)?$');
  if (!validPattern.hasMatch(value)) {
    throw Exception('invalid input format');
  }

  // Is it negative?
  final negative = value.startsWith('-');
  var cleanValue = negative ? value.substring(1) : value;
  
  // Handle empty after removing sign (shouldn't happen due to earlier checks, but safety)
  if (cleanValue.isEmpty || cleanValue == '.') {
    throw Exception('invalid input after sign removal');
  }

  // Split it into a whole and fractional part
  final comps = cleanValue.split('.');
  if (comps.length > 2) {
    throw Exception('too many decimal points, value: $value');
  }

  var whole = comps[0];
  
  // Handle case where there's no fractional part but has trailing dot
  var fraction = '';
  if (comps.length == 2) {
    fraction = comps[1];
  }
  
  // If no fractional part, pad with zeros to match decimals
  if (fraction.isEmpty) {
    fraction = '0'.padRight(decimals, '0');
  } else {
    // Pad right with zeros up to decimals length
    fraction = fraction.padRight(decimals, '0');
    
    // Check if fractional part exceeds the allowed decimals
    if (fraction.length > decimals) {
      throw Exception('fractional component exceeds decimals, value: $value');
    }
  }

  final multiplier = getMultiplier(decimals);

  // Validate whole and fraction are not empty after processing
  if (whole.isEmpty || whole == '.') {
    throw Exception('invalid whole part');
  }

  try {
    final wholeValue = BigInt.parse(whole);
    final fractionValue = BigInt.parse(fraction);
    final multiplierValue = BigInt.parse(multiplier);

    var wei = (wholeValue * multiplierValue) + fractionValue;

    if (negative) wei *= BigInt.from(-1);

    return wei;
  } on FormatException {
    throw Exception('invalid numeric format');
  }
}

// Returns a string "1" followed by decimal "0"s
String getMultiplier(int decimals) => '1'.padRight(decimals + 1, '0');
