import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/models/price_point.dart';
import 'package:realunit_wallet/packages/utils/format_fixed.dart';
import 'package:realunit_wallet/screens/dashboard/bloc/price_chart/price_chart_state.dart';
import 'package:realunit_wallet/screens/dashboard/models/time_period.dart';

class PriceChartCubit extends Cubit<PriceChartState> {
  PriceChartCubit(this._prices)
    : super(
        const PriceChartState(
          selectedPeriod: TimePeriod.all,
          visibleSpots: [],
          minX: 0,
          maxX: 0,
          minY: 0,
          maxY: 1,
        ),
      ) {
    _calculateChartData();
  }

  final List<PricePoint> _prices;

  void selectPeriod(TimePeriod period) {
    if (period == state.selectedPeriod) return;
    emit(state.copyWith(selectedPeriod: period));
    _calculateChartData();
  }

  void _calculateChartData() {
    if (_prices.isEmpty) {
      emit(
        state.copyWith(
          visibleSpots: [],
          minX: 0,
          maxX: 0,
          minY: 0,
          maxY: 1,
        ),
      );
      return;
    }

    final now = DateTime.now();

    // Calculate minX and maxXbased on selected period
    final minX = switch (state.selectedPeriod) {
      TimePeriod.oneWeek => DateTime(
        now.year,
        now.month,
        now.day - 7,
      ).millisecondsSinceEpoch.toDouble(),
      TimePeriod.oneMonth => DateTime(
        now.year,
        now.month - 1,
        now.day,
      ).millisecondsSinceEpoch.toDouble(),
      TimePeriod.threeMonths => DateTime(
        now.year,
        now.month - 3,
        now.day,
      ).millisecondsSinceEpoch.toDouble(),
      TimePeriod.oneYear => DateTime(
        now.year - 1,
        now.month,
        now.day,
      ).millisecondsSinceEpoch.toDouble(),
      TimePeriod.all => _prices.first.time.millisecondsSinceEpoch.toDouble(),
    };
    final maxX = _prices.last.time.millisecondsSinceEpoch.toDouble();

    // Filter price points to those within the selected time period (between minX and maxX)
    final visibleSpots = _prices
        .where(
          (p) => p.time.millisecondsSinceEpoch >= minX && p.time.millisecondsSinceEpoch <= maxX,
        )
        .map(
          (p) => FlSpot(
            p.time.millisecondsSinceEpoch.toDouble(),
            double.parse(formatFixed(p.price, 2)),
          ),
        )
        .toList();

    if (visibleSpots.isEmpty) {
      emit(
        state.copyWith(
          visibleSpots: [],
          minX: minX,
          maxX: maxX,
          minY: 0,
          maxY: 1,
        ),
      );
      return;
    }

    // Calculate minY and maxY from the visible spots, with some padding (10%)
    var min = visibleSpots.first.y;
    var max = visibleSpots.first.y;

    for (final spot in visibleSpots) {
      if (spot.y < min) min = spot.y;
      if (spot.y > max) max = spot.y;
    }
    final padding = (max - min) * 0.1;

    emit(
      state.copyWith(
        visibleSpots: visibleSpots,
        minX: minX,
        maxX: maxX,
        minY: min - padding,
        maxY: max + padding,
      ),
    );
  }
}
