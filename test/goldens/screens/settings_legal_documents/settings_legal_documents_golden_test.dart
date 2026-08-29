import 'package:alchemist/alchemist.dart' as alchemist;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/screens/settings_legal_documents/settings_legal_documents_page.dart';

import '../../../helper/helper.dart';

void main() {

  group('$SettingsLegalDocumentsPage', () {
    goldenTest(
      'default state',
      fileName: 'settings_legal_documents_page_default',
      constraints: phoneConstraints,
      builder: () => wrapForGolden(const SettingsLegalDocumentsPage()),
    );

    goldenTest(
      'scrolled to referral terms tile',
      fileName: 'settings_legal_documents_page_referral_terms',
      constraints: phoneConstraints,
      pumpBeforeTest: (tester) async {
        await alchemist.precacheImages(tester);
        await tester.ensureVisible(
          find.byKey(const Key('settings-referral-terms')),
        );
        await tester.pumpAndSettle();
      },
      builder: () => wrapForGolden(const SettingsLegalDocumentsPage()),
    );
  });
}
