import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/models/price_point.dart';
import 'package:realunit_wallet/packages/utils/format_fixed.dart';
import 'package:realunit_wallet/screens/dashboard/bloc/price_chart/price_chart_cubit.dart';
import 'package:realunit_wallet/screens/dashboard/bloc/price_chart/price_chart_state.dart';
import 'package:realunit_wallet/screens/dashboard/models/time_period.dart';
import 'package:realunit_wallet/screens/dashboard/widgets/price_chart.dart';
import 'package:realunit_wallet/screens/dashboard/widgets/time_period_selection_button.dart';
import 'package:realunit_wallet/screens/settings/bloc/settings_bloc.dart';
import 'package:realunit_wallet/styles/colors.dart';

class DashboardPriceWidget extends StatelessWidget {
  final BigInt price;
  final List<PricePoint> priceChart;

  const DashboardPriceWidget({
    super.key,
    required this.price,
    required this.priceChart,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      key: ValueKey(priceChart.hashCode),
      create: (context) => PriceChartCubit(priceChart),
      child: DashboardPriceWidgetView(
        price: price,
        priceChart: priceChart,
      ),
    );
  }
}

class DashboardPriceWidgetView extends StatelessWidget {
  final BigInt price;
  final List<PricePoint> priceChart;

  const DashboardPriceWidgetView({
    super.key,
    required this.price,
    required this.priceChart,
  });

  @override
  Widget build(BuildContext context) => Container(
    margin: const .only(top: 8),
    width: .infinity,
    child: SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const .symmetric(vertical: 12, horizontal: 20),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        S.of(context).realunitStockprice,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: .w600,
                          color: RealUnitColors.basic.black,
                        ),
                        maxLines: 1,
                        overflow: .ellipsis,
                      ),
                    ),
                  ],
                ),
                Row(
                  crossAxisAlignment: .start,
                  children: [
                    BlocBuilder<SettingsBloc, SettingsState>(
                      builder: (context, state) {
                        return Text(
                          '${state.currency.code.toUpperCase()} ',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: .w600),
                        );
                      },
                    ),
                    Flexible(
                      child: Text(
                        price == BigInt.zero ? '--.--' : formatFixed(price, 2, trimZeros: false),
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: .w600),
                        maxLines: 1,
                        overflow: .ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const PriceChart(),
          BlocBuilder<PriceChartCubit, PriceChartState>(
            builder: (context, state) {
              return Padding(
                padding: const .symmetric(horizontal: 20.0),
                child: Row(
                  children: TimePeriod.values.map((period) {
                    return Expanded(
                      child: TimePeriodSelectionButton(
                        period.name(context).toUpperCase(),
                        isSelected: state.selectedPeriod == period,
                        onTap: () => context.read<PriceChartCubit>().selectPeriod(period),
                      ),
                    );
                  }).toList(),
                ),
              );
            },
          ),
        ],
      ),
    ),
  );
}
