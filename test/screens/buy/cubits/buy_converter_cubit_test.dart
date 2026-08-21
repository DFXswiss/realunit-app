import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_brokerbot_service.dart';
import 'package:realunit_wallet/packages/service/dfx/models/brokerbot/dfx_buy_price_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/brokerbot/dfx_buy_shares_dto.dart';
import 'package:realunit_wallet/screens/buy/cubits/buy_converter/buy_converter_cubit.dart';
import 'package:realunit_wallet/styles/currency.dart';

class _MockBrokerbotService extends Mock implements DfxBrokerbotService {}

void main() {
  late _MockBrokerbotService service;

  setUpAll(() {
    registerFallbackValue(Currency.chf);
  });

  setUp(() {
    service = _MockBrokerbotService();
  });

  group('$BuyConverterCubit', () {
    test('initial state is empty with CHF', () {
      final cubit = BuyConverterCubit(service);

      expect(cubit.state.fiatText, '');
      expect(cubit.state.sharesText, '');
      expect(cubit.state.currency, Currency.chf);
      expect(cubit.state.loading, isFalse);
    });

    test('onFiatChanged debounces, then writes the converted shares', () async {
      when(() => service.getBuyShares(any(), any())).thenAnswer(
        (_) async => BrokerbotBuySharesDto(
          shares: 7,
          pricePerShare: 12.5,
          availableShares: 100,
        ),
      );

      final cubit = BuyConverterCubit(service);
      await cubit.onFiatChanged('100');
      // Past the 100ms debounce.
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(cubit.state.fiatText, '87.50');
      expect(cubit.state.sharesText, '7');
      expect(cubit.state.loading, isFalse);
      verify(() => service.getBuyShares('100', Currency.chf)).called(1);
    });

    test('onFiatChanged snaps CHF to shares × list in Rappen (10000 → 7299 × 1.37 = 9999.63)', () async {
      when(() => service.getBuyShares(any(), any())).thenAnswer(
        (_) async => BrokerbotBuySharesDto(
          shares: 7299,
          pricePerShare: 1.37,
          availableShares: 50000,
        ),
      );

      final cubit = BuyConverterCubit(service);
      await cubit.onFiatChanged('10000');
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(cubit.state.sharesText, '7299');
      expect(cubit.state.fiatText, '9999.63');
    });

    test('onFiatChanged debounces — only the latest value reaches the service', () async {
      when(() => service.getBuyShares(any(), any())).thenAnswer(
        (_) async => BrokerbotBuySharesDto(
          shares: 9,
          pricePerShare: 1,
          availableShares: 99,
        ),
      );

      final cubit = BuyConverterCubit(service);
      // Three rapid keystrokes; only the last should reach the service.
      await cubit.onFiatChanged('1');
      await cubit.onFiatChanged('12');
      await cubit.onFiatChanged('123');
      await Future<void>.delayed(const Duration(milliseconds: 250));

      verify(() => service.getBuyShares('123', any())).called(1);
      verifyNever(() => service.getBuyShares('1', any()));
      verifyNever(() => service.getBuyShares('12', any()));
    });

    test('onFiatChanged keeps state intact when the service throws', () async {
      when(
        () => service.getBuyShares(any(), any()),
      ).thenAnswer((_) async => throw Exception('bad input'));

      final cubit = BuyConverterCubit(service);
      await cubit.onFiatChanged('-1');
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(cubit.state.fiatText, '-1');
      expect(cubit.state.sharesText, '');
      expect(cubit.state.loading, isFalse);
    });

    test(
      'onSharesChanged debounces, then writes the converted fiat with matching fractional digits',
      () async {
        when(() => service.getBuyPrice(any(), any())).thenAnswer(
          (_) async => BrokerbotBuyPriceDto(
            totalCost: 125.5,
            pricePerShare: 25.1,
            availableShares: 100,
          ),
        );

        final cubit = BuyConverterCubit(service);
        // Input has 3 fractional digits → output has 3.
        await cubit.onSharesChanged('5.000');
        await Future<void>.delayed(const Duration(milliseconds: 250));

        expect(cubit.state.sharesText, '5.000');
        expect(cubit.state.fiatText, '125.500');
      },
    );

    test('onSharesChanged keeps state intact when the service throws', () async {
      // Mirror of the `onFiatChanged` throw guard: the sell-side debounce
      // body must not leak a state.loading=true when getBuyPrice fails.
      when(
        () => service.getBuyPrice(any(), any()),
      ).thenAnswer((_) async => throw Exception('throttle'));

      final cubit = BuyConverterCubit(service);
      await cubit.onSharesChanged('5');
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(cubit.state.sharesText, '5');
      expect(cubit.state.fiatText, '');
      expect(cubit.state.loading, isFalse);
    });

    test('onSharesChanged uses 2 fractional digits when input has no dot', () async {
      when(() => service.getBuyPrice(any(), any())).thenAnswer(
        (_) async => BrokerbotBuyPriceDto(
          totalCost: 125.5,
          pricePerShare: 25.1,
          availableShares: 100,
        ),
      );

      final cubit = BuyConverterCubit(service);
      await cubit.onSharesChanged('5');
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(cubit.state.fiatText, '125.50');
    });

    test(
      'onCurrencyChanged refetches shares with the new currency and emits both fields',
      () async {
        when(() => service.getBuyShares(any(), any())).thenAnswer(
          (_) async => BrokerbotBuySharesDto(
            shares: 3,
            pricePerShare: 10,
            availableShares: 100,
          ),
        );

        final cubit = BuyConverterCubit(service);
        await cubit.onCurrencyChanged(Currency.eur);

        expect(cubit.state.currency, Currency.eur);
        expect(cubit.state.sharesText, '3');
        expect(cubit.state.loading, isFalse);
        verify(() => service.getBuyShares('', Currency.eur)).called(1);
      },
    );

    test('onCurrencyChanged still flips currency even on service error', () async {
      when(
        () => service.getBuyShares(any(), any()),
      ).thenAnswer((_) async => throw Exception('throttle'));

      final cubit = BuyConverterCubit(service);
      await cubit.onCurrencyChanged(Currency.eur);

      expect(cubit.state.currency, Currency.eur);
      expect(cubit.state.loading, isFalse);
    });

    test(
      'fiat race: stale in-flight response is dropped when user typed further',
      () async {
        // Reproduces the production bug: user types fast enough that the
        // debounce timer for an intermediate value (e.g. "460") has already
        // fired and started its API call by the time they type the last
        // digit ("4600"). Both API calls are now in flight; without the
        // seq guard, the slower response wins last-write-wins — exactly
        // the "4600 CHF → 321 shares (=460/1.43)" observation in v1.0.67.
        final c460 = Completer<BrokerbotBuySharesDto>();
        final c4600 = Completer<BrokerbotBuySharesDto>();
        when(() => service.getBuyShares('460', any())).thenAnswer((_) => c460.future);
        when(() => service.getBuyShares('4600', any())).thenAnswer((_) => c4600.future);

        final cubit = BuyConverterCubit(service);

        await cubit.onFiatChanged('460');
        await Future<void>.delayed(const Duration(milliseconds: 150)); // timer fires → API_460 in flight
        await cubit.onFiatChanged('4600');
        await Future<void>.delayed(const Duration(milliseconds: 150)); // timer fires → API_4600 in flight

        // Pathological response order: the NEWER request resolves first…
        c4600.complete(BrokerbotBuySharesDto(
          shares: 3216,
          pricePerShare: 1.43,
          availableShares: 100,
        ));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(cubit.state.sharesText, '3216');

        // …and the OLDER request resolves later. Without the seq guard,
        // this would overwrite sharesText with '321'.
        c460.complete(BrokerbotBuySharesDto(
          shares: 321,
          pricePerShare: 1.43,
          availableShares: 100,
        ));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(
          cubit.state.sharesText,
          '3216',
          reason: 'stale seq=1 response for "460" must NOT overwrite seq=2 result for "4600"',
        );
      },
    );

    test(
      'shares race: stale in-flight response is dropped when user typed further',
      () async {
        // Symmetric pin for the onSharesChanged debounce path.
        final c5 = Completer<BrokerbotBuyPriceDto>();
        final c50 = Completer<BrokerbotBuyPriceDto>();
        when(() => service.getBuyPrice('5', any())).thenAnswer((_) => c5.future);
        when(() => service.getBuyPrice('50', any())).thenAnswer((_) => c50.future);

        final cubit = BuyConverterCubit(service);

        await cubit.onSharesChanged('5');
        await Future<void>.delayed(const Duration(milliseconds: 150));
        await cubit.onSharesChanged('50');
        await Future<void>.delayed(const Duration(milliseconds: 150));

        c50.complete(BrokerbotBuyPriceDto(
          totalCost: 71.50,
          pricePerShare: 1.43,
          availableShares: 100,
        ));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(cubit.state.fiatText, '71.50');

        c5.complete(BrokerbotBuyPriceDto(
          totalCost: 7.15,
          pricePerShare: 1.43,
          availableShares: 100,
        ));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(
          cubit.state.fiatText,
          '71.50',
          reason: 'stale in-flight onSharesChanged response must not overwrite newer one',
        );
      },
    );

    test(
      'onCurrencyChanged: superseded in-flight response is dropped, but the currency flip survives',
      () async {
        // User changes currency to EUR, then quickly types a new fiat
        // amount before the EUR conversion returns. The EUR-conversion
        // shares result must not land; but the currency picker must
        // already reflect EUR because we flip it eagerly before the await.
        final cEur = Completer<BrokerbotBuySharesDto>();
        when(() => service.getBuyShares(any(), Currency.eur)).thenAnswer((_) => cEur.future);
        when(() => service.getBuyShares('1000', Currency.eur)).thenAnswer(
          (_) async => BrokerbotBuySharesDto(
            shares: 700,
            pricePerShare: 1.43,
            availableShares: 100,
          ),
        );

        final cubit = BuyConverterCubit(service);
        // ignore: unawaited_futures
        cubit.onCurrencyChanged(Currency.eur);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(cubit.state.currency, Currency.eur, reason: 'currency flips immediately');

        await cubit.onFiatChanged('1000');
        await Future<void>.delayed(const Duration(milliseconds: 250));

        cEur.complete(BrokerbotBuySharesDto(
          shares: 0,
          pricePerShare: 1.43,
          availableShares: 100,
        ));
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(cubit.state.currency, Currency.eur);
        expect(cubit.state.sharesText, '700',
            reason: 'the superseded onCurrencyChanged response (shares=0) must be dropped');
      },
    );

    test('close() cancels pending debounce timers', () async {
      when(() => service.getBuyShares(any(), any())).thenAnswer(
        (_) async => BrokerbotBuySharesDto(
          shares: 1,
          pricePerShare: 1,
          availableShares: 1,
        ),
      );

      final cubit = BuyConverterCubit(service);
      await cubit.onFiatChanged('5');
      // Close before the 100ms debounce fires.
      await cubit.close();
      await Future<void>.delayed(const Duration(milliseconds: 250));

      verifyNever(() => service.getBuyShares(any(), any()));
    });

    test('does not emit after close', () async {
      final completer = Completer<BrokerbotBuySharesDto>();
      when(() => service.getBuyShares(any(), any())).thenAnswer((_) => completer.future);

      final cubit = BuyConverterCubit(service);
      await cubit.onFiatChanged('100');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await cubit.close();
      completer.complete(
        BrokerbotBuySharesDto(
          shares: 1,
          pricePerShare: 100,
          availableShares: 100,
        ),
      );
    });
  });
}
