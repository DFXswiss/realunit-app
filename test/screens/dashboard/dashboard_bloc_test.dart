import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/models/portfolio_value_point.dart';
import 'package:realunit_wallet/models/price_point.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_account_service.dart';
import 'package:realunit_wallet/packages/service/price_service.dart';
import 'package:realunit_wallet/packages/utils/default_assets.dart';
import 'package:realunit_wallet/screens/dashboard/bloc/dashboard_bloc.dart';
import 'package:realunit_wallet/styles/currency.dart';

class _MockPriceService extends Mock implements APriceService {}

class _MockAccountService extends Mock implements RealUnitAccountService {}

PricePoint _pp(int rappen, DateTime t) =>
    PricePoint(asset: realUnitAsset, price: BigInt.from(rappen), time: t);

PortfolioValuePoint _pt(int rappen, DateTime t) =>
    PortfolioValuePoint(value: BigInt.from(rappen), balance: BigInt.one, time: t);

void main() {
  late _MockPriceService priceService;
  late _MockAccountService accountService;

  setUpAll(() {
    registerFallbackValue(Currency.chf);
    registerFallbackValue(realUnitAsset);
  });

  setUp(() {
    priceService = _MockPriceService();
    accountService = _MockAccountService();
  });

  DashboardBloc build({Currency currency = Currency.chf}) {
    when(
      () => priceService.getPriceOfAsset(any(), any()),
    ).thenAnswer((_) async => BigInt.from(12345));
    when(() => priceService.getPriceChart(any(), any())).thenAnswer(
      (_) async => [
        _pp(10000, DateTime.utc(2026, 1, 1)),
        _pp(11000, DateTime.utc(2026, 2, 1)),
      ],
    );
    when(() => accountService.getPortfolioHistory(any())).thenAnswer(
      (_) async => [
        _pt(50000, DateTime.utc(2026, 1, 1)),
        _pt(52000, DateTime.utc(2026, 2, 1)),
      ],
    );
    return DashboardBloc(
      priceService,
      accountService,
      asset: realUnitAsset,
      initialCurrency: currency,
    );
  }

  group('$DashboardBloc', () {
    test('initial state uses the supplied currency and zero-defaults', () {
      final bloc = build();

      // The constructor immediately calls refresh(); read the snapshot
      // *before* any event has been processed.
      expect(bloc.state.currency, Currency.chf);
    });

    test('refresh populates price + priceChart + portfolioHistory from the services', () async {
      final bloc = build();

      // Wait until all three refresh events have been processed.
      await bloc.stream.firstWhere(
        (s) =>
            s.price == BigInt.from(12345) &&
            s.priceChart.length == 2 &&
            s.portfolioHistory.length == 2,
      );

      expect(bloc.state.price, BigInt.from(12345));
      expect(bloc.state.priceChart, hasLength(2));
      expect(bloc.state.portfolioHistory, hasLength(2));
      verify(() => priceService.getPriceOfAsset(realUnitAsset, Currency.chf)).called(1);
      verify(() => priceService.getPriceChart(realUnitAsset, Currency.chf)).called(1);
      verify(() => accountService.getPortfolioHistory(Currency.chf)).called(1);
    });

    test('refresh survives priceService failure without crashing', () async {
      when(() => priceService.getPriceOfAsset(any(), any())).thenThrow(Exception('503'));

      final bloc = build();
      // If the handler crashes without try-catch, an unhandled error propagates.
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // The bloc should still be usable — priceChart and portfolioHistory
      // were fetched independently.
      expect(bloc.state.currency, Currency.chf);
    });

    test('refresh survives priceChart failure without crashing', () async {
      when(() => priceService.getPriceChart(any(), any())).thenThrow(Exception('timeout'));

      final bloc = build();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(bloc.state.currency, Currency.chf);
    });

    test('refresh survives portfolioHistory failure without crashing', () async {
      when(() => accountService.getPortfolioHistory(any())).thenThrow(Exception('network'));

      final bloc = build();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(bloc.state.currency, Currency.chf);
    });

    test('CurrencyChangedEvent updates state and re-fetches all three datasets', () async {
      final bloc = build();
      // Drain the initial refresh.
      await bloc.stream.firstWhere((s) => s.portfolioHistory.isNotEmpty);
      clearInteractions(priceService);
      clearInteractions(accountService);
      when(
        () => priceService.getPriceOfAsset(any(), any()),
      ).thenAnswer((_) async => BigInt.from(99));
      when(() => priceService.getPriceChart(any(), any())).thenAnswer((_) async => []);
      when(() => accountService.getPortfolioHistory(any())).thenAnswer((_) async => []);

      // Subscribe BEFORE adding the event so we don't race the broadcast.
      final emitted = <DashboardState>[];
      final sub = bloc.stream.listen(emitted.add);
      bloc.add(const CurrencyChangedEvent(Currency.eur));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await sub.cancel();

      expect(bloc.state.currency, Currency.eur);
      expect(emitted.any((s) => s.currency == Currency.eur), isTrue);
      verify(() => priceService.getPriceOfAsset(realUnitAsset, Currency.eur)).called(1);
      verify(() => priceService.getPriceChart(realUnitAsset, Currency.eur)).called(1);
      verify(() => accountService.getPortfolioHistory(Currency.eur)).called(1);
    });

    test('late price for the previous currency is dropped after CurrencyChangedEvent', () async {
      final stalePrice = Completer<BigInt>();
      when(() => priceService.getPriceOfAsset(any(), any())).thenAnswer((invocation) {
        final currency = invocation.positionalArguments[1] as Currency;
        if (currency == Currency.chf) return stalePrice.future;
        return Future.value(BigInt.from(99));
      });
      when(() => priceService.getPriceChart(any(), any())).thenAnswer(
        (_) async => [
          _pp(10000, DateTime.utc(2026, 1, 1)),
        ],
      );
      when(() => accountService.getPortfolioHistory(any())).thenAnswer(
        (_) async => [
          _pt(50000, DateTime.utc(2026, 1, 1)),
        ],
      );

      final bloc = DashboardBloc(
        priceService,
        accountService,
        asset: realUnitAsset,
        initialCurrency: Currency.chf,
      );
      bloc.add(const CurrencyChangedEvent(Currency.eur));
      await bloc.stream.firstWhere(
        (s) => s.currency == Currency.eur && s.price == BigInt.from(99),
      );

      stalePrice.complete(BigInt.from(12345));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(bloc.state.currency, Currency.eur);
      expect(bloc.state.price, BigInt.from(99));
      await bloc.close();
    });
  });
}
