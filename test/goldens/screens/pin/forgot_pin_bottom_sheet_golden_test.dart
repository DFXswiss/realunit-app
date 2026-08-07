import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/screens/pin/widgets/forgot_pin_bottom_sheet.dart';

import '../../../helper/helper.dart';

void main() {
  const phoneConstraints = BoxConstraints.tightFor(width: 390, height: 844);

  // Presented via showModalBottomSheet from the app-lock 'Forgot PIN?' action.
  // The sheet's buttons only call context.pop when tapped, so it renders fine
  // in a Scaffold's bottomSheet slot with a dark scrim — the same pattern as
  // biometric_prompt_sheet_golden_test.dart. The scrim stands in for the dimmed
  // PIN screen behind the real sheet.
  group('$ForgotPinBottomSheet', () {
    goldenTest(
      'default state with close and reset buttons',
      fileName: 'forgot_pin_bottom_sheet_default',
      constraints: phoneConstraints,
      builder: () => wrapForGolden(
        const Scaffold(
          backgroundColor: Colors.black54,
          bottomSheet: ForgotPinBottomSheet(),
        ),
      ),
    );
  });
}
