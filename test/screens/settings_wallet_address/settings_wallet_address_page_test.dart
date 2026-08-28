import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_svg/svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/screens/receive/widgets/qr_address_widget.dart';
import 'package:realunit_wallet/screens/settings/bloc/settings_bloc.dart';
import 'package:realunit_wallet/screens/settings_wallet_address/settings_wallet_address_page.dart';
import 'package:realunit_wallet/setup/routing/routes/app_routes.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';

import '../../helper/helper.dart';

void main() {
  final AppStore appStore = MockAppStore();
  late MockSettingsBloc settingsBloc;

  setUpAll(() {
    GetIt.instance.registerSingleton<AppStore>(appStore);
  });

  setUp(() {
    when(() => appStore.primaryAddress)
        .thenReturn('0x938115b533a0b746428361760a6972dfd06d984a');
    settingsBloc = MockSettingsBloc();
  });

  tearDownAll(() async {
    await GetIt.instance.reset();
  });

  Future<void> pumpPage(WidgetTester tester, SettingsState state) async {
    when(() => settingsBloc.state).thenReturn(state);
    await tester.pumpApp(
      BlocProvider<SettingsBloc>.value(
        value: settingsBloc,
        child: const SettingsWalletAddressPage(),
      ),
    );
  }

  Finder sendButton() => find.widgetWithText(AppFilledButton, S.current.send);

  group('$SettingsWalletAddressPage', () {
    group('locked (default)', () {
      testWidgets('renders initially correctly', (tester) async {
        await pumpPage(tester, const SettingsState());

        expect(find.byType(SvgPicture), findsOneWidget);
        expect(find.byType(QRAddressWidget), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Text && widget.data == S.current.walletAddressDisclaimer,
          ),
          findsOneWidget,
        );
        expect(sendButton(), findsNothing);
      });

      testWidgets('displays the address in EIP-55 checksummed form', (tester) async {
        await pumpPage(tester, const SettingsState());

        const checksummed = '0x938115B533a0b746428361760A6972dfd06D984a';
        final qr = tester.widget<QRAddressWidget>(find.byType(QRAddressWidget));
        expect(qr.subtitle, checksummed);
        expect(qr.uri, contains(checksummed));
        expect(sendButton(), findsNothing);
      });
    });

    group('unlocked', () {
      testWidgets('shows the Send button', (tester) async {
        await pumpPage(
          tester,
          const SettingsState(insiderFeaturesUnlocked: true),
        );

        expect(sendButton(), findsOneWidget);
      });

      testWidgets('tapping Send pushes the send route', (tester) async {
        when(() => settingsBloc.state)
            .thenReturn(const SettingsState(insiderFeaturesUnlocked: true));
        final pushedRoutes = <String>[];
        final router = GoRouter(
          initialLocation: '/',
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => BlocProvider<SettingsBloc>.value(
                value: settingsBloc,
                child: const SettingsWalletAddressPage(),
              ),
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
  });
}
