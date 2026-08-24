import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/models/asset.dart';
import 'package:realunit_wallet/models/portfolio_value_point.dart';
import 'package:realunit_wallet/models/price_point.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_account_service.dart';
import 'package:realunit_wallet/packages/service/price_service.dart';
import 'package:realunit_wallet/packages/utils/default_assets.dart';
import 'package:realunit_wallet/styles/currency.dart';

part 'dashboard_event.dart';
part 'dashboard_state.dart';

class DashboardBloc extends Bloc<DashboardEvent, DashboardState> {
  DashboardBloc(
    this._priceService,
    this._accountService, {
    required this.asset,
    required Currency initialCurrency,
  }) : super(
         DashboardState(
           price: BigInt.zero,
           priceChart: [],
           portfolioHistory: [],
           currency: initialCurrency,
         ),
       ) {
    on<RefreshPriceEvent>(_onRefreshPriceEvent);
    on<RefreshPriceChartEvent>(_onRefreshPriceChartEvent);
    on<RefreshPortfolioHistoryEvent>(_onRefreshPortfolioHistoryEvent);
    on<CurrencyChangedEvent>(_onCurrencyChangedEvent);
    refresh();
  }

  void refresh() {
    add(RefreshPriceEvent());
    add(RefreshPriceChartEvent());
    add(RefreshPortfolioHistoryEvent());
  }

  final APriceService _priceService;
  final RealUnitAccountService _accountService;
  final Asset asset;

  Future<void> _onRefreshPriceEvent(RefreshPriceEvent event, Emitter<DashboardState> emit) async {
    final currency = state.currency;
    final price = await _priceService.getPriceOfAsset(realUnitAsset, currency);
    if (state.currency != currency) return;
    emit(state.copyWith(price: price));
  }

  Future<void> _onRefreshPriceChartEvent(
    RefreshPriceChartEvent event,
    Emitter<DashboardState> emit,
  ) async {
    final currency = state.currency;
    final priceChart = await _priceService.getPriceChart(realUnitAsset, currency);
    if (state.currency != currency) return;
    emit(state.copyWith(priceChart: priceChart));
  }

  Future<void> _onRefreshPortfolioHistoryEvent(
    RefreshPortfolioHistoryEvent event,
    Emitter<DashboardState> emit,
  ) async {
    final currency = state.currency;
    final portfolioHistory = await _accountService.getPortfolioHistory(currency);
    if (state.currency != currency) return;
    emit(state.copyWith(portfolioHistory: portfolioHistory));
  }

  void _onCurrencyChangedEvent(CurrencyChangedEvent event, Emitter<DashboardState> emit) {
    emit(state.copyWith(currency: event.currency));
    refresh();
  }
}
