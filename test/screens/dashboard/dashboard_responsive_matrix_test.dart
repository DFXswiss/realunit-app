// Responsive matrix gate for the empty-dashboard "RealUnit kaufen" CTA.
//
// Proves the buy CTA stays reachable and fully tappable across the full
// device x text-scale matrix (see test/helper/responsive_matrix.dart).
// Regression lock for the dead-button bug: `Column(..., Spacer(), <CTA>)`
// inside the height-bounded `Expanded > Stack` host (dashboard_page.dart)
// overflowed already at default text scale with one pending transaction,
// painting the CTA outside the parent's hit-testable region.
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/models/balance.dart';
import 'package:realunit_wallet/packages/service/dfx/models/transactions/dto/transactions_dto.dart';
import 'package:realunit_wallet/packages/utils/default_assets.dart';
import 'package:realunit_wallet/screens/dashboard/bloc/balance_cubit.dart';
import 'package:realunit_wallet/screens/dashboard/bloc/dashboard_bloc.dart';
import 'package:realunit_wallet/screens/dashboard/bloc/pending_transactions_cubit.dart';
import 'package:realunit_wallet/screens/dashboard/dashboard_page.dart';
import 'package:realunit_wallet/screens/settings/bloc/settings_bloc.dart';
import 'package:realunit_wallet/setup/routing/routes/app_routes.dart';
import 'package:realunit_wallet/styles/currency.dart';
import 'package:realunit_wallet/styles/themes.dart';

import '../../helper/helper.dart';

class _MockDashboardBloc extends MockBloc<DashboardEvent, DashboardState>
    implements DashboardBloc {}

class _MockBalanceCubit extends MockCubit<Balance> implements BalanceCubit {}

class _MockPendingTransactionsCubit extends MockCubit<List<TransactionDto>>
    implements PendingTransactionsCubit {}

