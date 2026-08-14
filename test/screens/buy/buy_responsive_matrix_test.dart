// Responsive matrix gate for BuyView primary CTA.
//
// Proves the buy payment-action button stays fully tappable across the full
// device × text-scale matrix (see test/helper/responsive_matrix.dart).
// Regression lock for the IntrinsicHeight + Spacer collapse that pushed the
// CTA below the viewport on first frame without a RenderFlex overflow.
//
// Also proves the sticky actions stay above the soft keyboard via Scaffold's
// default resizeToAvoidBottomInset (viewInsets shrink the bounded height).
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/config/api_config.dart';
import 'package:realunit_wallet/packages/repository/cache_repository.dart';
import 'package:realunit_wallet/packages/repository/supported_fiat_repository.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_brokerbot_service.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_price_service.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/buy/buy_payment_info.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/buy/dto/real_unit_buy_confirm_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/payment_info_error.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_buy_payment_info_service.dart';
import 'package:realunit_wallet/packages/service/session_cache.dart';
import 'package:realunit_wallet/screens/buy/buy_page.dart';
import 'package:realunit_wallet/screens/buy/cubits/buy_converter/buy_converter_cubit.dart';
import 'package:realunit_wallet/screens/buy/cubits/buy_payment_info/buy_payment_info_cubit.dart';
import 'package:realunit_wallet/setup/routing/routes/app_routes.dart';
import 'package:realunit_wallet/styles/currency.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';

import '../../helper/helper.dart';

class MockBuyConverterCubit extends MockCubit<BuyConverterState> implements BuyConverterCubit {}

class MockBuyPaymentInfoCubit extends MockCubit<BuyPaymentInfoState>
    implements BuyPaymentInfoCubit {}

class MockDfxBrokerbotService extends Mock implements DfxBrokerbotService {}

class MockRealUnitBuyPaymentInfoService extends Mock implements RealUnitBuyPaymentInfoService {}

class MockDfxPriceService extends Mock implements DFXPriceService {}

class MockApiConfig extends Mock implements ApiConfig {}

class MockCacheRepository extends Mock implements CacheRepository {}

class MockSupportedFiatRepository extends Mock implements SupportedFiatRepository {}

