import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/models/portfolio_value_point.dart';
import 'package:realunit_wallet/screens/dashboard/bloc/portfolio_chart/portfolio_chart_cubit.dart';
import 'package:realunit_wallet/screens/dashboard/models/time_period.dart';

PortfolioValuePoint _pt(DateTime time, int rappen) => PortfolioValuePoint(
  value: BigInt.from(rappen),
  balance: BigInt.one,
  time: time,
);

void main() {
  group('$PortfolioChartCubit', () {
    test('empty input yields the zero-window initial-shape state', () {
      final cubit = PortfolioChartCubit(const []);

      expect(cubit.state.visibleSpots, isEmpty);
      expect(cubit.state.minX, 0);
      expect(cubit.state.maxX, 0);
      expect(cubit.state.minY, 0);
      expect(cubit.state.maxY, 1);
      expect(cubit.state.horizontalLineValues, isEmpty);
    });

    test('initial state defaults to TimePeriod.all', () {
      // Regression guard for the dashboard default: a freshly constructed
      // cubit must select the full range, not a clipped window.
      final cubit = PortfolioChartCubit([
        _pt(DateTime.utc(2026, 1, 1), 1000),
        _pt(DateTime.utc(2026, 2, 1), 2000),
      ]);

      expect(cubit.state.selectedPeriod, TimePeriod.all);
    });

    test('empty input keeps zero-window after selectPeriod to oneMonth', () async {
      // Guards the empty-input early-return branch when period changes.
      final cubit = PortfolioChartCubit(const []);
      final emitted = <PortfolioChartState>[];
      final sub = cubit.stream.listen(emitted.add);

      cubit.selectPeriod(TimePeriod.oneMonth);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(cubit.state.selectedPeriod, TimePeriod.oneMonth);
      expect(cubit.state.visibleSpots, isEmpty);
      expect(cubit.state.horizontalLineValues, isEmpty);
      // Cubit emits the period change; the subsequent zero-window re-emit
      // from `_calculateChartData` is deduped by `Equatable` because the
      // zero-window state is unchanged. Only the period flip is observable.
      expect(emitted, hasLength(1));
      expect(emitted.single.selectedPeriod, TimePeriod.oneMonth);
    });

    test('all-period populates visibleSpots scaled by 100', () {
      final points = [
        _pt(DateTime.utc(2026, 1, 1), 50000), // 500.00
        _pt(DateTime.utc(2026, 2, 1), 60000), // 600.00
      ];

      final cubit = PortfolioChartCubit(points);
      cubit.selectPeriod(TimePeriod.all);

      expect(cubit.state.visibleSpots, hasLength(2));
      expect(cubit.state.visibleSpots.first.y, 500.0);
      expect(cubit.state.visibleSpots.last.y, 600.0);
      // 6 horizontal lines are always produced when there is data.
      expect(cubit.state.horizontalLineValues, hasLength(6));
      // minY / maxY come from the first/last horizontal line.
      expect(cubit.state.minY, cubit.state.horizontalLineValues.first);
      expect(cubit.state.maxY, cubit.state.horizontalLineValues.last);
    });

    test('flat-value series still spreads lines via the 5% floor (no Y-collapse)', () {
      // When all values are equal, the cubit floors the padded deviation at
      // `average * 0.05` so the chart still has a visible Y-range instead of
      // collapsing to a single horizontal line.
      //
      // Dates are anchored to `DateTime.now()` so the series stays realistic
      // and robust against any future period-clipping; this test exercises the
      // default period (`TimePeriod.all`), which keeps the full series visible.
      final now = DateTime.now();
      final points = [
        _pt(now.subtract(const Duration(days: 60)), 10000),
        _pt(now.subtract(const Duration(days: 30)), 10000),
        _pt(now.subtract(const Duration(days: 1)), 10000),
      ];

      final cubit = PortfolioChartCubit(points);

      expect(cubit.state.horizontalLineValues, hasLength(6));
      // average 100 → floor 5 → rawInterval 2 → niceNumber 2 → bottom 94.
      expect(
        cubit.state.horizontalLineValues,
        [94.0, 96.0, 98.0, 100.0, 102.0, 104.0],
      );
      expect(cubit.state.minY, 94.0);
      expect(cubit.state.maxY, 104.0);
    });

    test('zero-average flat series keeps a visible Y-range from 0', () {
      // average 0 → relative 5% floor is 0 → absolute floor 5 → interval 2
      // → lines start at 0 (holdings never go negative).
      final points = [
        _pt(DateTime.utc(2026, 1, 1), 0),
        _pt(DateTime.utc(2026, 2, 1), 0),
      ];

      final cubit = PortfolioChartCubit(points);
      cubit.selectPeriod(TimePeriod.all);

      expect(cubit.state.visibleSpots, hasLength(2));
      expect(cubit.state.visibleSpots.every((s) => s.y == 0.0), isTrue);
      expect(
        cubit.state.horizontalLineValues,
        [0.0, 2.0, 4.0, 6.0, 8.0, 10.0],
      );
      expect(cubit.state.minY, 0.0);
      expect(cubit.state.maxY, 10.0);
    });

    test('oneWeek all-zero window keeps a visible Y-range around 0', () {
      final now = DateTime.now();
      final points = [
        _pt(now.subtract(const Duration(days: 60)), 0),
        _pt(now.subtract(const Duration(days: 3)), 0),
        _pt(now.subtract(const Duration(days: 1)), 0),
      ];

      final cubit = PortfolioChartCubit(points);
      cubit.selectPeriod(TimePeriod.oneWeek);

      expect(cubit.state.visibleSpots, hasLength(3));
      expect(cubit.state.visibleSpots.every((s) => s.y == 0.0), isTrue);
      expect(cubit.state.visibleSpots.first.x, cubit.state.minX);
      expect(cubit.state.minY, 0.0);
      expect(cubit.state.maxY, 10.0);
      expect(cubit.state.minY < cubit.state.maxY, isTrue);
    });

    test('selectPeriod to the same period is a no-op (no emit)', () async {
      final cubit = PortfolioChartCubit([_pt(DateTime.utc(2026, 1, 1), 5000)]);
      final emitted = <PortfolioChartState>[];
      final sub = cubit.stream.listen(emitted.add);

      cubit.selectPeriod(cubit.state.selectedPeriod);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(emitted, isEmpty);
    });

    test('selectPeriod to oneWeek narrows visibleSpots to the 7-day window', () {
      final now = DateTime.now();
      final old = _pt(now.subtract(const Duration(days: 60)), 5000);
      final recent = _pt(now.subtract(const Duration(days: 2)), 6000);

      final cubit = PortfolioChartCubit([old, recent]);
      cubit.selectPeriod(TimePeriod.oneWeek);

      expect(cubit.state.selectedPeriod, TimePeriod.oneWeek);
      expect(cubit.state.visibleSpots, hasLength(2));
      expect(cubit.state.visibleSpots.first.x, cubit.state.minX);
      expect(cubit.state.visibleSpots.first.y, 50.0);
      expect(cubit.state.visibleSpots.last.y, 60.0);
    });

    test('selectPeriod to oneMonth narrows visibleSpots to the 1-month window', () {
      final now = DateTime.now();
      final old = _pt(now.subtract(const Duration(days: 120)), 5000);
      final recent = _pt(now.subtract(const Duration(days: 10)), 7000);

      final cubit = PortfolioChartCubit([old, recent]);
      cubit.selectPeriod(TimePeriod.oneMonth);

      expect(cubit.state.selectedPeriod, TimePeriod.oneMonth);
      expect(cubit.state.visibleSpots, hasLength(2));
      expect(cubit.state.visibleSpots.first.x, cubit.state.minX);
      expect(cubit.state.visibleSpots.first.y, 50.0);
      expect(cubit.state.visibleSpots.last.y, 70.0);
    });

    test('selectPeriod to threeMonths narrows visibleSpots to the 3-month window', () {
      final now = DateTime.now();
      final old = _pt(now.subtract(const Duration(days: 200)), 5000);
      final recent = _pt(now.subtract(const Duration(days: 30)), 8000);

      final cubit = PortfolioChartCubit([old, recent]);
      cubit.selectPeriod(TimePeriod.threeMonths);

      expect(cubit.state.selectedPeriod, TimePeriod.threeMonths);
      expect(cubit.state.visibleSpots, hasLength(2));
      expect(cubit.state.visibleSpots.first.x, cubit.state.minX);
      expect(cubit.state.visibleSpots.first.y, 50.0);
      expect(cubit.state.visibleSpots.last.y, 80.0);
    });

    test('selectPeriod to oneYear narrows visibleSpots to the 1-year window', () {
      final now = DateTime.now();
      final old = _pt(now.subtract(const Duration(days: 730)), 5000);
      final recent = _pt(now.subtract(const Duration(days: 100)), 9000);

      final cubit = PortfolioChartCubit([old, recent]);
      cubit.selectPeriod(TimePeriod.oneYear);

      expect(cubit.state.selectedPeriod, TimePeriod.oneYear);
      expect(cubit.state.visibleSpots, hasLength(2));
      expect(cubit.state.visibleSpots.first.x, cubit.state.minX);
      expect(cubit.state.visibleSpots.first.y, 50.0);
      expect(cubit.state.visibleSpots.last.y, 90.0);
    });

    test('oneYear holds a pre-window zero across a gap so the line spans minX', () {
      // Customer-shaped 1J: last sample before the window is 0, next interior
      // sample is months later. Without the hold, the stroke started at 50%.
      final now = DateTime.now();
      final cubit = PortfolioChartCubit([
        _pt(now.subtract(const Duration(days: 370)), 0),
        _pt(now.subtract(const Duration(days: 180)), 0),
        _pt(now, 0),
      ]);
      cubit.selectPeriod(TimePeriod.oneYear);

      expect(cubit.state.visibleSpots.length, greaterThanOrEqualTo(3));
      expect(cubit.state.visibleSpots.first.x, cubit.state.minX);
      expect(cubit.state.visibleSpots.every((s) => s.y == 0.0), isTrue);
    });

    test('oneYear does not duplicate a sample that already sits on minX', () {
      final now = DateTime.now();
      final start = DateTime(now.year - 1, now.month, now.day);
      final cubit = PortfolioChartCubit([
        _pt(start.subtract(const Duration(days: 10)), 5000),
        _pt(start, 6000),
        _pt(now, 7000),
      ]);
      cubit.selectPeriod(TimePeriod.oneYear);

      expect(cubit.state.visibleSpots, hasLength(2));
      expect(cubit.state.visibleSpots.first.x, start.millisecondsSinceEpoch.toDouble());
      expect(cubit.state.visibleSpots.first.y, 60.0);
      expect(cubit.state.visibleSpots.last.y, 70.0);
    });

    test('minX is clamped to first price time even when the period predates it', () {
      // Guards `math.max(startDate, firstPriceX)`: when all data is recent
      // and the period window starts before the first price, minX must be
      // the first price's time, not the window start.
      final now = DateTime.now();
      final p1 = _pt(now.subtract(const Duration(days: 3)), 5000);
      final p2 = _pt(now.subtract(const Duration(days: 1)), 6000);

      final cubit = PortfolioChartCubit([p1, p2]);
      cubit.selectPeriod(TimePeriod.oneYear);

      expect(
        cubit.state.minX,
        p1.time.millisecondsSinceEpoch.toDouble(),
      );
    });

    test('large-magnitude flat series uses the 5% floor with a larger nice-number interval', () {
      // average 10000 → floor 500 → rawInterval 200 → niceNumber 200 →
      // centerLine 10000 → bottomLine 10000 - 600 = 9400.
      final points = [
        _pt(DateTime.utc(2026, 1, 1), 1000000),
        _pt(DateTime.utc(2026, 2, 1), 1000000),
      ];

      final cubit = PortfolioChartCubit(points);
      cubit.selectPeriod(TimePeriod.all);

      expect(
        cubit.state.horizontalLineValues,
        [9400.0, 9600.0, 9800.0, 10000.0, 10200.0, 10400.0],
      );
    });

    test('non-empty prices but all outside the selected window yield an empty visible chart', () {
      // Regression: PortfolioChartCubit used to crash with `Bad state: No
      // element` when every price fell outside the selected window. That is a
      // realistic state whenever the user narrows to a short period (here
      // oneWeek) while their only data points are older than the window.
      final points = [
        _pt(DateTime.utc(2020, 1, 1), 5000),
        _pt(DateTime.utc(2020, 2, 1), 6000),
      ];

      final cubit = PortfolioChartCubit(points);
      cubit.selectPeriod(TimePeriod.oneWeek);

      expect(cubit.state.visibleSpots, isEmpty);
      expect(cubit.state.horizontalLineValues, isEmpty);
      expect(cubit.state.minY, 0);
      expect(cubit.state.maxY, 1);
    });
  });
}
