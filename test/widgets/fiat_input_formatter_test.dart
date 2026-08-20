import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/widgets/fiat_input_formatter.dart';

void main() {
  const formatter = FiatInputFormatter();

  TextEditingValue update(TextEditingValue oldValue, TextEditingValue newValue) =>
      formatter.formatEditUpdate(oldValue, newValue);

  group('$FiatInputFormatter.formatEditUpdate', () {
    test('rewrites a one-step paste of 1.000.000 to 1000000', () {
      final out = update(
        TextEditingValue.empty,
        const TextEditingValue(
          text: '1.000.000',
          selection: TextSelection.collapsed(offset: 9),
        ),
      );
      expect(out.text, '1000000');
      expect(out.selection, const TextSelection.collapsed(offset: 7));
    });

    test('rewrites a one-step paste of 1,000,000 to 1000000', () {
      final out = update(
        TextEditingValue.empty,
        const TextEditingValue(
          text: '1,000,000',
          selection: TextSelection.collapsed(offset: 9),
        ),
      );
      expect(out.text, '1000000');
      expect(out.selection, const TextSelection.collapsed(offset: 7));
    });

    test('keeps the caret at the end when a thousands group is completed at the end', () {
      final out = update(
        const TextEditingValue(
          text: '1.00',
          selection: TextSelection.collapsed(offset: 4),
        ),
        const TextEditingValue(
          text: '1.000',
          selection: TextSelection.collapsed(offset: 5),
        ),
      );
      expect(out.text, '1000');
      expect(out.selection, const TextSelection.collapsed(offset: 4));
    });

    test('keeps the caret relative to the edit when a thousands group is stripped mid-text', () {
      // Insert '.' after '1' in '1000' → '1.000' → '1000', caret stays after '1'.
      final out = update(
        const TextEditingValue(
          text: '1000',
          selection: TextSelection.collapsed(offset: 1),
        ),
        const TextEditingValue(
          text: '1.000',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      expect(out.text, '1000');
      expect(out.selection, const TextSelection.collapsed(offset: 1));
    });
  });
}
