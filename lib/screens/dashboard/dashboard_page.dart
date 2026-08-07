import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/repository/balance_repository.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_price_service.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_account_service.dart';
import 'package:realunit_wallet/packages/service/transaction_history_service.dart';
import 'package:realunit_wallet/screens/dashboard/bloc/balance_cubit.dart';
import 'package:realunit_wallet/screens/dashboard/bloc/dashboard_bloc.dart';
import 'package:realunit_wallet/screens/dashboard/bloc/pending_transactions_cubit.dart';
import 'package:realunit_wallet/screens/dashboard/widgets/sections/dashboard_actions.dart';
import 'package:realunit_wallet/screens/dashboard/widgets/sections/dashboard_pending_transactions.dart';
import 'package:realunit_wallet/screens/dashboard/widgets/sections/dashboard_portfolio.dart';
import 'package:realunit_wallet/screens/dashboard/widgets/sections/dashboard_portfolio_chart_widget.dart';
import 'package:realunit_wallet/screens/dashboard/widgets/sections/dashboard_price_widget.dart';
import 'package:realunit_wallet/screens/dashboard/widgets/sections/dashboard_transaction_history.dart';
import 'package:realunit_wallet/screens/settings/bloc/settings_bloc.dart';
import 'package:realunit_wallet/setup/di.dart';
import 'package:realunit_wallet/setup/routing/routes/app_routes.dart';
import 'package:realunit_wallet/setup/routing/routes/settings_routes.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/styles/icons.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';
import 'package:realunit_wallet/widgets/scrollable_actions_layout.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final networkMode = context.watch<SettingsBloc>().state.networkMode;

    return MultiBlocProvider(
      key: ValueKey(networkMode),
      providers: [
        BlocProvider(
          create: (context) => DashboardBloc(
            getIt<DFXPriceService>(),
            getIt<RealUnitAccountService>(),
            asset: getIt<AppStore>().apiConfig.asset,
            initialCurrency: context.read<SettingsBloc>().state.currency,
          ),
        ),
        BlocProvider(
          create: (context) => BalanceCubit(
            getIt<BalanceRepository>(),
            asset: getIt<AppStore>().apiConfig.asset,
            walletAddress: getIt<AppStore>().primaryAddress,
          ),
        ),
        BlocProvider(
          create: (context) => PendingTransactionsCubit(
            getIt<TransactionHistoryService>(),
          ),
        ),
      ],
      child: const DashboardView(),
    );
  }
}

class DashboardView extends StatelessWidget {
  const DashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    final dashboardState = context.watch<DashboardBloc>().state;
    final balance = context.watch<BalanceCubit>().state.balance;

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: SafeArea(
          child: Row(
            spacing: 6.0,
            children: [
              const SizedBox(width: 14),
              const RealUnitIcon(),
              Expanded(
                child: Text(
                  S.of(context).realunitWallet,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    letterSpacing: -0.32,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => context.pushNamed(SettingsRoutes.settings),
                icon: const Icon(
                  Icons.menu,
                  color: RealUnitColors.realUnitBlue,
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
      body: BlocListener<SettingsBloc, SettingsState>(
        listenWhen: (previous, current) => previous.currency != current.currency,
        listener: (context, state) {
          context.read<DashboardBloc>().add(CurrencyChangedEvent(state.currency));
        },
        child: PopScope(
          canPop: false,
          child: Column(
            children: [
              if (dashboardState.portfolioHistory.isNotEmpty)
                DashboardPortfolioChartWidget(
                  currentValue: dashboardState.portfolioHistory.isNotEmpty
                      ? dashboardState.portfolioHistory.last.balance * dashboardState.price
                      : BigInt.zero,
                  portfolioHistory: dashboardState.portfolioHistory,
                )
              else
                DashboardPriceWidget(
                  price: dashboardState.price,
                  priceChart: dashboardState.priceChart,
                ),
              Expanded(
                child: Stack(
                  children: [
                    Container(color: RealUnitColors.neutral100),
                    if (balance > BigInt.zero)
                      SingleChildScrollView(
                        child: Container(
                          padding: const .symmetric(
                            horizontal: 20.0,
                            vertical: 24.0,
                          ),
                          child: Column(
                            spacing: 20.0,
                            children: [
                              const DashboardActions(),
                              DashboardPortfolio(
                                price: dashboardState.price,
                              ),
                              const DashboardPendingTransactionsView(),
                              const DashboardTransactionHistory(),
                            ],
                          ),
                        ),
                      )
                    else
                      ScrollableActionsLayout(
                        padding: const .symmetric(
                          horizontal: 20.0,
                          vertical: 24.0,
                        ),
                        centerBody: true,
                        body: Column(
                          crossAxisAlignment: .stretch,
                          spacing: context.watch<PendingTransactionsCubit>().state.isEmpty
                              ? 0.0
                              : 24.0,
                          children: [
                            const DashboardPendingTransactionsView(),
                            SvgPicture.asset(
                              'assets/images/illustrations/realu_token.svg',
                              width: 165,
                              height: 165,
                            ),
                          ],
                        ),
                        actions: [
                          Padding(
                            padding: const .symmetric(vertical: 20),
                            child: AppFilledButton(
                              onPressed: () => context.pushNamed(AppRoutes.buy),
                              label: S.of(context).buyRealUnit,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
