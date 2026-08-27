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

    testWidgets('shows the required error for an empty prefix', (tester) async {
      final harness = await _pumpPhoneField(tester);

      await tester.enterText(_prefixField(), '');
      final isValid = harness.formKey.currentState!.validate();
      await tester.pump();

      expect(isValid, isFalse);
      expect(
        find.text(_phoneError(tester, (s) => s.registerPhoneNumberPrefixInvalid)),
        findsOneWidget,
      );
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

    // The client enforces basic format (non-empty + digits) and the explicit
    // CH/DE/AT trunk-zero canonicality invariant. All other phone validity,
    // including length and dial-code existence, remains backend-owned, so the
    // app accepts non-empty, digits-only national parts regardless of length
    // and lets the backend accept or reject them (CONTRIBUTING: "the API
    // decides"; the app must not block them pre-emptively). These cases guard
    // against a length gate being re-introduced.
    testWidgets('accepts a short +41 national number and defers the length to the API', (
      tester,
    ) async {
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

    testWidgets('strips a leading Swiss trunk zero from the national number', (tester) async {
      final harness = await _pumpPhoneField(tester);

      final isValid = await _enterAndValidate(tester, harness, '0791234567');

      expect(harness.controller.value, '+41791234567');
      expect(isValid, isTrue);
    });

    testWidgets('canonicalizes a Swiss number when the prefix contains extra digits', (
      tester,
    ) async {
      final harness = await _pumpPhoneField(tester);

      await tester.enterText(_prefixField(), '410');
      final isValid = await _enterAndValidate(tester, harness, '791234567');

      expect(harness.controller.value, '+41791234567');
      expect(isValid, isTrue);
    });

    testWidgets('canonicalizes a Swiss number when the national field contains the prefix digit', (
      tester,
    ) async {
      final harness = await _pumpPhoneField(tester);

      await tester.enterText(_prefixField(), '4');
      final isValid = await _enterAndValidate(tester, harness, '10791234567');

      expect(harness.controller.value, '+41791234567');
      expect(isValid, isTrue);
    });

    testWidgets('strips a leading German trunk zero from the national number', (tester) async {
      final harness = await _pumpPhoneField(tester, initialPhoneNumber: '+49');

      final isValid = await _enterAndValidate(tester, harness, '0691234567');

      expect(harness.controller.value, '+49691234567');
      expect(isValid, isTrue);
    });

    testWidgets('strips a leading Austrian trunk zero from the national number', (tester) async {
      final harness = await _pumpPhoneField(tester);

      await tester.enterText(_prefixField(), '43');
      final isValid = await _enterAndValidate(tester, harness, '06641234567');

      expect(harness.controller.value, '+436641234567');
      expect(isValid, isTrue);
    });

    testWidgets('keeps a leading Italian zero in the stored number', (tester) async {
      // For +39 the leading 0 is significant. Stripping it would make landlines
      // such as 0666982 invalid.
      final harness = await _pumpPhoneField(tester);

      await tester.enterText(_prefixField(), '39');
      final isValid = await _enterAndValidate(tester, harness, '0666982');

      expect(harness.controller.value, '+390666982');
      expect(isValid, isTrue);
    });

    testWidgets('keeps a leading Liechtenstein zero in the stored number', (tester) async {
      // Liechtenstein has no national trunk 0, so the entered leading zero
      // must remain part of the national number.
      final harness = await _pumpPhoneField(tester);

      await tester.enterText(_prefixField(), '423');
      final isValid = await _enterAndValidate(tester, harness, '0123456');

      expect(harness.controller.value, '+4230123456');
      expect(isValid, isTrue);
    });

    testWidgets('does not strip a zero that is not at the start of the national number', (
      tester,
    ) async {
      final harness = await _pumpPhoneField(tester);

      final isValid = await _enterAndValidate(tester, harness, '790123456');

      expect(harness.controller.value, '+41790123456');
      expect(isValid, isTrue);
    });

    testWidgets('rejects multiple leading trunk zeros', (tester) async {
      final harness = await _pumpPhoneField(tester);

      final isValid = await _enterAndValidate(tester, harness, '00791234567');

      expect(harness.controller.value, '+410791234567');
      expect(isValid, isFalse);
      expect(
        find.text(_phoneError(tester, (s) => s.registerPhoneNumberInvalid)),
        findsOneWidget,
      );
    });

    testWidgets('strips a leading trunk zero when the country prefix changes', (tester) async {
      final harness = await _pumpPhoneField(tester);
      await tester.enterText(_numberField(), '0791234567');
      await tester.pump();

      await tester.enterText(_prefixField(), '49');
      await tester.pump();

      expect(harness.controller.value, '+49791234567');
    });

    testWidgets('strips a leading trunk zero from a pre-filled value without user interaction', (
      tester,
    ) async {
      final harness = await _pumpPhoneField(tester, initialPhoneNumber: '+410791234567');
      await tester.pump();

      expect(harness.controller.value, '+41791234567');
    });

    testWidgets('rejects a pre-filled number with multiple leading trunk zeros', (
      tester,
    ) async {
      final harness = await _pumpPhoneField(tester, initialPhoneNumber: '+4100791234567');

      final isValid = harness.formKey.currentState!.validate();
      await tester.pump();

      expect(harness.controller.value, '+410791234567');
      expect(isValid, isFalse);
      expect(
        find.text(_phoneError(tester, (s) => s.registerPhoneNumberInvalid)),
        findsOneWidget,
      );
    });

    testWidgets('accepts a 9-digit +49 national number (valid per the API, not a length error)', (
      tester,
    ) async {
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

    testWidgets('does not accept more than 3 prefix digits', (tester) async {
      final harness = await _pumpPhoneField(tester);

      // LengthLimitingTextInputFormatter keeps the old value when the field is
      // already at maxLength and the incoming edit is longer (collapsed
      // selection). Clear first so '1234' is truncated to '123' rather than
      // rejected against a 3-digit seed.
      await tester.enterText(_prefixField(), '');
      await tester.enterText(_prefixField(), '1234');
      await tester.enterText(_numberField(), '791234567');
      await tester.pump();

      final prefixEditable = tester.widget<EditableText>(
        find.descendant(of: _prefixField(), matching: find.byType(EditableText)),
      );
      expect(prefixEditable.controller.text, '123');
      expect(harness.controller.value, '+123791234567');
    });

    testWidgets('accepts a 3-digit prefix and composes the stored number', (tester) async {
      final harness = await _pumpPhoneField(tester);

      await tester.enterText(_prefixField(), '423');
      final isValid = await _enterAndValidate(tester, harness, '6641234567');

      expect(harness.controller.value, '+4236641234567');
      expect(isValid, isTrue);
    });

    testWidgets('decomposes a seeded +423 number without letting +43 eat it', (tester) async {
      await _pumpPhoneField(tester, initialPhoneNumber: '+4236641234567');

      final prefixEditable = tester.widget<EditableText>(
        find.descendant(of: _prefixField(), matching: find.byType(EditableText)),
      );
      final numberEditable = tester.widget<EditableText>(
        find.descendant(of: _numberField(), matching: find.byType(EditableText)),
      );
      expect(prefixEditable.controller.text, '423');
      expect(numberEditable.controller.text, '6641234567');
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
