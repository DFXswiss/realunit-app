import 'package:realunit_wallet/models/portfolio_value_point.dart';

/// Frozen handbook personas — synthetic, not live accounts.
///
/// Each history has ≥10 balance changes inside a 1-year window. Times are
/// local midnight so MAX (first/last fixture) and 1J (`DateTime.now()`
/// window) stay pixel-stable. Value is shares × 153 rappen (same unit price
/// as the existing dashboard portfolio golden).
///
/// As-of date for the handbook trade tables: 2026-08-28.
DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

PortfolioValuePoint _pt(int daysAgo, int shares) {
  return PortfolioValuePoint(
    value: BigInt.from(shares * 153),
    balance: BigInt.from(shares),
    time: _today().subtract(Duration(days: daysAgo)),
  );
}

/// K1 Monatskäufer — twelve equal +80 REALU buys, still holding 960.
List<PortfolioValuePoint> personaDcaHistory() => [
      _pt(335, 80),
      _pt(305, 160),
      _pt(275, 240),
      _pt(245, 320),
      _pt(215, 400),
      _pt(185, 480),
      _pt(155, 560),
      _pt(125, 640),
      _pt(95, 720),
      _pt(65, 800),
      _pt(35, 880),
      _pt(5, 960),
    ];

/// K2 Einmalkauf — one +5000 lump, then nine +50 top-ups, holding 5450.
List<PortfolioValuePoint> personaLumpHistory() => [
      _pt(350, 0),
      _pt(340, 5000),
      _pt(300, 5050),
      _pt(270, 5100),
      _pt(240, 5150),
      _pt(210, 5200),
      _pt(180, 5250),
      _pt(150, 5300),
      _pt(120, 5350),
      _pt(90, 5400),
      _pt(30, 5450),
    ];

/// K3 Verkauf auf 0 — eight buys then four sells to zero.
/// 1J still contains the rise; 1W is a flat zero line.
List<PortfolioValuePoint> personaExitHistory() => [
      _pt(320, 200),
      _pt(290, 400),
      _pt(260, 550),
      _pt(230, 700),
      _pt(200, 800),
      _pt(170, 900),
      _pt(140, 980),
      _pt(110, 1060),
      _pt(80, 860),
      _pt(50, 560),
      _pt(25, 260),
      _pt(10, 0),
      _pt(6, 0),
      _pt(1, 0),
      _pt(0, 0),
    ];

/// K4 Mix — interleaved buys and partial sells, holding 600.
List<PortfolioValuePoint> personaMixHistory() => [
      _pt(330, 150),
      _pt(300, 300),
      _pt(270, 250),
      _pt(240, 450),
      _pt(210, 550),
      _pt(180, 450),
      _pt(150, 530),
      _pt(120, 610),
      _pt(90, 550),
      _pt(60, 590),
      _pt(30, 630),
      _pt(5, 600),
    ];

/// K5 Aufstocken — twelve rising buys, holding 1800.
List<PortfolioValuePoint> personaScaleHistory() => [
      _pt(335, 40),
      _pt(305, 100),
      _pt(275, 180),
      _pt(245, 280),
      _pt(215, 400),
      _pt(185, 540),
      _pt(155, 700),
      _pt(125, 880),
      _pt(95, 1080),
      _pt(65, 1300),
      _pt(35, 1540),
      _pt(5, 1800),
    ];
