import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/widgets/form/phone_number_field.dart';

import '../../../helper/helper.dart';

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

    // This is the longest message the field displays.
    // Alchemist's wrapper pushes a MaterialPageRoute; the default
    // pumpBeforeTest (precacheImages) settles it. Replacing that default with
    // validate() plus a single pump() runs Form.validate() before FormField.build
    // has registered the fields, so _fields is empty and the error never paints.
    final formKey = GlobalKey<FormState>();
    goldenTest(
      'leading-zero error phone number field',
      fileName: 'phone_number_field_leading_zero_error',
      constraints: phoneConstraints,
      pumpBeforeTest: (tester) async {
        await tester.pumpAndSettle();
        formKey.currentState!.validate();
        await tester.pumpAndSettle();
      },
      builder: () => wrapForGolden(
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
      ),
    );
  });
}