void main() {
  late _MockDashboardBloc dashboardBloc;
  late _MockBalanceCubit balanceCubit;
  late _MockPendingTransactionsCubit pendingTxCubit;
  late MockSettingsBloc settingsBloc;

  Balance zeroBalance() => Balance(
    chainId: realUnitAsset.chainId,
    contractAddress: realUnitAsset.address,
    walletAddress: '0x0',
    balance: BigInt.zero,
    asset: realUnitAsset,
  );

  DashboardState emptyDashboardState() => DashboardState(
    price: BigInt.zero,
    priceChart: const [],
    portfolioHistory: const [],
    currency: Currency.chf,
  );

  // Long amount + asset so the trailing amount/date column is under real
  // width pressure at high text scales (gates the Flexible wrap on
  // PendingTransactionRow). Realistic sell-size, not an absurd string.
  final waitingForPaymentTx = TransactionDto(
    id: 1,
    type: TransactionType.sell,
    state: TransactionState.waitingForPayment,
    inputAmount: 123456.78,
    inputAsset: 'REALU',
    date: DateTime.utc(2026, 5, 20, 12),
  );

  setUp(() {
    dashboardBloc = _MockDashboardBloc();
    balanceCubit = _MockBalanceCubit();
    pendingTxCubit = _MockPendingTransactionsCubit();
    settingsBloc = MockSettingsBloc();

    when(() => dashboardBloc.state).thenReturn(emptyDashboardState());
    when(() => balanceCubit.state).thenReturn(zeroBalance());
    when(() => balanceCubit.asset).thenReturn(realUnitAsset);
    when(() => pendingTxCubit.state).thenReturn(const <TransactionDto>[]);
    when(() => settingsBloc.state).thenReturn(const SettingsState());
  });

  Widget buildDashboard() => MultiBlocProvider(
    providers: [
      BlocProvider<SettingsBloc>.value(value: settingsBloc),
      BlocProvider<DashboardBloc>.value(value: dashboardBloc),
      BlocProvider<BalanceCubit>.value(value: balanceCubit),
      BlocProvider<PendingTransactionsCubit>.value(value: pendingTxCubit),
    ],
    child: const DashboardView(),
  );

  // A minimal two-route stack: '/' hosts the dashboard, '/buy' is a marker
  // page so a real `context.pushNamed(AppRoutes.buy)` resolves instead of
  // throwing (the CTA's actual, unmocked navigation call).
  GoRouter buildRouter() => GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, _) => buildDashboard()),
      GoRoute(
        name: AppRoutes.buy,
        path: '/buy',
        builder: (_, _) => const Scaffold(
          body: Center(child: Text('buy-page-marker')),
        ),
      ),
    ],
  );

  Future<void> pumpDashboard(WidgetTester tester, MatrixCell cell) async {
    final router = buildRouter();
    addTearDown(router.dispose);

    await tester.binding.setSurfaceSize(cell.device.size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MediaQuery(
        data: cell.mediaQuery,
        child: MaterialApp.router(
          routerConfig: router,
          theme: realUnitTheme,
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
    // The pending-tx row hosts a CupertinoActivityIndicator that never
    // settles, and the empty-state SVG needs a couple of frames to decode —
    // fixed pumps only, never pumpAndSettle here (mirrors
    // dashboard_states_golden_test.dart's pendingTransactions pumpBeforeTest).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  group('DashboardView responsive matrix - empty balance, buy CTA reachable '
      '(full device x textScale)', () {
    for (final cell in kFullResponsiveMatrix) {
      for (final hasPendingTx in [false, true]) {
        final label = hasPendingTx ? 'with pending tx' : 'no pending tx';
        testWidgets('$label - ${cell.id}', (tester) async {
          await withTargetPlatform(cell.device.platform, () async {
            when(() => pendingTxCubit.state).thenReturn(
              hasPendingTx ? [waitingForPaymentTx] : const <TransactionDto>[],
            );

            await expectNoLayoutOverflow(
              tester,
              () async {
                await pumpDashboard(tester, cell);
              },
              reason: 'overflow on $label / ${cell.label}',
            );

            await expectFullyTappable(
              tester,
              find.text(S.current.buyRealUnit),
              within: find.byType(DashboardView),
              reason: '$label / ${cell.label}: buy CTA not tappable',
            );
          });
        });
      }
    }
  });

  group(
    'DashboardView responsive matrix - positive balance, insider unlocked, '
    'all four actions tappable (full device x textScale)',
    () {
      for (final cell in kFullResponsiveMatrix) {
        testWidgets(cell.id, (tester) async {
          await withTargetPlatform(cell.device.platform, () async {
            when(() => balanceCubit.state).thenReturn(
              Balance(
                chainId: realUnitAsset.chainId,
                contractAddress: realUnitAsset.address,
                walletAddress: '0x0',
                balance: BigInt.from(5000000000000000000),
                asset: realUnitAsset,
              ),
            );
            when(() => settingsBloc.state)
                .thenReturn(const SettingsState(insiderFeaturesUnlocked: true));

            await expectNoLayoutOverflow(
              tester,
              () async {
                await pumpDashboard(tester, cell);
              },
              reason:
                  'overflow on positive balance, insider unlocked / ${cell.label}',
            );

            await expectFullyTappable(
              tester,
              find.text(S.current.buy),
              within: find.byType(DashboardView),
              reason: '${cell.label}: buy button not tappable',
            );
            await expectFullyTappable(
              tester,
              find.text(S.current.sell),
              within: find.byType(DashboardView),
              reason: '${cell.label}: sell button not tappable',
            );
            await expectFullyTappable(
              tester,
              find.text(S.current.pay),
              within: find.byType(DashboardView),
              reason: '${cell.label}: pay button not tappable',
            );
            await expectFullyTappable(
              tester,
              find.text(S.current.send),
              within: find.byType(DashboardView),
              reason: '${cell.label}: send button not tappable',
            );
          });
        });
      }
    },
  );

  // Focused regression: the exact reported failure mode (empty balance, one
  // waitingForPayment pending tx, default text scale) must invoke the real
  // navigation via a tap - not just have a non-null onPressed. The old code
  // silently swallowed the tap because the button was painted outside the
  // hit-testable region.
  testWidgets(
    'REGRESSION: zero balance + one pending tx @1.0x - tap on the buy CTA '
    'actually navigates to AppRoutes.buy',
    (tester) async {
      final cell = MatrixCell(
        kIosDeviceProfiles.firstWhere((d) => d.id == 'iphone_se_3'),
        1.0,
      );
      await withTargetPlatform(cell.device.platform, () async {
        when(() => pendingTxCubit.state).thenReturn([waitingForPaymentTx]);

        await expectNoLayoutOverflow(tester, () async {
          await pumpDashboard(tester, cell);
        });

        expect(find.text('buy-page-marker'), findsNothing);

        await expectFullyTappable(
          tester,
          find.text(S.current.buyRealUnit),
          within: find.byType(DashboardView),
        );
        await tester.pumpAndSettle();

        expect(find.text('buy-page-marker'), findsOneWidget);
      });
    },
  );
}