void main() {
  late BuyConverterCubit converterCubit;
  late BuyPaymentInfoCubit buyPaymentInfoCubit;

  void setupDependencyInjection() {
    final getIt = GetIt.instance;
    getIt.registerSingleton<AppStore>(
      AppStore(() => MockApiConfig(), SessionCache(MockCacheRepository())),
    );
    getIt.registerSingleton<DfxBrokerbotService>(MockDfxBrokerbotService());
    getIt.registerSingleton<RealUnitBuyPaymentInfoService>(MockRealUnitBuyPaymentInfoService());
    getIt.registerSingleton<DFXPriceService>(MockDfxPriceService());
    final fiatRepo = MockSupportedFiatRepository();
    when(() => fiatRepo.getBuyable()).thenAnswer((_) async => const [Currency.chf, Currency.eur]);
    when(() => fiatRepo.getSellable()).thenAnswer((_) async => const [Currency.chf]);
    when(() => fiatRepo.getAll()).thenAnswer((_) async => const [Currency.chf, Currency.eur]);
    getIt.registerSingleton<SupportedFiatRepository>(fiatRepo);
  }

  setUpAll(() {
    registerFallbackValue(Currency.chf);
    setupDependencyInjection();
  });

  tearDownAll(() async => await GetIt.instance.reset());

  setUp(() {
    converterCubit = MockBuyConverterCubit();
    buyPaymentInfoCubit = MockBuyPaymentInfoCubit();

    when(() => converterCubit.state).thenReturn(const BuyConverterState());
    when(() => buyPaymentInfoCubit.state).thenReturn(const BuyPaymentInfoInitial());
    when(
      () => buyPaymentInfoCubit.getPaymentInfo(
        amount: any(named: 'amount'),
        currency: any(named: 'currency'),
      ),
    ).thenAnswer((_) => Future.value());
  });

  /// Primary CTA state: unknown error shows a Retry button whose tap only
  /// calls the already-stubbed getPaymentInfo (no router/service needed).
  void stubPrimaryCtaState() {
    when(() => buyPaymentInfoCubit.state).thenReturn(
      const BuyPaymentInfoFailure(PaymentInfoError.unknown),
    );
    when(() => converterCubit.state).thenReturn(
      const BuyConverterState(
        currency: Currency.eur,
        fiatText: '999999999',
        sharesText: '1234567.89',
      ),
    );
  }

  /// Success dual-CTA: real BuyConfirmCubit via GetIt service + GoRouter for
  /// confirm navigation; deactivate opens an AlertDialog.
  void stubSuccessCtaState() {
    when(() => buyPaymentInfoCubit.state).thenReturn(
      const BuyPaymentInfoSuccess(
        BuyPaymentInfo(
          amount: 300,
          id: 1,
          iban: 'iban',
          bic: 'bic',
          name: 'name',
          street: 'street',
          number: 'number',
          zip: 'zip',
          city: 'city',
          country: 'country',
          currency: Currency.chf,
        ),
      ),
    );
    final buyService = GetIt.instance<RealUnitBuyPaymentInfoService>();
    when(() => buyService.confirmPayment(any())).thenAnswer(
      (_) async => const RealUnitBuyConfirmDto(reference: 'REF-456'),
    );
    when(() => buyService.deactivateQuote(any())).thenAnswer((_) async {});
  }

  Widget buildSubject() {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: converterCubit),
        BlocProvider.value(value: buyPaymentInfoCubit),
      ],
      child: const BuyView(),
    );
  }

  Future<void> pumpScreen(
    WidgetTester tester,
    MatrixCell cell,
    Widget child, {
    MediaQueryData? mediaQueryOverride,
  }) async {
    final mediaQuery = mediaQueryOverride ?? cell.mediaQuery;
    await tester.binding.setSurfaceSize(mediaQuery.size);
    addTearDown(() async => await tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MediaQuery(
        data: mediaQuery,
        child: MaterialApp(
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

  /// Success host needs GoRouter: confirm tap pushes buyPaymentDetails.
  Future<void> pumpSuccessScreen(
    WidgetTester tester,
    MatrixCell cell, {
    MediaQueryData? mediaQueryOverride,
  }) async {
    final mediaQuery = mediaQueryOverride ?? cell.mediaQuery;
    await tester.binding.setSurfaceSize(mediaQuery.size);
    addTearDown(() async => await tester.binding.setSurfaceSize(null));

    final router = GoRouter(
      initialLocation: '/parent/child',
      routes: [
        GoRoute(
          path: '/parent',
          builder: (_, _) => const Scaffold(body: Text('parent-marker')),
          routes: [
            GoRoute(
              path: 'child',
              builder: (_, _) => MultiBlocProvider(
                providers: [
                  BlocProvider.value(value: converterCubit),
                  BlocProvider.value(value: buyPaymentInfoCubit),
                ],
                child: const BuyView(),
              ),
            ),
          ],
        ),
        GoRoute(
          name: AppRoutes.buyPaymentDetails,
          path: '/buyPaymentDetails',
          builder: (_, _) => const Scaffold(body: Text('details-marker')),
        ),
      ],
    );

    await tester.pumpWidget(
      MediaQuery(
        data: mediaQuery,
        child: MaterialApp.router(
          routerConfig: router,
          locale: const Locale('de'),
          localizationsDelegates: const [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: S.delegate.supportedLocales,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  group('BuyView responsive matrix (full device × textScale)', () {
    for (final cell in kFullResponsiveMatrix) {
      testWidgets(cell.id, (tester) async {
        await withTargetPlatform(cell.device.platform, () async {
          stubPrimaryCtaState();

          await expectNoLayoutOverflow(
            tester,
            () async {
              await pumpScreen(tester, cell, buildSubject());
            },
            reason: 'overflow on ${cell.label}',
          );

          await expectFullyTappable(
            tester,
            find.byType(AppFilledButton),
            within: find.byType(BuyView),
            reason: '${cell.label}: buy CTA not tappable',
          );
        });
      });
    }
  });

  // Success two-CTA: separate matrix groups so each cell performs overflow +
  // exactly one real tap (confirm navigates; deactivate opens a dialog).
  group('BuyView Success dual-CTA matrix — confirm (full device × textScale)', () {
    for (final cell in kFullResponsiveMatrix) {
      testWidgets('${cell.id}_success_confirm', (tester) async {
        await withTargetPlatform(cell.device.platform, () async {
          stubSuccessCtaState();

          await expectNoLayoutOverflow(
            tester,
            () async {
              await pumpSuccessScreen(tester, cell);
            },
            reason: 'overflow on ${cell.label} (Success confirm)',
          );

          await expectFullyTappable(
            tester,
            find.text(S.current.buyPaymentConfirm),
            within: find.byType(BuyView),
            reason: '${cell.label}: Success confirm CTA not tappable',
          );
        });
      });
    }
  });

  group('BuyView Success dual-CTA matrix — deactivate (full device × textScale)', () {
    for (final cell in kFullResponsiveMatrix) {
      testWidgets('${cell.id}_success_deactivate', (tester) async {
        await withTargetPlatform(cell.device.platform, () async {
          stubSuccessCtaState();

          await expectNoLayoutOverflow(
            tester,
            () async {
              await pumpSuccessScreen(tester, cell);
            },
            reason: 'overflow on ${cell.label} (Success deactivate)',
          );

          await expectFullyTappable(
            tester,
            find.text(S.current.pendingTransactionDeactivate),
            within: find.byType(BuyView),
            reason: '${cell.label}: Success deactivate CTA not tappable',
          );
        });
      });
    }
  });

  // Keyboard: Scaffold.resizeToAvoidBottomInset (default true) shrinks the
  // body; ScrollableActionsLayout receives the reduced bounded height. Prove
  // the CTA stays fully tappable with a simulated open keyboard.
  testWidgets(
    'KEYBOARD: iPhone SE textScale 1.0 — CTA tappable with viewInsets keyboard',
    (tester) async {
      final cell = MatrixCell(
        kIosDeviceProfiles.firstWhere((d) => d.id == 'iphone_se_3'),
        1.0,
      );
      final keyboardMediaQuery = cell.mediaQuery.copyWith(
        viewInsets: const EdgeInsets.only(bottom: 336),
      );

      await withTargetPlatform(cell.device.platform, () async {
        stubPrimaryCtaState();

        await expectNoLayoutOverflow(
          tester,
          () async {
            await pumpScreen(
              tester,
              cell,
              buildSubject(),
              mediaQueryOverride: keyboardMediaQuery,
            );
          },
          reason: 'overflow with keyboard on ${cell.label}',
        );

        await expectFullyTappable(
          tester,
          find.byType(AppFilledButton),
          within: find.byType(BuyView),
          reason: 'buy CTA not tappable above the keyboard (viewInsets.bottom=336)',
        );
      });
    },
  );
}
