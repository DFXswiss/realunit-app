import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/widgets/form/phone_number_field.dart';

import '../../helper/pump_app.dart';

class _PhoneFieldHarness {
  _PhoneFieldHarness({
    required this.formKey,
    required this.controller,
  });

  final GlobalKey<FormState> formKey;
  final ValueNotifier<String?> controller;
}

Future<_PhoneFieldHarness> _pumpPhoneField(
  WidgetTester tester, {
  String? initialPhoneNumber,
}) async {
  final formKey = GlobalKey<FormState>();
  final controller = ValueNotifier<String?>(initialPhoneNumber);
  addTearDown(controller.dispose);

  await tester.pumpApp(
    Scaffold(
      body: Form(
        key: formKey,
        child: PhoneNumberField(controller: controller),
      ),
    ),
  );

  return _PhoneFieldHarness(formKey: formKey, controller: controller);
}

Finder _prefixField() => find.byType(TextFormField).first;

Finder _numberField() => find.byType(TextFormField).at(1);

Future<bool> _enterAndValidate(
  WidgetTester tester,
  _PhoneFieldHarness harness,
  String nationalNumber,
) async {
  await tester.enterText(_numberField(), nationalNumber);

  final isValid = harness.formKey.currentState!.validate();
  await tester.pump();
  return isValid;
}

String _phoneError(WidgetTester tester, String Function(S localizations) message) {
  final context = tester.element(find.byType(PhoneNumberField));
  return message(S.of(context));
}

void main() {
  group('$PhoneNumberField', () {
    testWidgets('shows the required error for empty input', (tester) async {
      final harness = await _pumpPhoneField(tester);

      final isValid = harness.formKey.currentState!.validate();
      await tester.pump();

      expect(isValid, isFalse);
      expect(
        find.text(_phoneError(tester, (s) => s.registerPhoneNumberInvalid)),
        findsOneWidget,
      );
      expect(harness.controller.value, isNull);
    });

    testWidgets('shows the digits-only error for non-digit input', (tester) async {
      final harness = await _pumpPhoneField(tester);

      final isValid = await _enterAndValidate(tester, harness, '79abc4567');

      expect(isValid, isFalse);
      expect(
        find.text(_phoneError(tester, (s) => s.registerPhoneNumberOnlyDigits)),
        findsOneWidget,
      );
    });

    // The client performs format hygiene only (non-empty + digits). It must not
    // gate on length: the API validates the number with libphonenumber, so the
    // app accepts any non-empty, digits-only national part regardless of length
    // and lets the backend accept or reject it (CONTRIBUTING: "the API decides…
    // the app must not block it pre-emptively"). These cases guard against a
    // length gate being re-introduced.
    testWidgets('accepts a short +41 national number and defers the length to the API',
        (tester) async {
      final harness = await _pumpPhoneField(tester);

      final isValid = await _enterAndValidate(tester, harness, '12345');

      expect(harness.controller.value, '+4112345');
      expect(isValid, isTrue);
    });

    testWidgets('accepts a full-length Swiss national number', (tester) async {
      final harness = await _pumpPhoneField(tester);

      final isValid = await _enterAndValidate(tester, harness, '791234567');

      expect(harness.controller.value, '+41791234567');
      expect(isValid, isTrue);
    });

    testWidgets('accepts a 9-digit +49 national number (valid per the API, not a length error)',
        (tester) async {
      // A 9-digit German national number (e.g. a Frankfurt landline, 069 …) is
      // valid for libphonenumber; the client must not reject it on length.
      final harness = await _pumpPhoneField(tester, initialPhoneNumber: '+49');

      final isValid = await _enterAndValidate(tester, harness, '691234567');

      expect(harness.controller.value, '+49691234567');
      expect(isValid, isTrue);
    });

    testWidgets('accepts a non-CH/DE prefix and composes the stored number', (tester) async {
      final harness = await _pumpPhoneField(tester);

      await tester.enterText(_prefixField(), '43');
      final isValid = await _enterAndValidate(tester, harness, '12345');

      expect(harness.controller.value, '+4312345');
      expect(isValid, isTrue);
    });

    testWidgets('switching the country prefix recomposes the stored number', (tester) async {
      final harness = await _pumpPhoneField(tester, initialPhoneNumber: '+41791234567');

      await tester.enterText(_prefixField(), '49');
      await tester.pump();

      expect(harness.controller.value, '+49791234567');
    });

    testWidgets('does not accept more than 2 prefix digits', (tester) async {
      final harness = await _pumpPhoneField(tester);

      // LengthLimitingTextInputFormatter keeps the old value when the field is
      // already at maxLength and the incoming edit is longer (collapsed
      // selection). Clear first so '123' is truncated to '12' rather than
      // rejected against the seeded '41'.
      await tester.enterText(_prefixField(), '');
      await tester.enterText(_prefixField(), '123');
      await tester.enterText(_numberField(), '791234567');
      await tester.pump();

      final prefixEditable = tester.widget<EditableText>(
        find.descendant(of: _prefixField(), matching: find.byType(EditableText)),
      );
      expect(prefixEditable.controller.text, '12');
      expect(harness.controller.value, '+12791234567');
    });

    testWidgets('shows the format error for a 1-digit prefix', (tester) async {
      final harness = await _pumpPhoneField(tester);

      await tester.enterText(_prefixField(), '4');
      final isValid = harness.formKey.currentState!.validate();
      await tester.pump();

      expect(isValid, isFalse);
      expect(
        find.text(_phoneError(tester, (s) => s.registerPhoneNumberPrefixFormat)),
        findsOneWidget,
      );
    });

    testWidgets('keeps + out of the prefix field text and on prefixText', (tester) async {
      final harness = await _pumpPhoneField(tester);

      await tester.enterText(_prefixField(), '41');
      await tester.enterText(_numberField(), '791234567');
      await tester.pump();

      expect(harness.controller.value, '+41791234567');
      expect(find.text('+41'), findsNothing);
      final prefixTextField = tester.widget<TextField>(
        find.descendant(of: _prefixField(), matching: find.byType(TextField)),
      );
      expect(prefixTextField.decoration?.prefixText, '+');
    });
  });
}
