import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/config/api_config.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_blockchain_api_service.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_faucet_service.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_pay_service.dart';
import 'package:realunit_wallet/packages/service/wallet_service.dart';
import 'package:realunit_wallet/packages/utils/default_assets.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';
import 'package:realunit_wallet/screens/pay/cubits/pay_quote/pay_quote_cubit.dart';
import 'package:realunit_wallet/screens/pay/pay_process_page.dart';
import 'package:realunit_wallet/screens/pay/pay_quote_page.dart';

import '../../helper/helper.dart';

class _MockPayQuoteCubit extends MockCubit<PayQuoteState> implements PayQuoteCubit {}

class _MockPayService extends Mock implements RealUnitPayService {}

class _MockFaucetService extends Mock implements DfxFaucetService {}

class _MockBlockchainService extends Mock implements DfxBlockchainApiService {}

class _MockWalletService extends Mock implements WalletService {}

class _MockAppStore extends Mock implements AppStore {}

class _MockApiConfig extends Mock implements ApiConfig {}

class _MockWallet extends Mock implements SoftwareWallet {}

void main() {
  late _MockPayQuoteCubit quoteCubit;

  // Real Sepolia OCP capture (DFXswiss/api #3819): CHF 2.00 → 2.0 ZCHF on the
  // Ethereum method.
  const ready = PayQuoteReady(
    paymentLinkId: 'pl_realunit_ocp_sepolia',
    quoteId: 'plq_realunit_ocp_sepolia',
    fiatAsset: 'CHF',
    fiatAmount: 2,
    zchfAmount: 2.0,
  );

  setUpAll(() {
    final getIt = GetIt.instance;

    // PayQuotePage resolves the pay service from getIt and calls load(); the
    // load throws a typed error here so the pushed route builds deterministically
    // (rendering PayQuoteError) without a live backend.
    final payService = _MockPayService();
    when(() => payService.getPaymentDetails(any())).thenThrow(
      const ApiException(code: 'TEST', message: 'no backend in widget test'),
    );
    getIt.registerSingleton<RealUnitPayService>(payService);

    // The confirm button pushes PayProcessPage, which resolves a full service
    // graph from getIt and calls start(). A debug wallet makes start() settle
    // immediately (signatureUnsupported) without touching the chain.
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
    quoteCubit = _MockPayQuoteCubit();
    when(() => quoteCubit.state).thenReturn(const PayQuoteLoading());
  });

  Widget buildSubject() => BlocProvider<PayQuoteCubit>.value(
    value: quoteCubit,
    child: const PayQuoteView(),
  );

  group('$PayQuotePage', () {
    testWidgets('builds its own cubit and renders $PayQuoteView', (tester) async {
      await tester.pumpApp(const PayQuotePage(paymentLinkId: 'pl_abc'));

      expect(find.byType(PayQuoteView), findsOne);
    });
  });

  group('$PayQuoteView', () {
    testWidgets('loading state shows a $CupertinoActivityIndicator', (tester) async {
      when(() => quoteCubit.state).thenReturn(const PayQuoteLoading());
      await tester.pumpApp(buildSubject());

      expect(find.byType(CupertinoActivityIndicator), findsOne);
    });

    testWidgets('ready state shows the CHF amount, ZCHF needed and confirm button', (tester) async {
      when(() => quoteCubit.state).thenReturn(ready);
      await tester.pumpApp(buildSubject());

      expect(find.text(S.current.payQuoteSummary('2.00', 'CHF')), findsOne);
      expect(find.text('2.00 CHF'), findsOne);
      expect(find.text('2.00 ZCHF'), findsOne);
      expect(find.text(S.current.payConfirmButton), findsOne);
    });

    testWidgets('ready state shows merchant and REALU swap details when present', (tester) async {
      when(() => quoteCubit.state).thenReturn(
        const PayQuoteReady(
          paymentLinkId: 'pl_realunit_ocp_sepolia',
          quoteId: 'plq_realunit_ocp_sepolia',
          fiatAsset: 'CHF',
          fiatAmount: 2,
          zchfAmount: 2.0,
          merchantName: 'Café Zürich',
          merchantCity: 'Zürich',
          realuAmount: 5,
          realuEstimatedZchf: 1.98,
          realuFeesTotal: 0.02,
        ),
      );
      await tester.pumpApp(buildSubject());

      expect(find.text('Café Zürich, Zürich'), findsOne);
      expect(find.text('5 REALU'), findsOne);
      expect(find.text('1.98 ZCHF'), findsOne);
      expect(find.text('0.02 REALU'), findsOne);
    });

    testWidgets('confirm button navigates to the process step', (tester) async {
      when(() => quoteCubit.state).thenReturn(ready);
      await tester.pumpApp(buildSubject());

      await tester.tap(find.text(S.current.payConfirmButton));
      // The process page renders a CupertinoActivityIndicator that animates
      // forever, so pumpAndSettle would time out; pump fixed frames to drive
      // the push transition instead.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(PayProcessView), findsOne);
    });

    testWidgets('expired state shows the re-scan message', (tester) async {
      when(() => quoteCubit.state).thenReturn(const PayQuoteExpired());
      await tester.pumpApp(buildSubject());

      expect(find.text(S.current.payFailureQuoteExpired), findsOne);
    });

    testWidgets('unavailable state shows the unavailable message', (tester) async {
      when(() => quoteCubit.state).thenReturn(const PayQuoteUnavailable());
      await tester.pumpApp(buildSubject());

      expect(find.text(S.current.payQuoteUnavailable), findsOne);
    });

    testWidgets('error state shows the generic failure message', (tester) async {
      when(() => quoteCubit.state).thenReturn(const PayQuoteError('boom'));
      await tester.pumpApp(buildSubject());

      expect(find.text(S.current.payFailureGeneric), findsOne);
    });

    testWidgets('error state retry button re-invokes load()', (tester) async {
      when(() => quoteCubit.state).thenReturn(const PayQuoteError('boom'));
      when(() => quoteCubit.load()).thenAnswer((_) async {});
      await tester.pumpApp(buildSubject());

      await tester.tap(find.byKey(const ValueKey('payQuoteRetryButton')));
      await tester.pump();

      verify(() => quoteCubit.load()).called(1);
    });
  });
}
