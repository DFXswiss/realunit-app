import 'package:flutter/services.dart';
import 'package:realunit_wallet/packages/utils/fiat_amount.dart';

/// Digits and separators only. A completed thousands group (`1.000` /
/// `1,000` / `1.000.000`) is rewritten to the integer; mixed thousands plus
/// decimal (`1.000,50` / `1,000.50`) keep the decimal; partials (`1.`,
/// `1.0`, `1.00`) stay as typed.
class FiatInputFormatter extends TextInputFormatter {
  const FiatInputFormatter();

  static final _allowedChars = FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'));

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final allowed = _allowedChars.formatEditUpdate(oldValue, newValue);
    final separator = strippedFiatGroupingSeparator(allowed.text);
    final normalized = normalizeFiatInput(allowed.text);
    if (normalized == allowed.text) return allowed;
    final cursor = allowed.selection.baseOffset.clamp(0, allowed.text.length);
    // Only separators actually dropped that sit before the caret. A global
    // length delta also subtracts separators behind it (typing `1` into
    // `.000,50` would move the caret to 0 instead of 1).
    var removedBefore = 0;
    if (separator != null) {
      for (var i = 0; i < cursor; i++) {
        if (allowed.text[i] == separator) removedBefore++;
      }
    }
    return TextEditingValue(
      text: normalized,
      selection: TextSelection.collapsed(
        offset: (cursor - removedBefore).clamp(0, normalized.length),
      ),
    );
  }
}
