part of 'settings_bloc.dart';

final class SettingsState {
  const SettingsState({
    this.language = Language.en,
    this.currency = Currency.chf,
    this.networkMode = NetworkMode.mainnet,
    this.hideAmounts = false,
    this.insiderFeaturesUnlocked = false,
  });

  final Language language;
  final Currency currency;
  final NetworkMode networkMode;
  final bool hideAmounts;
  final bool insiderFeaturesUnlocked;

  SettingsState copyWith({
    Language? language,
    Currency? currency,
    NetworkMode? networkMode,
    bool? hideAmounts,
    bool? insiderFeaturesUnlocked,
  }) =>
      SettingsState(
        language: language ?? this.language,
        currency: currency ?? this.currency,
        networkMode: networkMode ?? this.networkMode,
        hideAmounts: hideAmounts ?? this.hideAmounts,
        insiderFeaturesUnlocked: insiderFeaturesUnlocked ?? this.insiderFeaturesUnlocked,
      );
}
