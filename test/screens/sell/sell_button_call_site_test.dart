// Guards the two `showModalBottomSheet(isScrollControlled: true)` call sites in
// sell_button.dart (SellConfirmSheet and SellExecutedSheet). No existing test mounts the real
// SellButton and drives its BlocConsumer listener, so dropping either flag would regress
// silently. See sell_sheets_responsive_matrix_test.dart's own note that its matrix "does NOT
// exercise the real SellButton widget, so it cannot detect a regression at that call site
// itself — only the behavior the call site depends on." This test closes that gap.
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/dto/eip7702/eip7702_data_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/dto/real_unit_sell_payment_info_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/sell_payment_info.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_sell_payment_info_service.dart';
import 'package:realunit_wallet/screens/sell/cubits/sell_converter/sell_converter_cubit.dart';
import 'package:realunit_wallet/screens/sell/cubits/sell_payment_info/sell_payment_info_cubit.dart';
import 'package:realunit_wallet/screens/sell/widgets/sell_button.dart';
import 'package:realunit_wallet/screens/sell/widgets/sell_confirm_sheet.dart';
import 'package:realunit_wallet/screens/sell/widgets/sell_executed_sheet.dart';
import 'package:realunit_wallet/styles/currency.dart';
import 'package:realunit_wallet/styles/themes.dart';

class _MockSellPaymentInfoCubit extends MockCubit<SellPaymentInfoState>
    implements SellPaymentInfoCubit {}

class _MockSellConverterCubit extends MockCubit<SellConverterState>
    implements SellConverterCubit {}

class _MockRealUnitSellPaymentInfoService extends Mock
    implements RealUnitSellPaymentInfoService {}

/// Records every route pushed onto the navigator it observes, in order, so the test can
/// inspect the concrete [ModalBottomSheetRoute] instances `SellButton` pushes and pin their
/// `isScrollControlled` literal directly — the only reliable way to catch a regression at the
/// call site itself (rather than at some helper the call site merely depends on).
class _RouteCapturingObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushed = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    pushed.add(route);
  }
}

SellPaymentInfo _paymentInfoFixture() => const SellPaymentInfo(
  id: 42,
  eip7702: Eip7702Data(
    relayerAddress: '0x1',
    delegationManagerAddress: '0x2',
    delegatorAddress: '0x3',
    userNonce: 0,
    domain: Eip7702Domain(
      name: 'RealUnit',
      version: '1',
      chainId: 1,
      verifyingContract: '0x4',
    ),
    types: Eip7702Types(delegation: [], caveat: []),
    message: Eip7702Message(
      delegate: '0x5',
      delegator: '0x6',
      authority: '0x7',
      caveats: [],
      salt: 0,
    ),
    tokenAddress: '0x8',
    amountWei: '0',
    depositAddress: '0x9',
  ),
  amount: 100,
  exchangeRate: 1.0,
  rate: 1.0,
  beneficiary: BeneficiaryDto(iban: 'CH9300762011623852957'),
  estimatedAmount: 100.0,
  currency: Currency.chf,
  depositAddress: '0xA',
  tokenAddress: '0xB',
  chainId: 1,
  ethBalance: 0.01,
  requiredGasEth: 0.001,
);

void main() {
  late _MockSellPaymentInfoCubit sellPaymentInfoCubit;
  late _MockSellConverterCubit sellConverterCubit;

  setUpAll(() {
    GetIt.instance.registerSingleton<RealUnitSellPaymentInfoService>(
      _MockRealUnitSellPaymentInfoService(),
    );
  });

  tearDownAll(() async => GetIt.instance.reset());

  setUp(() {
    sellPaymentInfoCubit = _MockSellPaymentInfoCubit();
    sellConverterCubit = _MockSellConverterCubit();
    when(() => sellPaymentInfoCubit.state).thenReturn(const SellPaymentInfoInitial());
    when(() => sellConverterCubit.state).thenReturn(const SellConverterState());
  });

  Future<_RouteCapturingObserver> pumpSellButton(WidgetTester tester) async {
    final observer = _RouteCapturingObserver();
    final router = GoRouter(
      observers: [observer],
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: Center(
              child: MultiBlocProvider(
                providers: [
                  BlocProvider<SellPaymentInfoCubit>.value(value: sellPaymentInfoCubit),
                  BlocProvider<SellConverterCubit>.value(value: sellConverterCubit),
                ],
                child: const SellButton(amount: '10', bankAccount: null),
              ),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(
        theme: realUnitTheme,
        routerConfig: router,
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
      ),
    );
    await tester.pumpAndSettle();
    return observer;
  }

  group('$SellButton call sites', () {
    testWidgets(
      'shows SellConfirmSheet with isScrollControlled: true on SellPaymentInfoSuccess',
      (tester) async {
        whenListen(
          sellPaymentInfoCubit,
          Stream.value(SellPaymentInfoSuccess(_paymentInfoFixture(), isBitbox: false)),
          initialState: const SellPaymentInfoInitial(),
        );

        final observer = await pumpSellButton(tester);

        expect(find.byType(SellConfirmSheet), findsOneWidget);

        final modalRoutes = observer.pushed.whereType<ModalBottomSheetRoute>().toList();
        expect(
          modalRoutes,
          hasLength(1),
          reason: 'Expected exactly one modal bottom sheet (SellConfirmSheet) to have been '
              'pushed.',
        );
        expect(
          modalRoutes.first.isScrollControlled,
          isTrue,
          reason: 'sell_button.dart must push SellConfirmSheet with isScrollControlled: true.',
        );
      },
    );

    testWidgets(
      'shows SellExecutedSheet with isScrollControlled: true after the confirm sheet '
      'resolves with true',
      (tester) async {
        whenListen(
          sellPaymentInfoCubit,
          Stream.value(SellPaymentInfoSuccess(_paymentInfoFixture(), isBitbox: false)),
          initialState: const SellPaymentInfoInitial(),
        );

        final observer = await pumpSellButton(tester);

        final confirmRoute = observer.pushed.whereType<ModalBottomSheetRoute>().single;

        // Resolve the confirm sheet's route with `true` directly on the Navigator that owns
        // it — equivalent to the user completing the real SellConfirmCubit flow
        // (SellConfirmSuccess -> context.pop(true)) without depending on that internal flow
        // (which needs a live response from RealUnitSellPaymentInfoService.confirmPayment).
        // This isolates the assertion to the call-site literal in sell_button.dart, which is
        // the only thing this test is meant to guard.
        confirmRoute.navigator!.pop(true);
        await tester.pumpAndSettle();

        expect(find.byType(SellExecutedSheet), findsOneWidget);

        final modalRoutes = observer.pushed.whereType<ModalBottomSheetRoute>().toList();
        expect(
          modalRoutes,
          hasLength(2),
          reason: 'Expected a second modal bottom sheet (SellExecutedSheet) to have been '
              'pushed after the confirm sheet resolved with true.',
        );
        expect(
          modalRoutes.last.isScrollControlled,
          isTrue,
          reason: 'sell_button.dart must push SellExecutedSheet with isScrollControlled: true.',
        );
      },
    );
  });
}
