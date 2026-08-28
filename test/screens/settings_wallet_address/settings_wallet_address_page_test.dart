import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/screens/receive/widgets/qr_address_widget.dart';
import 'package:realunit_wallet/screens/settings_wallet_address/settings_wallet_address_page.dart';
import 'package:realunit_wallet/setup/routing/routes/app_routes.dart';
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

  Finder sendButton() => find.widgetWithText(AppFilledButton, S.current.send);

  group('$SettingsWalletAddressPage', () {
    testWidgets('renders logo, QR, disclaimer and Send', (tester) async {
      await tester.pumpApp(const SettingsWalletAddressPage());

      expect(find.byType(SvgPicture), findsOneWidget);
      expect(find.byType(QRAddressWidget), findsOneWidget);
      expect(find.text(S.current.walletAddressDisclaimer), findsOneWidget);
      expect(sendButton(), findsOneWidget);
    });

    testWidgets('QR uses EIP-55 checksummed address', (tester) async {
      await tester.pumpApp(const SettingsWalletAddressPage());

      final qr = tester.widget<QRAddressWidget>(find.byType(QRAddressWidget));
      expect(qr.subtitle, '0x938115B533a0b746428361760A6972dfd06D984a');
      expect(qr.uri, 'ethereum:0x938115B533a0b746428361760A6972dfd06D984a');
    });

    testWidgets('tapping Send pushes the send route', (tester) async {
      final pushedRoutes = <String>[];
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const SettingsWalletAddressPage(),
          ),
          GoRoute(
            name: AppRoutes.send,
            path: '/send',
            builder: (_, _) {
              pushedRoutes.add(AppRoutes.send);
              return const Scaffold(body: Text('ROUTE:send'));
            },
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: const [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
          ],
          supportedLocales: S.delegate.supportedLocales,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      expect(pushedRoutes, [AppRoutes.send]);
    });
  });
}
