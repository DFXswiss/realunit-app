import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/packages/config/network_mode.dart';
import 'package:realunit_wallet/packages/repository/settings_repository.dart';
import 'package:realunit_wallet/styles/currency.dart';
import 'package:realunit_wallet/styles/language.dart';

part 'settings_event.dart';
part 'settings_state.dart';

class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  SettingsBloc(
    this._settingsRepository,
    this.getNewAuthToken, {
    this.onNetworkModeChanged,
  }) : super(SettingsState(
          language: Language.fromCode(_settingsRepository.language),
          currency: Currency.fromCode(_settingsRepository.currency),
          networkMode: _settingsRepository.networkMode,
          insiderFeaturesUnlocked:
              _settingsRepository.insiderFeaturesUnlocked,
        )) {
    on<SetCurrencyEvent>(_onSetCurrencyEvent);
    on<ApplyAccountCurrencyEvent>(_onApplyAccountCurrencyEvent);
    on<SetLanguageEvent>(_onSetLanguageEvent);
    on<SetNetworkModeEvent>(_onSetNetworkModeEvent);
    on<ToggleHideAmountEvent>(_onToggleHideAmountEvent);
    on<UnlockInsiderFeaturesEvent>(_onUnlockInsiderFeaturesEvent);
  }

  final SettingsRepository _settingsRepository;
  final Future<void> Function() getNewAuthToken;

  /// Called after the network mode has been persisted and a fresh auth token
  /// has been fetched, but before the new state is emitted. Used to invalidate
  /// reference-data caches (fiats, languages) that are scoped per backend.
  final void Function()? onNetworkModeChanged;

  void _onSetLanguageEvent(SetLanguageEvent event, Emitter<SettingsState> emit) {
    _settingsRepository.language = event.language.code;
    emit(state.copyWith(language: event.language));
  }

  void _onSetCurrencyEvent(SetCurrencyEvent event, Emitter<SettingsState> emit) {
    _settingsRepository.currency = event.currency.code;
    emit(state.copyWith(currency: event.currency));
  }

  void _onApplyAccountCurrencyEvent(
    ApplyAccountCurrencyEvent event,
    Emitter<SettingsState> emit,
  ) {
    if (_settingsRepository.hasStoredCurrency) return;
    emit(state.copyWith(currency: event.currency));
  }

  Future<void> _onSetNetworkModeEvent(
      SetNetworkModeEvent event, Emitter<SettingsState> emit) async {
    _settingsRepository.networkMode = event.networkMode;
    await getNewAuthToken();
    onNetworkModeChanged?.call();
    emit(state.copyWith(networkMode: event.networkMode));
  }

  void _onToggleHideAmountEvent(ToggleHideAmountEvent event, Emitter<SettingsState> emit) {
    emit(state.copyWith(hideAmounts: !state.hideAmounts));
  }

  void _onUnlockInsiderFeaturesEvent(
    UnlockInsiderFeaturesEvent event,
    Emitter<SettingsState> emit,
  ) {
    _settingsRepository.insiderFeaturesUnlocked = true;
    emit(state.copyWith(insiderFeaturesUnlocked: true));
  }
}
