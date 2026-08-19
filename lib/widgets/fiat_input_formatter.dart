import 'package:flutter/services.dart';
import 'package:realunit_wallet/packages/utils/fiat_amount.dart';

/// Digits and separators only. A completed thousands group (`1.000` / `1,000`)
/// is rewritten to the integer; partials (`1.`, `1.0`, `1.00`) stay as typed.
class FiatInputFormatter extends TextInputFormatter {
  const FiatInputFormatter();

  static final _allowedChars = FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'));

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final allowed = _allowedChars.formatEditUpdate(oldValue, newValue);
    final normalized = normalizeFiatInput(allowed.text);
    if (normalized == allowed.text) return allowed;
    return TextEditingValue(
      text: normalized,
      selection: TextSelection.collapsed(offset: normalized.length),
    );
  }
}
