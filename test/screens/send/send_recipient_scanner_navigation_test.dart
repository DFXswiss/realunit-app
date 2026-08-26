// Gate for the QR scanner double-stack bug: a live camera delivers the same
// code on every frame. Pushing the amount step and resetting the cubit in the
// same turn drops the Valid guard, so frame 2 pushes a second SendAmountPage.
// This test fires two BarcodeCaptures against the real cubit and expects
// SendAmountView exactly once; after pop, a third capture is accepted again.
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/models/balance.dart';
import 'package:realunit_wallet/packages/config/api_config.dart';
import 'package:realunit_wallet/packages/repository/balance_repository.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/utils/default_assets.dart';
import 'package:realunit_wallet/screens/send/send_amount_page.dart';
import 'package:realunit_wallet/screens/send/send_recipient_page.dart';

import '../../helper/helper.dart';

class _MockBalanceRepository extends Mock implements BalanceRepository {}

class _MockAppStore extends Mock implements AppStore {}

class _MockApiConfig extends Mock implements ApiConfig {}

void main() {
  // EIP-55 address from send_recipient_cubit_test.dart.
  const checksummed = '0x9F5713DEacB8e9CAB6c2d3FaE1AFc2715F8D2D71';

  Balance balanceOf(BigInt value) => Balance(
    chainId: realUnitAsset.chainId,
    contractAddress: realUnitAsset.address,
    walletAddress: '0xwallet',
    balance: value,
    asset: realUnitAsset,
  );

  setUpAll(() {
    registerFallbackValue(
      Balance(
        chainId: 1,
        contractAddress: '0x',
        walletAddress: '0x',
        balance: BigInt.zero,
        asset: realUnitAsset,
      ),
    );
    stubMobileScannerChannel();

    final getIt = GetIt.instance;
    final balanceRepo = _MockBalanceRepository();
    when(() => balanceRepo.watchBalance(any())).thenAnswer(
      (_) => Stream<Balance>.value(balanceOf(BigInt.from(100))),
    );
    getIt.registerFactory<BalanceRepository>(() => balanceRepo);
    final appStore = _MockAppStore();
    final apiConfig = _MockApiConfig();
    when(() => apiConfig.asset).thenReturn(realUnitAsset);
    when(() => appStore.apiConfig).thenReturn(apiConfig);
    when(() => appStore.primaryAddress).thenReturn('0xwallet');
    getIt.registerSingleton<AppStore>(appStore);
  });

  tearDownAll(() async => GetIt.instance.reset());

  testWidgets(
    'two identical captures push SendAmountView once; re-arms after pop',
    (tester) async {
      await tester.pumpApp(const SendRecipientPage());

      final scanner = tester.widget<MobileScanner>(find.byType(MobileScanner));
      const capture = BarcodeCapture(barcodes: [Barcode(rawValue: checksummed)]);
      scanner.onDetect!(capture);
      scanner.onDetect!(capture); // second frame — must not push again
      await tester.pumpAndSettle();

      expect(find.byType(SendAmountView), findsOne);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(SendAmountView), findsNothing);

      // Re-armed after pop: a new capture is accepted again.
      final scannerAfterPop = tester.widget<MobileScanner>(find.byType(MobileScanner));
      scannerAfterPop.onDetect!(capture);
      await tester.pumpAndSettle();
      expect(find.byType(SendAmountView), findsOne);
    },
  );
}
