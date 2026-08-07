import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/config/api_config.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_transfer_service.dart';
import 'package:realunit_wallet/packages/utils/default_assets.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';
import 'package:realunit_wallet/screens/send/send_confirm_page.dart';
import 'package:realunit_wallet/screens/send/send_process_page.dart';

import '../../helper/helper.dart';

class _MockTransferService extends Mock implements RealUnitTransferService {}

class _MockAppStore extends Mock implements AppStore {}

class _MockApiConfig extends Mock implements ApiConfig {}

class _MockWallet extends Mock implements SoftwareWallet {}

void main() {
  setUpAll(() {
    // The confirm button pushes SendProcessPage, which builds a cubit off getIt
    // and calls start(). A debug wallet makes start() settle immediately without
    // any network call.
    final getIt = GetIt.instance;
    getIt.registerSingleton<RealUnitTransferService>(_MockTransferService());
    final appStore = _MockAppStore();
    final apiConfig = _MockApiConfig();
    when(() => apiConfig.asset).thenReturn(realUnitAsset);
    final wallet = _MockWallet();
    when(() => wallet.walletType).thenReturn(WalletType.debug);
    when(() => appStore.wallet).thenReturn(wallet);
    when(() => appStore.apiConfig).thenReturn(apiConfig);
    getIt.registerSingleton<AppStore>(appStore);
  });

  tearDownAll(() async => GetIt.instance.reset());

  group('$SendConfirmPage', () {
    testWidgets('renders the recipient + amount summary', (tester) async {
      await tester.pumpApp(
        const SendConfirmPage(
          recipient: '0x9F5713dEAcb8e9CaB6c2D3FaE1aFc2715F8D2D71',
          amount: 5,
        ),
      );

      expect(find.text(S.current.sendConfirmTitle), findsOne);
      expect(find.text(S.current.sendConfirmSummary('5')), findsOne);
      expect(find.text('0x9F5713dEAcb8e9CaB6c2D3FaE1aFc2715F8D2D71'), findsOne);
      expect(find.text(S.current.sendShares('5')), findsOne);
    });

    testWidgets('confirming starts the process step', (tester) async {
      await tester.pumpApp(
        const SendConfirmPage(recipient: '0xRecipient', amount: 5),
      );

      await tester.tap(find.text(S.current.sendConfirmButton));
      // Let the page-route transition advance (the process page never settles —
      // it keeps a CupertinoActivityIndicator animating — so pump fixed frames).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(SendProcessView), findsOne);
    });

    testWidgets('double-tap before rebuild pushes only one process page', (tester) async {
      await tester.pumpApp(
        const SendConfirmPage(recipient: '0xRecipient', amount: 5),
      );

      // Two tap-up callbacks before any rebuild (WidgetTester.tap does not pump).
      await tester.tap(find.text(S.current.sendConfirmButton));
      await tester.tap(find.text(S.current.sendConfirmButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(SendProcessView), findsOneWidget);
    });
  });
}
