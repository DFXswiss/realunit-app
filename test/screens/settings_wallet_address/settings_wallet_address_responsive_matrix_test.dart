import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/screens/settings_wallet_address/settings_wallet_address_page.dart';
import 'package:realunit_wallet/setup/routing/routes/app_routes.dart';
import 'package:realunit_wallet/styles/themes.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';

import '../../helper/helper.dart';

Future<void> _pumpScreen(
  WidgetTester tester,
  MatrixCell cell,
  Widget child,
) async {
  await tester.binding.setSurfaceSize(cell.mediaQuery.size);
  addTearDown(() async => tester.binding.setSurfaceSize(null));
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => child,
      ),
      GoRoute(
        name: AppRoutes.send,
        path: '/send',
        builder: (_, _) => const Scaffold(body: Text('ROUTE:send')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    MediaQuery(
      data: cell.mediaQuery,
      child: MaterialApp.router(
        theme: realUnitTheme,
        locale: const Locale('de'),
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

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

  group('SettingsWalletAddressPage responsive matrix', () {
    for (final cell in kFullResponsiveMatrix) {
      testWidgets(cell.id, (tester) async {
        await withTargetPlatform(cell.device.platform, () async {
          await expectNoLayoutOverflow(
            tester,
            () => _pumpScreen(
              tester,
              cell,
              const SettingsWalletAddressPage(),
            ),
            reason: 'SettingsWalletAddressPage overflow / ${cell.label}',
          );

          await expectFullyTappable(
            tester,
            find.widgetWithText(AppFilledButton, S.current.send),
            within: find.byType(SettingsWalletAddressPage),
            reason:
                'SettingsWalletAddressPage / ${cell.label}: Send CTA not tappable',
          );
        });
      });
    }
  });
}
