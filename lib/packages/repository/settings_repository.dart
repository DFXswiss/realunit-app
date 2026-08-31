import 'dart:ui';

import 'package:realunit_wallet/packages/config/network_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsRepository {
  final SharedPreferences _sharedPreferences;

  SettingsRepository(this._sharedPreferences);

  Future<bool> saveCurrentWalletId(int walletId) =>
      _sharedPreferences.setInt('currentWalletId', walletId);

  Future<bool> removeCurrentWalletId() => _sharedPreferences.remove('currentWalletId');

  int? get currentWalletId => _sharedPreferences.getInt('currentWalletId');

  String get language {
    final stored = _sharedPreferences.getString('language');
    if (stored != null) return stored;

    final systemLang = PlatformDispatcher.instance.locale.languageCode;
    return systemLang == 'de' ? 'de' : 'en';
  }

  set language(String langCode) => _sharedPreferences.setString('language', langCode);

  bool get hasStoredCurrency => _sharedPreferences.getString('currency') != null;

  // Unset default is EUR. Residence-based CHF/EUR comes from the account
  // currency on GET /v2/user (applied by SettingsBloc, not persisted here).
  String get currency => _sharedPreferences.getString('currency') ?? 'EUR';

  set currency(String currencyCode) => _sharedPreferences.setString('currency', currencyCode);

  bool get termsAccepted => _sharedPreferences.getBool('termsAccepted') ?? false;

  set termsAccepted(bool accepted) => _sharedPreferences.setBool('termsAccepted', accepted);

  NetworkMode get networkMode {
    final value = _sharedPreferences.getString('networkMode');
    return NetworkMode.values.firstWhere(
      (network) => network.name == value,
      orElse: () => NetworkMode.mainnet,
    );
  }

  set networkMode(NetworkMode mode) => _sharedPreferences.setString('networkMode', mode.name);

  bool get softwareTermsAccepted => _sharedPreferences.getBool('softwareTermsAccepted') ?? false;

  set softwareTermsAccepted(bool accepted) =>
      _sharedPreferences.setBool('softwareTermsAccepted', accepted);

  bool get insiderFeaturesUnlocked =>
      _sharedPreferences.getBool('insiderFeaturesUnlocked') ?? false;
  set insiderFeaturesUnlocked(bool unlocked) =>
      _sharedPreferences.setBool('insiderFeaturesUnlocked', unlocked);
}
