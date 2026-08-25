import 'dart:async';

import 'package:realunit_wallet/packages/service/dfx/dfx_kyc_service.dart';
import 'package:realunit_wallet/packages/service/dfx/models/user/dto/user_dto.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';
import 'package:realunit_wallet/screens/settings/bloc/settings_bloc.dart';

/// Applies GET /v2/user.currency when a wallet opens or is replaced, and
/// clears a non-persisted account default when it closes.
///
/// Extracted from [WalletApp] so open / close / A→B can be tested without
/// pumping the full app (same seam idea as boot_navigation).
class AccountCurrencySync {
  AccountCurrencySync({
    required SettingsBloc settings,
    required DfxKycService kyc,
    required AWallet? Function() currentWallet,
  }) : _settings = settings,
       _kyc = kyc,
       _currentWallet = currentWallet;

  final SettingsBloc _settings;
  final DfxKycService _kyc;
  final AWallet? Function() _currentWallet;
  int _generation = 0;

  AWallet? get currentWallet => _currentWallet();

  /// Applies an already-fetched GET /v2/user currency (KYC path) only if
  /// [captured] is still the open wallet.
  void applyFromUser(UserDto user, {required AWallet? captured}) {
    final currency = user.currency;
    if (currency == null) return;
    final open = _currentWallet();
    if (open == null || !identical(open, captured)) return;
    _settings.add(ApplyAccountCurrencyEvent(currency));
  }

  void onOpened(AWallet? wallet) {
    final generation = ++_generation;
    unawaited(_apply(generation, wallet));
  }

  void onClosed() {
    _generation++;
    _settings.add(const ClearAccountCurrencyEvent());
  }

  void onSwitched(AWallet? wallet) {
    _settings.add(const ClearAccountCurrencyEvent());
    onOpened(wallet);
  }

  Future<void> _apply(int generation, AWallet? captured) async {
    try {
      final user = await _kyc.getUser();
      if (generation != _generation) return;
      if (!identical(_currentWallet(), captured)) return;
      final currency = user.currency;
      if (currency == null) return;
      _settings.add(ApplyAccountCurrencyEvent(currency));
    } catch (_) {
      // Account currency is a display default; boot must not fail if /v2/user
      // is unavailable.
    }
  }
}
