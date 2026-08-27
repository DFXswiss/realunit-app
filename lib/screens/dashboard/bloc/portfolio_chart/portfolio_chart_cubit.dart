import 'dart:math' as math;

import 'package:equatable/equatable.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/models/portfolio_value_point.dart';
import 'package:realunit_wallet/packages/utils/format_fixed.dart';
import 'package:realunit_wallet/screens/dashboard/models/time_period.dart';

part 'portfolio_chart_state.dart';

class PortfolioChartCubit extends Cubit<PortfolioChartState> {
  PortfolioChartCubit(this._prices)
    : super(
        const PortfolioChartState(
          selectedPeriod: TimePeriod.all,
          visibleSpots: [],
          minX: 0,
          maxX: 0,
          minY: 0,
          maxY: 1,
          horizontalLineValues: [],
        ),
      ) {
    _calculateChartData();
  }

  final List<PortfolioValuePoint> _prices;

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
          horizontalLineValues: [],
        ),
      );
      return;
    }

    final now = DateTime.now();

    // Calculate minX and maxXbased on selected period
    final firstPriceX = _prices.first.time.millisecondsSinceEpoch.toDouble();
    final startDate = switch (state.selectedPeriod) {
      TimePeriod.oneWeek => DateTime(
        now.year,
        now.month,
        now.day - 7,
      ),
      TimePeriod.oneMonth => DateTime(
        now.year,
        now.month - 1,
        now.day,
      ),
      TimePeriod.threeMonths => DateTime(
        now.year,
        now.month - 3,
        now.day,
      ),
      TimePeriod.oneYear => DateTime(
        now.year - 1,
        now.month,
        now.day,
      ),
      TimePeriod.all => _prices.first.time,
    };
    final minX = math.max(
      startDate.millisecondsSinceEpoch.toDouble(),
      firstPriceX,
    );
    final maxX = _prices.last.time.millisecondsSinceEpoch.toDouble();

    // Filter price points to those within the selected time period (between minX and maxX)
    final visibleSpots = _prices
        .where(
          (p) => p.time.millisecondsSinceEpoch >= minX && p.time.millisecondsSinceEpoch <= maxX,
        )
        .map(
          (p) => FlSpot(
            p.time.millisecondsSinceEpoch.toDouble(),
            double.parse(formatFixed(p.value, 2)),
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
          horizontalLineValues: [],
        ),
      );
      return;
    }

    // Calculate minY and maxY from the visible spots
    var min = visibleSpots.first.y;
    var max = visibleSpots.first.y;
    var sum = 0.0;

    for (final spot in visibleSpots) {
      if (spot.y < min) min = spot.y;
      if (spot.y > max) max = spot.y;
      sum += spot.y;
    }

    // Calculate average to center the chart
    final average = sum / visibleSpots.length;

    // Find the maximum deviation from average
    final maxDeviation = math.max(
      (max - average).abs(),
      (min - average).abs(),
    );

    // Add padding (20% extra space) and ensure minimum range for visual clarity.
    // `average * 0.05` is 0 when the series is all zeros, which used to collapse
    // minY/maxY and hide the LineChart; fall back to 5.0 currency units then.
    final relativeFloor = average.abs() * 0.05;
    final minFloor = relativeFloor > 0 ? relativeFloor : 5.0;
    final paddedDeviation = math.max(maxDeviation * 1.2, minFloor);

    // Calculate rounded horizontal line values centered around average
    final horizontalLineValues = _calculateHorizontalLines(paddedDeviation, average);

    final minY = horizontalLineValues.first;
    final maxY = horizontalLineValues.last;

    emit(
      state.copyWith(
        visibleSpots: visibleSpots,
        minX: minX,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
        horizontalLineValues: horizontalLineValues,
      ),
    );
  }

  List<double> _calculateHorizontalLines(double deviation, double average) {
    const lineCount = 6;
    const intervalCount = lineCount - 1;

    // Callers always pass a positive deviation (relative 5% floor, or 5.0
    // for an all-zero series). A non-positive value would collapse minY/maxY.

    // Calculate an interval that spans the data range
    final rawInterval = (2 * deviation) / intervalCount;
    final interval = _roundToNumber(rawInterval);

    // Center the lines around the average by rounding it to the nearest interval
    final centerLine = (average / interval).round() * interval;

    // Position the bottom line so the center is roughly in the middle.
    // Keep minY >= 0 for positive holdings; an all-zero series must be allowed
    // below 0 so the stroke is not clipped to the axis.
    final unclampedBottom = centerLine - 3 * interval;
    final bottomLine = average > 0 ? math.max(0.0, unclampedBottom) : unclampedBottom;

    return List.generate(lineCount, (i) => bottomLine + i * interval);
  }

  double _roundToNumber(double value) {
    if (value <= 0) return 1;

    // Get the order of magnitude (e.g., 350 -> 100, 4500 -> 1000)
    final magnitude = math.pow(10, (math.log(value) / math.ln10).floor()).toDouble();

    // Normalize to 1-10 range and snap to nearest "nice" number (1, 2, 5, or 10)
    final normalized = value / magnitude;
    final niceNumber = switch (normalized) {
      <= 1 => 1,
      <= 2 => 2,
      <= 5 => 5,
      _ => 10,
    };

    return niceNumber * magnitude;
  }
}
