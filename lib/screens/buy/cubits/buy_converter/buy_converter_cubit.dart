import 'dart:async';
import 'dart:developer' as developer;

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_brokerbot_service.dart';
import 'package:realunit_wallet/styles/currency.dart';

part 'buy_converter_state.dart';

class BuyConverterCubit extends Cubit<BuyConverterState> {
  final DfxBrokerbotService _brokerbotService;

  BuyConverterCubit(this._brokerbotService, {Currency currency = Currency.chf})
    : super(BuyConverterState(currency: currency));

  Timer? _fiatDebounce;
  Timer? _sharesDebounce;

  // Monotonic counter for the latest user intent. Every user-triggered
  // method (onFiatChanged / onSharesChanged / onCurrencyChanged) increments
  // it and captures its own value via closure; the async body drops its
  // emit if `_seq` has moved on. Prevents the timer-cancel-vs-running-body
  // race where a debounced timer's body has already started its API call
  // by the time the user types another character — without this guard the
  // older in-flight response can win last-write-wins and overwrite the
  // newer result (e.g. `460 → shares=321` overwriting `4600 → shares=3216`).
  int _seq = 0;

  /// User changed fiat → convert to shares. The conversion result lands in
  /// [BuyConverterState.sharesText] and [BuyConverterState.payableText] only:
  /// writing it back into [BuyConverterState.fiatText] would overwrite the
  /// text field mid-edit and make typing/deleting impossible.
  Future<void> onFiatChanged(String value) async {
    emit(state.copyWith(fiatText: value, payableText: ''));

    _fiatDebounce?.cancel();
    final mySeq = ++_seq;
    _fiatDebounce = Timer(const Duration(milliseconds: 100), () async {
      if (isClosed || mySeq != _seq) return;
      emit(state.copyWith(loading: true));

      try {
        final result = await _brokerbotService.getBuyShares(value, state.currency);
        if (isClosed || mySeq != _seq) return;
        final priceMinor = (result.pricePerShare * 100).round();
        final payable = result.shares * priceMinor / 100;
        emit(
          state.copyWith(
            sharesText: result.shares.toString(),
            payableText: payable.toStringAsFixed(2),
            loading: false,
          ),
        );
      } catch (e) {
        developer.log(e.toString());
        if (isClosed || mySeq != _seq) return;
        emit(state.copyWith(loading: false));
      }
    });
  }

  /// User changed shares → convert to fiat. Writing the result into
  /// [BuyConverterState.fiatText] is safe here: the user is typing in the
  /// shares field, so the fiat field is pure conversion output.
  Future<void> onSharesChanged(String value) async {
    emit(state.copyWith(sharesText: value, payableText: ''));

    _sharesDebounce?.cancel();
    final mySeq = ++_seq;
    _sharesDebounce = Timer(const Duration(milliseconds: 100), () async {
      if (isClosed || mySeq != _seq) return;
      emit(state.copyWith(loading: true));

      try {
        final result = await _brokerbotService.getBuyPrice(value, state.currency);
        if (isClosed || mySeq != _seq) return;
        emit(
          state.copyWith(
            fiatText: result.totalCost.toStringAsFixed(_fractionDigits(value)),
            payableText: result.totalCost.toStringAsFixed(2),
            loading: false,
          ),
        );
      } catch (e) {
        developer.log(e.toString());
        if (isClosed || mySeq != _seq) return;
        emit(state.copyWith(loading: false));
      }
    });
  }

  Future<void> onCurrencyChanged(Currency currency) async {
    final mySeq = ++_seq;
    // Flip currency immediately so the picker reflects the user choice
    // even if an in-flight conversion arrives later and gets dropped by
    // the seq guard.
    emit(state.copyWith(loading: true, currency: currency, payableText: ''));

    try {
      final result = await _brokerbotService.getBuyShares(state.fiatText, currency);
      if (isClosed || mySeq != _seq) return;
      final priceMinor = (result.pricePerShare * 100).round();
      final payable = result.shares * priceMinor / 100;
      emit(
        state.copyWith(
          sharesText: result.shares.toString(),
          payableText: payable.toStringAsFixed(2),
          loading: false,
        ),
      );
    } catch (e) {
      developer.log(e.toString());
      if (isClosed || mySeq != _seq) return;
      emit(state.copyWith(loading: false));
    }
  }

  int _fractionDigits(String input) {
    if (!input.contains('.')) return 2;
    return input.split('.').last.length;
  }

  @override
  Future<void> close() {
    _fiatDebounce?.cancel();
    _sharesDebounce?.cancel();
    return super.close();
  }
}
