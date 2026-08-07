part of 'settings_bloc.dart';

sealed class SettingsEvent extends Equatable {
  const SettingsEvent();

  @override
  List<Object> get props => [];
}

final class SetLanguageEvent extends SettingsEvent {
  final Language language;

  const SetLanguageEvent(this.language);

  @override
  List<Object> get props => [language];
}

final class SetCurrencyEvent extends SettingsEvent {
  final Currency currency;

  const SetCurrencyEvent(this.currency);

  @override
  List<Object> get props => [currency];
}

final class SetNetworkModeEvent extends SettingsEvent {
  final NetworkMode networkMode;

  const SetNetworkModeEvent(this.networkMode);

  @override
  List<Object> get props => [networkMode];
}

final class ToggleHideAmountEvent extends SettingsEvent {
  const ToggleHideAmountEvent();
}

final class UnlockInsiderFeaturesEvent extends SettingsEvent {
  const UnlockInsiderFeaturesEvent();
}
