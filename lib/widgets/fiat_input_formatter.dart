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
    final normalized = normalizeFiatInput(allowed.text);
    if (normalized == allowed.text) return allowed;
    final cursor = allowed.selection.baseOffset.clamp(0, allowed.text.length);
    // Mixed thousands + decimal (`1.000,50` → `1000,50`) drops only the
    // thousands separator. Counting every [.,] before the cursor subtracted
    // the kept decimal too and placed the caret one place too early.
    final removed = allowed.text.length - normalized.length;
    return TextEditingValue(
      text: normalized,
      selection: TextSelection.collapsed(
        offset: (cursor - removed).clamp(0, normalized.length),
      ),
    );
  }
}
