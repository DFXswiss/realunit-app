import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/screens/receive/widgets/qr_address_widget.dart';
import 'package:realunit_wallet/screens/settings_wallet_address/settings_wallet_address_page.dart';

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
    testWidgets('renders initially correctly', (tester) async {
      await tester.pumpApp(const SettingsWalletAddressPage());

      expect(find.byType(SvgPicture), findsOneWidget);
      expect(find.byType(QRAddressWidget), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Text && widget.data == S.current.walletAddressDisclaimer,
        ),
        findsOneWidget,
      );
    });

    testWidgets('displays the address in EIP-55 checksummed form', (tester) async {
      await tester.pumpApp(const SettingsWalletAddressPage());

      const checksummed = '0x938115B533a0b746428361760A6972dfd06D984a';
      final qr = tester.widget<QRAddressWidget>(find.byType(QRAddressWidget));
      expect(qr.subtitle, checksummed);
      expect(qr.uri, contains(checksummed));
    });
  });
}
