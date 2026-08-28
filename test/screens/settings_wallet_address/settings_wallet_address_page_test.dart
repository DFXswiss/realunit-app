import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/screens/receive/receive_page.dart';
import 'package:realunit_wallet/screens/receive/widgets/qr_address_widget.dart';
import 'package:realunit_wallet/screens/settings_wallet_address/settings_wallet_address_page.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';

import '../../helper/helper.dart';

void main() {
  final AppStore appStore = MockAppStore();

  setUpAll(() {
    GetIt.instance.registerSingleton<AppStore>(appStore);
  });

  setUp(() {
    when(() => appStore.primaryAddress)
        .thenReturn('0x938115b533a0b746428361760a6972dfd06d984a');
  });

  tearDownAll(() async {
    await GetIt.instance.reset();
  });

  group('$SettingsWalletAddressPage', () {
    testWidgets('builds ReceivePage with QR and Send', (tester) async {
      await tester.pumpApp(const SettingsWalletAddressPage());

      expect(find.byType(ReceivePage), findsOneWidget);
      expect(find.byType(QRAddressWidget), findsOneWidget);
      expect(
        find.widgetWithText(AppFilledButton, S.current.send),
        findsOneWidget,
      );
      expect(find.text(S.current.walletAddressDisclaimer), findsNothing);
    });
  });
}
