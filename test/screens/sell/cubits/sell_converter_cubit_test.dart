import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_brokerbot_service.dart';
import 'package:realunit_wallet/packages/service/dfx/models/brokerbot/dfx_buy_price_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/brokerbot/dfx_sell_price_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/brokerbot/dfx_sell_shares_dto.dart';
import 'package:realunit_wallet/screens/sell/cubits/sell_converter/sell_converter_cubit.dart';
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

  group('$SellConverterCubit', () {
    test('initial state is empty with CHF', () {
      final cubit = SellConverterCubit(service);

      expect(cubit.state.fiatText, '');
      expect(cubit.state.sharesText, '');
      expect(cubit.state.currency, Currency.chf);
      expect(cubit.state.loading, isFalse);
    });

    test('onFiatChanged debounces, then writes shares from getSellShares', () async {
      when(() => service.getSellShares(any(), any())).thenAnswer(
        (_) async => BrokerbotSellSharesDto(
          targetAmount: 100,
          shares: 8,
          pricePerShare: 12.5,
          currency: 'CHF',
        ),
      );

      final cubit = SellConverterCubit(service);
      await cubit.onFiatChanged('100');
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(cubit.state.fiatText, '100');
      expect(cubit.state.sharesText, '8');
      expect(cubit.state.loading, isFalse);
      verify(() => service.getSellShares('100', Currency.chf)).called(1);
    });

    test('onFiatChanged respects an explicit currency argument', () async {
      when(() => service.getSellShares(any(), any())).thenAnswer(
        (_) async => BrokerbotSellSharesDto(
          targetAmount: 100,
          shares: 8,
          pricePerShare: 12.5,
          currency: 'EUR',
        ),
      );

      final cubit = SellConverterCubit(service);
      await cubit.onFiatChanged('100', currency: Currency.eur);
      await Future<void>.delayed(const Duration(milliseconds: 250));

      verify(() => service.getSellShares('100', Currency.eur)).called(1);
    });

    test('onFiatChanged debounce keeps only the latest value', () async {
      when(() => service.getSellShares(any(), any())).thenAnswer(
        (_) async => BrokerbotSellSharesDto(
          targetAmount: 1,
          shares: 1,
          pricePerShare: 1,
          currency: 'CHF',
        ),
      );

      final cubit = SellConverterCubit(service);
      await cubit.onFiatChanged('1');
      await cubit.onFiatChanged('12');
      await cubit.onFiatChanged('123');
      await Future<void>.delayed(const Duration(milliseconds: 250));

      verify(() => service.getSellShares('123', any())).called(1);
      verifyNever(() => service.getSellShares('1', any()));
      verifyNever(() => service.getSellShares('12', any()));
    });

    test('onFiatChanged leaves state stable on service error', () async {
      when(
        () => service.getSellShares(any(), any()),
      ).thenAnswer((_) async => throw Exception('throttle'));

      final cubit = SellConverterCubit(service);
      await cubit.onFiatChanged('5');
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(cubit.state.fiatText, '5');
      expect(cubit.state.sharesText, '');
      expect(cubit.state.loading, isFalse);
    });

    test('onFiatChanged clears stale sharesText when a later conversion fails', () async {
      when(() => service.getSellShares('300', any())).thenAnswer(
        (_) async => BrokerbotSellSharesDto(
          targetAmount: 300,
          shares: 209,
          pricePerShare: 1.43,
          currency: 'CHF',
        ),
      );
      when(() => service.getSellShares('1.000', any())).thenAnswer(
        (_) async => throw Exception('Shares request failed: amountInput is not valid'),
      );

      final cubit = SellConverterCubit(service);
      await cubit.onFiatChanged('300');
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(cubit.state.sharesText, '209');

      await cubit.onFiatChanged('1.000');
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(cubit.state.fiatText, '1.000');
      expect(cubit.state.sharesText, '');
      expect(cubit.state.loading, isFalse);
    });

    test('onSharesChanged writes estimatedAmount with matching fractional digits', () async {
      when(() => service.getSellPrice(any(), any())).thenAnswer(
        (_) async => BrokerbotSellPriceDto(
          shares: 10,
          estimatedAmount: 125.5,
          pricePerShare: 12.55,
          currency: 'CHF',
        ),
      );

      final cubit = SellConverterCubit(service);
      // 3 fractional digits in input → 3 in output.
      await cubit.onSharesChanged('10.000');
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(cubit.state.sharesText, '10.000');
      expect(cubit.state.fiatText, '125.500');
    });

    test('onSharesChanged leaves state stable on service error', () async {
      // Symmetry guard: the `onFiatChanged` throw path is already pinned;
      // the shares-side debounce body must also reset `loading=false`
      // instead of stranding the UI on a spinner.
      when(
        () => service.getSellPrice(any(), any()),
      ).thenAnswer((_) async => throw Exception('throttle'));

      final cubit = SellConverterCubit(service);
      await cubit.onSharesChanged('5');
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(cubit.state.sharesText, '5');
      expect(cubit.state.fiatText, '');
      expect(cubit.state.loading, isFalse);
    });

    test('onSharesChanged clears stale fiatText when a later conversion fails', () async {
      when(() => service.getSellPrice('5', any())).thenAnswer(
        (_) async => BrokerbotSellPriceDto(
          shares: 5,
          estimatedAmount: 7.15,
          pricePerShare: 1.43,
          currency: 'CHF',
        ),
      );
      when(() => service.getSellPrice('x', any())).thenAnswer(
        (_) async => throw Exception('SellPrice request failed: sharesInput is not valid'),
      );

      final cubit = SellConverterCubit(service);
      await cubit.onSharesChanged('5');
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(cubit.state.fiatText, '7.15');

      await cubit.onSharesChanged('x');
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(cubit.state.sharesText, 'x');
      expect(cubit.state.fiatText, '');
      expect(cubit.state.loading, isFalse);
    });

    test('onSharesChanged defaults to 2 fractional digits when input has no dot', () async {
      when(() => service.getSellPrice(any(), any())).thenAnswer(
        (_) async => BrokerbotSellPriceDto(
          shares: 10,
          estimatedAmount: 125.5,
          pricePerShare: 12.55,
          currency: 'CHF',
        ),
      );

      final cubit = SellConverterCubit(service);
      await cubit.onSharesChanged('10');
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(cubit.state.fiatText, '125.50');
    });

    test(
        'onCurrencyChanged re-quotes via the SELL price endpoint '
        '(issue #657 P4 S1 regression — used to call getBuyPrice)', () async {
      // The previous behaviour called getBuyPrice/totalCost on a currency
      // switch, rendering a buy-side quote as the sell "You receive" amount —
      // inconsistent with onSharesChanged, which quotes via getSellPrice.
      when(() => service.getBuyPrice(any(), any())).thenAnswer(
        (_) async => BrokerbotBuyPriceDto(
          totalCost: 50.0,
          pricePerShare: 5.0,
          availableShares: 100,
        ),
      );

      final cubit = SellConverterCubit(service);
      // Seed with some shares via onSharesChanged so currency switch has input.
      when(() => service.getSellPrice(any(), any())).thenAnswer(
        (_) async => BrokerbotSellPriceDto(
          shares: 10,
          estimatedAmount: 100,
          pricePerShare: 10,
          currency: 'CHF',
        ),
      );
      await cubit.onSharesChanged('10');
      await Future<void>.delayed(const Duration(milliseconds: 250));

      when(() => service.getSellPrice(any(), any())).thenAnswer(
        (_) async => BrokerbotSellPriceDto(
          shares: 10,
          estimatedAmount: 95.5,
          pricePerShare: 9.55,
          currency: 'EUR',
        ),
      );
      await cubit.onCurrencyChanged(Currency.eur);

      expect(cubit.state.currency, Currency.eur);
      // Sell-side estimate, NOT the buy-side totalCost (50.00).
      expect(cubit.state.fiatText, '95.50');
      verify(() => service.getSellPrice('10', Currency.eur)).called(1);
      verifyNever(() => service.getBuyPrice(any(), any()));
    });

    test('onCurrencyChanged flips currency even when the sell quote throws', () async {
      when(
        () => service.getSellPrice(any(), any()),
      ).thenAnswer((_) async => throw Exception('throttle'));

      final cubit = SellConverterCubit(service);
      await cubit.onCurrencyChanged(Currency.eur);

      expect(cubit.state.currency, Currency.eur);
      expect(cubit.state.loading, isFalse);
    });

    test('onCurrencyChanged clears stale fiatText when conversion fails', () async {
      when(() => service.getSellPrice(any(), Currency.chf)).thenAnswer(
        (_) async => BrokerbotSellPriceDto(
          shares: 10,
          estimatedAmount: 14.30,
          pricePerShare: 1.43,
          currency: 'CHF',
        ),
      );
      when(() => service.getSellPrice(any(), Currency.eur)).thenAnswer(
        (_) async => throw Exception('throttle'),
      );

      final cubit = SellConverterCubit(service);
      await cubit.onSharesChanged('10');
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(cubit.state.fiatText, '14.30');

      await cubit.onCurrencyChanged(Currency.eur);

      expect(cubit.state.currency, Currency.eur);
      expect(cubit.state.fiatText, '');
      expect(cubit.state.loading, isFalse);
    });

    test(
      'fiat race: stale in-flight response is dropped when user typed further',
      () async {
        // Symmetric pin to BuyConverterCubit: prevents the timer-cancel-vs-
        // running-body race where an older API call resolves after a newer
        // one and overwrites the result via last-write-wins.
        final c5 = Completer<BrokerbotSellSharesDto>();
        final c50 = Completer<BrokerbotSellSharesDto>();
        when(() => service.getSellShares('5', any())).thenAnswer((_) => c5.future);
        when(() => service.getSellShares('50', any())).thenAnswer((_) => c50.future);

        final cubit = SellConverterCubit(service);

        await cubit.onFiatChanged('5');
        await Future<void>.delayed(const Duration(milliseconds: 150));
        await cubit.onFiatChanged('50');
        await Future<void>.delayed(const Duration(milliseconds: 150));

        c50.complete(BrokerbotSellSharesDto(
          targetAmount: 50,
          shares: 35,
          pricePerShare: 1.43,
          currency: 'CHF',
        ));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(cubit.state.sharesText, '35');

        c5.complete(BrokerbotSellSharesDto(
          targetAmount: 5,
          shares: 3,
          pricePerShare: 1.43,
          currency: 'CHF',
        ));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(
          cubit.state.sharesText,
          '35',
          reason: 'stale seq=1 response must NOT overwrite seq=2 result',
        );
      },
    );

    test(
      'shares race: stale in-flight response is dropped when user typed further',
      () async {
        final c5 = Completer<BrokerbotSellPriceDto>();
        final c50 = Completer<BrokerbotSellPriceDto>();
        when(() => service.getSellPrice('5', any())).thenAnswer((_) => c5.future);
        when(() => service.getSellPrice('50', any())).thenAnswer((_) => c50.future);

        final cubit = SellConverterCubit(service);

        await cubit.onSharesChanged('5');
        await Future<void>.delayed(const Duration(milliseconds: 150));
        await cubit.onSharesChanged('50');
        await Future<void>.delayed(const Duration(milliseconds: 150));

        c50.complete(BrokerbotSellPriceDto(
          shares: 50,
          estimatedAmount: 71.50,
          pricePerShare: 1.43,
          currency: 'CHF',
        ));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(cubit.state.fiatText, '71.50');

        c5.complete(BrokerbotSellPriceDto(
          shares: 5,
          estimatedAmount: 7.15,
          pricePerShare: 1.43,
          currency: 'CHF',
        ));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(
          cubit.state.fiatText,
          '71.50',
          reason: 'stale in-flight onSharesChanged response must not overwrite newer one',
        );
      },
    );

    test('close() cancels pending debounce timers', () async {
      when(() => service.getSellShares(any(), any())).thenAnswer(
        (_) async => BrokerbotSellSharesDto(
          targetAmount: 1,
          shares: 1,
          pricePerShare: 1,
          currency: 'CHF',
        ),
      );

      final cubit = SellConverterCubit(service);
      await cubit.onFiatChanged('5');
      await cubit.close();
      await Future<void>.delayed(const Duration(milliseconds: 250));

      verifyNever(() => service.getSellShares(any(), any()));
    });

    test('does not emit after close', () async {
      final completer = Completer<BrokerbotSellSharesDto>();
      when(() => service.getSellShares(any(), any())).thenAnswer((_) => completer.future);

      final cubit = SellConverterCubit(service);
      await cubit.onFiatChanged('100');
      // Let the debounce timer fire.
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await cubit.close();
      completer.complete(
        BrokerbotSellSharesDto(
          targetAmount: 100,
          shares: 1,
          pricePerShare: 100,
          currency: 'CHF',
        ),
      );

      // If emit fires after close, StateError is thrown by the framework.
    });
  });
}
