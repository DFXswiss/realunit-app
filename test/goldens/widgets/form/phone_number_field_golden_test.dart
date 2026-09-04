import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/widgets/form/phone_number_field.dart';

import '../../../helper/helper.dart';

Widget _leadingZeroErrorField(GlobalKey<FormState> formKey, {Locale locale = const Locale('de')}) {
  return wrapForGolden(
    Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: formKey,
          child: PhoneNumberField(
            controller: ValueNotifier<String?>('+4100791234567'),
          ),
        ),
      ),
    ),
    locale: locale,
  );
}

Future<void> _validateThenSettle(WidgetTester tester, GlobalKey<FormState> formKey) async {
  await tester.pumpAndSettle();
  formKey.currentState!.validate();
  await tester.pumpAndSettle();
}

void main() {
  group('$PhoneNumberField', () {
    goldenTest(
      'default empty phone number field',
      fileName: 'phone_number_field_default',
      constraints: phoneConstraints,
      builder: () => wrapForGolden(
        Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: PhoneNumberField(
              controller: ValueNotifier<String?>(null),
            ),
          ),
        ),
      ),
    );

    // Pins the only error state this PR adds; an earlier wording of the
    // message overflowed the field's single error line.
    // Alchemist's wrapper pushes a MaterialPageRoute; the default
    // pumpBeforeTest (precacheImages) settles it. Replacing that default with
    // validate() plus a single pump() runs Form.validate() before FormField.build
    // has registered the fields, so _fields is empty and the error never paints.
    final deErrorKey = GlobalKey<FormState>();
    goldenTest(
      'leading-zero error phone number field',
      fileName: 'phone_number_field_leading_zero_error',
      constraints: phoneConstraints,
      pumpBeforeTest: (tester) => _validateThenSettle(tester, deErrorKey),
      builder: () => _leadingZeroErrorField(deErrorKey),
    );

    final enErrorKey = GlobalKey<FormState>();
    goldenTest(
      'leading-zero error phone number field in English',
      fileName: 'phone_number_field_leading_zero_error_en',
      constraints: phoneConstraints,
      pumpBeforeTest: (tester) => _validateThenSettle(tester, enErrorKey),
      builder: () => _leadingZeroErrorField(enErrorKey, locale: const Locale('en')),
    );
  });
}
