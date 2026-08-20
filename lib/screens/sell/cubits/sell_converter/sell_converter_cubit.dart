import 'dart:async';
import 'dart:developer' as developer;

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_brokerbot_service.dart';
import 'package:realunit_wallet/styles/currency.dart';

part 'sell_converter_state.dart';

class SellConverterCubit extends Cubit<SellConverterState> {
  final DfxBrokerbotService _brokerbotService;

  SellConverterCubit(this._brokerbotService) : super(const SellConverterState());

  Timer? _fiatDebounce;
  Timer? _sharesDebounce;

  // Monotonic counter for the latest user intent. Every user-triggered
  // method (onFiatChanged / onSharesChanged / onCurrencyChanged) increments
  // it and captures its own value via closure; the async body drops its
  // emit if `_seq` has moved on. Prevents the timer-cancel-vs-running-body
  // race where a debounced timer's body has already started its API call
  // by the time the user types another character — without this guard the
  // older in-flight response can win last-write-wins and overwrite the
  // newer result.
  int _seq = 0;

  /// User changed fiat → convert to shares
  Future<void> onFiatChanged(String value, {Currency currency = Currency.chf}) async {
    emit(state.copyWith(fiatText: value));

    _fiatDebounce?.cancel();
    final mySeq = ++_seq;
    _fiatDebounce = Timer(const Duration(milliseconds: 100), () async {
      if (isClosed || mySeq != _seq) return;
      emit(state.copyWith(loading: true));

      try {
        final result = await _brokerbotService.getSellShares(value, currency);
        if (isClosed || mySeq != _seq) return;
        emit(
          state.copyWith(
            sharesText: result.shares.toString(),
            loading: false,
          ),
        );
      } catch (e) {
        developer.log(e.toString());
        if (isClosed || mySeq != _seq) return;
        emit(state.copyWith(loading: false, sharesText: ''));
      }
    });
  }

  /// User changed shares → convert to fiat
  Future<void> onSharesChanged(String value, {Currency currency = Currency.chf}) async {
    emit(state.copyWith(sharesText: value));

    _sharesDebounce?.cancel();
    final mySeq = ++_seq;
    _sharesDebounce = Timer(const Duration(milliseconds: 100), () async {
      if (isClosed || mySeq != _seq) return;
      emit(state.copyWith(loading: true));

      try {
        final result = await _brokerbotService.getSellPrice(value, currency);
        if (isClosed || mySeq != _seq) return;
        emit(
          state.copyWith(
            fiatText: result.estimatedAmount.toStringAsFixed(_fractionDigits(value)),
            loading: false,
          ),
        );
      } catch (e) {
        developer.log(e.toString());
        if (isClosed || mySeq != _seq) return;
        emit(state.copyWith(loading: false, fiatText: ''));
      }
    });
  }

  Future<void> onCurrencyChanged(Currency currency) async {
    final mySeq = ++_seq;
    // Flip currency immediately so the picker reflects the user choice
    // even if an in-flight conversion arrives later and gets dropped by
    // the seq guard.
    emit(state.copyWith(loading: true, currency: currency));
    try {
      // Re-quote via getSellPrice.estimatedAmount, mirroring onSharesChanged (#657 P4 S1).
      final result = await _brokerbotService.getSellPrice(state.sharesText, currency);
      if (isClosed || mySeq != _seq) return;
      emit(
        state.copyWith(
          fiatText: result.estimatedAmount.toStringAsFixed(_fractionDigits(state.sharesText)),
          loading: false,
        ),
      );
    } catch (e) {
      developer.log(e.toString());
      if (isClosed || mySeq != _seq) return;
      emit(state.copyWith(loading: false, fiatText: ''));
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
