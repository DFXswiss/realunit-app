import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/screens/send/send_info_page.dart';
import 'package:realunit_wallet/screens/send/send_recipient_page.dart';

import '../../helper/helper.dart';

void main() {
  setUpAll(stubMobileScannerChannel);

  group('$SendInfoPage', () {
    testWidgets('shows the shareholder transfer disclosure', (tester) async {
      await tester.pumpApp(const SendInfoPage());

      expect(find.text(S.current.sendInfoTitle), findsOneWidget);
      expect(find.text(S.current.sendInfoBody), findsOneWidget);
      expect(find.text(S.current.next), findsOneWidget);
    });

    testWidgets('continues to the recipient scanner', (tester) async {
      await tester.pumpApp(const SendInfoPage());

      await tester.tap(find.text(S.current.next));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(SendRecipientPage), findsOneWidget);
    });
  });
}
