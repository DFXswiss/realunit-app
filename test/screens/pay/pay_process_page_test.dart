import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/config/api_config.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_blockchain_api_service.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_faucet_service.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_pay_service.dart';
import 'package:realunit_wallet/packages/service/wallet_service.dart';
import 'package:realunit_wallet/packages/utils/default_assets.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';
import 'package:realunit_wallet/screens/pay/cubits/pay_process/pay_process_cubit.dart';
import 'package:realunit_wallet/screens/pay/pay_process_page.dart';

import '../../helper/helper.dart';

class _MockPayProcessCubit extends MockCubit<PayProcessState> implements PayProcessCubit {}

class _MockPayService extends Mock implements RealUnitPayService {}

class _MockFaucetService extends Mock implements DfxFaucetService {}

class _MockBlockchainService extends Mock implements DfxBlockchainApiService {}

class _MockWalletService extends Mock implements WalletService {}

class _MockAppStore extends Mock implements AppStore {}

class _MockApiConfig extends Mock implements ApiConfig {}

class _MockWallet extends Mock implements SoftwareWallet {}

void main() {
  late _MockPayProcessCubit processCubit;

  setUpAll(() {
    final getIt = GetIt.instance;
    // PayProcessPage resolves a full service graph from getIt and calls
    // start(). A debug wallet makes start() settle immediately
    // (signatureUnsupported) without touching the chain.
    final payService = _MockPayService();
    getIt.registerSingleton<RealUnitPayService>(payService);
    getIt.registerSingleton<DfxFaucetService>(_MockFaucetService());
    getIt.registerSingleton<DfxBlockchainApiService>(_MockBlockchainService());
    getIt.registerSingleton<WalletService>(_MockWalletService());
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

  setUp(() {
    processCubit = _MockPayProcessCubit();
    when(() => processCubit.state).thenReturn(const PayProcessInitial());
    when(() => processCubit.retryPay()).thenAnswer((_) async {});
  });

  Widget buildSubject() => BlocProvider<PayProcessCubit>.value(
    value: processCubit,
    child: const PayProcessView(),
  );

  group('$PayProcessPage', () {
    testWidgets('builds its own cubit and renders $PayProcessView', (tester) async {
      await tester.pumpApp(const PayProcessPage(paymentLinkId: 'pl_abc', zchfNeeded: 42.7));
      // start() runs and emits a failure on the debug wallet; pump a frame to
      // let the cubit settle (the sheet animation is not awaited here).
      await tester.pump();

      expect(find.byType(PayProcessView), findsOne);
    });
  });

  group('$PayProcessView progress labels', () {
    Future<void> expectLabel(WidgetTester tester, PayProcessState state, String label) async {
      when(() => processCubit.state).thenReturn(state);
      await tester.pumpApp(buildSubject());

      expect(find.byType(CupertinoActivityIndicator), findsOne);
      expect(find.text(label), findsOne);
    }

    testWidgets('initial shows preparing-swap', (tester) async {
      await expectLabel(tester, const PayProcessInitial(), S.current.payPreparingSwap);
    });

    testWidgets('preparing-swap label', (tester) async {
      await expectLabel(tester, const PayProcessPreparingSwap(), S.current.payPreparingSwap);
    });

    testWidgets('waiting-for-eth label', (tester) async {
      await expectLabel(tester, const PayProcessWaitingForEth(), S.current.payWaitingForEth);
    });

    testWidgets('swapping label', (tester) async {
      await expectLabel(tester, const PayProcessSwapping(), S.current.paySwapping);
    });

    testWidgets('refreshing-quote label', (tester) async {
      await expectLabel(tester, const PayProcessRefreshingQuote(), S.current.payRefreshingQuote);
    });

    testWidgets('paying label', (tester) async {
      await expectLabel(tester, const PayProcessPaying(), S.current.payPaying);
    });

    testWidgets('awaiting-settlement label', (tester) async {
      await expectLabel(
        tester,
        const PayProcessAwaitingSettlement('0xtx'),
        S.current.payAwaitingSettlement,
      );
    });

    testWidgets('success label', (tester) async {
      await expectLabel(tester, const PayProcessSuccess(), S.current.paySuccess);
    });

    testWidgets('pay-retry label', (tester) async {
      await expectLabel(
        tester,
        const PayProcessPayRetry(PayRetryReason.quoteExpired),
        S.current.payRetryTitle,
      );
    });

    testWidgets('failure label', (tester) async {
      await expectLabel(
        tester,
        const PayProcessFailure(PayProcessFailureReason.generic),
        S.current.payFailureTitle,
      );
    });
  });

  // The result/retry sheets are modal bottom sheets shown from the listener.
  // The PayProcessView keeps a CupertinoActivityIndicator animating behind the
  // sheet, so pumpAndSettle never settles; pump fixed frames to open the sheet.
  // A phone-sized surface keeps the taller retry sheet from overflowing the
  // default 800x600 test viewport (mirrors the logout-sheet test convention).
  Future<void> pumpWithState(WidgetTester tester, PayProcessState terminal) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    whenListen(
      processCubit,
      Stream<PayProcessState>.fromIterable([terminal]),
      initialState: const PayProcessSwapping(),
    );
    await tester.pumpApp(buildSubject());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('$PayProcessView result sheet', () {
    testWidgets('success emits a success sheet with title + description', (tester) async {
      await pumpWithState(tester, const PayProcessSuccess());

      expect(find.text(S.current.paySuccessDescription), findsOne);
      expect(find.byIcon(Icons.check_circle_rounded), findsOne);
      expect(find.text(S.current.close), findsOne);

      // Tapping close pops the sheet and then pops the page.
      await tester.tap(find.text(S.current.close));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
    });

    testWidgets('insufficient-zchf failure emits a failure sheet', (tester) async {
      await pumpWithState(
        tester,
        const PayProcessFailure(PayProcessFailureReason.insufficientZchf),
      );

      // payFailureTitle also renders as the progress-label behind the sheet,
      // so it appears twice; the reason message is the sheet-unique assertion.
      expect(find.text(S.current.payFailureTitle), findsWidgets);
      expect(find.text(S.current.payFailureInsufficientZchf), findsOne);
      expect(find.byIcon(Icons.error_rounded), findsOne);
    });

    testWidgets('insufficient-eth failure message', (tester) async {
      await pumpWithState(
        tester,
        const PayProcessFailure(PayProcessFailureReason.insufficientEth),
      );

      expect(find.text(S.current.payFailureInsufficientEth), findsOne);
    });

    testWidgets('signature-unsupported failure message', (tester) async {
      await pumpWithState(
        tester,
        const PayProcessFailure(PayProcessFailureReason.signatureUnsupported),
      );

      expect(find.text(S.current.payFailureSignatureUnsupported), findsOne);
    });

    testWidgets('bitbox-required failure message', (tester) async {
      await pumpWithState(
        tester,
        const PayProcessFailure(PayProcessFailureReason.bitboxRequired),
      );

      expect(find.text(S.current.payFailureBitboxRequired), findsOne);
    });

    testWidgets('generic failure message', (tester) async {
      await pumpWithState(
        tester,
        const PayProcessFailure(PayProcessFailureReason.generic),
      );

      expect(find.text(S.current.payFailureGeneric), findsOne);
    });
  });

  group('$PayProcessView retry sheet', () {
    testWidgets('pay-retry emits a retry sheet whose primary action calls retryPay', (
      tester,
    ) async {
      await pumpWithState(tester, const PayProcessPayRetry(PayRetryReason.quoteExpired));

      expect(find.text(S.current.payRetryQuoteExpired), findsOne);
      expect(find.byIcon(Icons.replay_rounded), findsOne);

      await tester.tap(find.text(S.current.payRetryButton));
      await tester.pump();

      verify(() => processCubit.retryPay()).called(1);
    });

    testWidgets('retry sheet close action dismisses without retrying', (tester) async {
      await pumpWithState(tester, const PayProcessPayRetry(PayRetryReason.transient));

      expect(find.text(S.current.payRetryTransient), findsOne);

      await tester.tap(find.text(S.current.close));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      verifyNever(() => processCubit.retryPay());
      expect(find.text(S.current.payRetryTransient), findsNothing);
    });

    testWidgets('insufficient-zchf retry reason shows its message', (tester) async {
      await pumpWithState(tester, const PayProcessPayRetry(PayRetryReason.insufficientZchf));

      expect(find.text(S.current.payRetryInsufficientZchf), findsOne);
    });

    testWidgets('unsigned-tx-mismatch retry reason shows its message', (tester) async {
      await pumpWithState(tester, const PayProcessPayRetry(PayRetryReason.unsignedTxMismatch));

      expect(find.text(S.current.payRetryUnsignedTxMismatch), findsOne);
    });
  });
}
