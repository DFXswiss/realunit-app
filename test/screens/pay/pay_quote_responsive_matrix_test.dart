import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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
import 'package:realunit_wallet/screens/pay/cubits/pay_quote/pay_quote_cubit.dart';
import 'package:realunit_wallet/screens/pay/pay_quote_page.dart';
import 'package:realunit_wallet/styles/themes.dart';

import '../../helper/helper.dart';

class _MockPayQuoteCubit extends MockCubit<PayQuoteState> implements PayQuoteCubit {}

class _MockPayService extends Mock implements RealUnitPayService {}

class _MockFaucetService extends Mock implements DfxFaucetService {}

class _MockBlockchainService extends Mock implements DfxBlockchainApiService {}

class _MockWalletService extends Mock implements WalletService {}

class _MockAppStore extends Mock implements AppStore {}

class _MockApiConfig extends Mock implements ApiConfig {}

class _MockWallet extends Mock implements SoftwareWallet {}

Future<void> _pumpScreen(WidgetTester tester, MatrixCell cell, Widget child) async {
  await tester.binding.setSurfaceSize(cell.mediaQuery.size);
  addTearDown(() async => await tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MediaQuery(
      data: cell.mediaQuery,
      child: MaterialApp(
        theme: realUnitTheme,
        locale: const Locale('de'),
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        home: child,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  const ready = PayQuoteReady(
    paymentLinkId: 'pl_realunit_ocp_sepolia',
    quoteId: 'plq_realunit_ocp_sepolia',
    fiatAsset: 'CHF',
    fiatAmount: 2,
    zchfAmount: 2.0,
  );

  late _MockPayQuoteCubit quoteCubit;

  setUpAll(() {
    final getIt = GetIt.instance;
    getIt.registerSingleton<RealUnitPayService>(_MockPayService());
    getIt.registerSingleton<DfxFaucetService>(_MockFaucetService());
    getIt.registerSingleton<DfxBlockchainApiService>(_MockBlockchainService());
    getIt.registerSingleton<WalletService>(_MockWalletService());

    final appStore = _MockAppStore();
    final apiConfig = _MockApiConfig();
    final wallet = _MockWallet();
    when(() => apiConfig.asset).thenReturn(realUnitAsset);
    when(() => wallet.walletType).thenReturn(WalletType.debug);
    when(() => appStore.wallet).thenReturn(wallet);
    when(() => appStore.apiConfig).thenReturn(apiConfig);
    getIt.registerSingleton<AppStore>(appStore);
  });

  tearDownAll(() async => GetIt.instance.reset());

  setUp(() {
    quoteCubit = _MockPayQuoteCubit();
    when(() => quoteCubit.state).thenReturn(ready);
  });

  group('PayQuoteView responsive matrix (full device x textScale)', () {
    for (final cell in kFullResponsiveMatrix) {
      testWidgets(cell.id, (tester) async {
        await withTargetPlatform(cell.device.platform, () async {
          final subject = BlocProvider<PayQuoteCubit>.value(
            value: quoteCubit,
            child: const PayQuoteView(),
          );

          await expectNoLayoutOverflow(
            tester,
            () => _pumpScreen(tester, cell, subject),
            reason: 'PayQuoteView overflow / ${cell.label}',
          );

          await expectFullyTappable(
            tester,
            find.widgetWithText(FilledButton, S.current.payConfirmButton),
            within: find.byType(PayQuoteView),
            reason: 'PayQuoteView / ${cell.label}: Confirm CTA not tappable',
          );
        });
      });
    }
  });
}
