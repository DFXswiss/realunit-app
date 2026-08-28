import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/screens/pay/pay_info_page.dart';
import 'package:realunit_wallet/screens/pay/pay_scan_page.dart';

import '../../helper/helper.dart';

void main() {
  setUpAll(stubMobileScannerChannel);

  group('$PayInfoPage', () {
    testWidgets('shows the OpenCryptoPay exchange disclosure', (tester) async {
      await tester.pumpApp(const PayInfoPage());

      expect(find.text(S.current.payInfoTitle), findsOneWidget);
      expect(find.text(S.current.payInfoBody), findsOneWidget);
      expect(find.text(S.current.next), findsOneWidget);
    });

    testWidgets('continues to the scanner with the initial payload', (tester) async {
      const initialPayload = 'payload-from-deeplink';
      await tester.pumpApp(const PayInfoPage(initialPayload: initialPayload));

      await tester.tap(find.text(S.current.next));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final page = tester.widget<PayScanPage>(find.byType(PayScanPage));
      expect(page.initialPayload, initialPayload);
    });
  });
}
