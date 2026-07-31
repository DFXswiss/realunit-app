import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/models/balance.dart';
import 'package:realunit_wallet/packages/config/api_config.dart';
import 'package:realunit_wallet/packages/repository/balance_repository.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/utils/default_assets.dart';
import 'package:realunit_wallet/screens/send/send_amount_page.dart';
import 'package:realunit_wallet/screens/send/send_confirm_page.dart';

import '../../helper/helper.dart';

class _MockBalanceRepository extends Mock implements BalanceRepository {}

class _MockAppStore extends Mock implements AppStore {}

class _MockApiConfig extends Mock implements ApiConfig {}

void main() {
  Balance balanceOf(BigInt value) => Balance(
    chainId: realUnitAsset.chainId,
    contractAddress: realUnitAsset.address,
    walletAddress: '0xwallet',
    balance: value,
    asset: realUnitAsset,
  );

  late _MockBalanceRepository balanceRepo;

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
  });

  void registerGraph(BigInt available) {
    final getIt = GetIt.instance;
    balanceRepo = _MockBalanceRepository();
    when(() => balanceRepo.watchBalance(any())).thenAnswer(
      (_) => Stream<Balance>.value(balanceOf(available)),
    );
    getIt.registerFactory<BalanceRepository>(() => balanceRepo);
    final appStore = _MockAppStore();
    final apiConfig = _MockApiConfig();
    when(() => apiConfig.asset).thenReturn(realUnitAsset);
    when(() => appStore.apiConfig).thenReturn(apiConfig);
    when(() => appStore.primaryAddress).thenReturn('0xwallet');
    getIt.registerSingleton<AppStore>(appStore);
  }

  tearDown(() async => GetIt.instance.reset());

  group('$SendAmountPage', () {
    testWidgets('shows the available balance and gates the continue button', (tester) async {
      registerGraph(BigInt.from(42));
      await tester.pumpApp(const SendAmountPage(recipient: '0xRecipient'));
      await tester.pumpAndSettle();

      expect(find.text(S.current.sendAmountAvailable('42')), findsOne);

      // Continue is disabled until a valid amount is entered.
      final disabled = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(disabled.onPressed, isNull);
    });

    testWidgets('an over-balance amount surfaces the insufficient error', (tester) async {
      registerGraph(BigInt.from(5));
      await tester.pumpApp(const SendAmountPage(recipient: '0xRecipient'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '6');
      await tester.pump();

      expect(find.text(S.current.sendAmountInsufficient), findsOne);
      final stillDisabled = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(stillDisabled.onPressed, isNull);
    });

    testWidgets('a valid amount enables continue and navigates to confirm', (tester) async {
      registerGraph(BigInt.from(42));
      await tester.pumpApp(const SendAmountPage(recipient: '0xRecipient'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '5');
      await tester.pumpAndSettle();

      // The continue button is now enabled.
      final enabled = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(enabled.onPressed, isNotNull);

      await tester.tap(find.widgetWithText(FilledButton, S.current.next));
      await tester.pumpAndSettle();

      expect(find.byType(SendConfirmPage), findsOne);
    });

    testWidgets('MAX fills the available balance', (tester) async {
      registerGraph(BigInt.from(42));
      await tester.pumpApp(const SendAmountPage(recipient: '0xRecipient'));
      await tester.pumpAndSettle();

      await tester.tap(find.text(S.current.max.toUpperCase()));
      await tester.pumpAndSettle();

      // MAX fills the field with the available balance and the amount validates.
      expect(find.text('42'), findsOneWidget);
      final enabled = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(enabled.onPressed, isNotNull);
    });
  });
}
