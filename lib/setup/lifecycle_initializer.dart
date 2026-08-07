import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/balance_service.dart';
import 'package:realunit_wallet/packages/service/wallet_service.dart';
import 'package:realunit_wallet/screens/pin/bloc/auth/pin_auth_cubit.dart';
import 'package:realunit_wallet/setup/di.dart';
import 'package:realunit_wallet/setup/routing/boot_navigation.dart';
import 'package:realunit_wallet/setup/routing/router_config.dart';

class LifecycleInitializer extends StatefulWidget {
  final Widget child;

  const LifecycleInitializer({super.key, required this.child});

  @override
  State<LifecycleInitializer> createState() => _LifecycleInitializerState();
}

class _LifecycleInitializerState extends State<LifecycleInitializer> {
  late final AppLifecycleListener _listener;

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(onStateChange: _onStateChanged);
  }

  void _onStateChanged(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.detached:
        _onDetached();
      case AppLifecycleState.resumed:
        _onResumed();
      case AppLifecycleState.inactive:
        _onInactive();
      case AppLifecycleState.hidden:
        _onHidden();
      case AppLifecycleState.paused:
        _onPaused();
    }
    developer.log(state.name, name: 'AppLifecycleListener');
  }

  /// Guards the background-lock so it arms at most once per background episode.
  /// A normal backgrounding raises both `hidden` and `paused` (order and
  /// coalescing vary by platform), so without this guard the mnemonic drop +
  /// PIN re-lock would run twice — the second `lockCurrentWallet()` would
  /// double-decrement [WalletService]'s active-unlock-holder count. Reset on
  /// resume so the next backgrounding arms again.
  bool _armedForBackground = false;

  void _onDetached() {}

  void _onResumed() {
    _armedForBackground = false;
    getIt<PinAuthCubit>().onAppResumed();
    getIt<BalanceService>().updateBalance(getIt<AppStore>().primaryAddress);
  }

  // `inactive` is deliberately NOT a lock trigger. On iOS it fires for
  // transient interruptions that are still in front of the user — the
  // biometric (Face ID / Touch ID) prompt, permission dialogs, the incoming
  // call banner, the Control Center / notification-shade swipe. The biometric
  // unlock prompt in particular raises `inactive`, so locking here would drop
  // the mnemonic and re-arm the PIN gate in the middle of the very unlock the
  // user is completing. We arm only on `paused` / `hidden`, which both mean the
  // app is actually backgrounded.
  void _onInactive() {}

  void _onHidden() => _armBackgroundLock();

  void _onPaused() {
    getIt<BalanceService>().cancelSync();
    _armBackgroundLock();
  }

  /// Drops the in-memory mnemonic and arms the PIN re-lock when the app is
  /// backgrounded. Armed from both `hidden` and `paused` so a platform that
  /// skips or coalesces `hidden` still locks (the finding's core gap), and made
  /// idempotent via [_armedForBackground] so the `hidden` + `paused` pair locks
  /// exactly once.
  void _armBackgroundLock() {
    if (_armedForBackground) return;
    _armedForBackground = true;

    // effectiveLocation, not currentConfiguration.uri: the KYC flow is pushed
    // imperatively, and the raw uri would capture the base route underneath.
    final location = effectiveLocation(routerConfig.routerDelegate.currentConfiguration);
    getIt<PinAuthCubit>().onAppHidden(resumeCaptureFor(location));
    // Drop the mnemonic before the OS suspends the isolate. `lockCurrentWallet`
    // is defensive on its own — no try/catch / catchError by design, so a
    // Future.error surfaces in the Zone instead of being silently swallowed.
    // Microtask race to watch: if `_onResumed` ever calls
    // `ensureCurrentWalletUnlocked`, ordering against this pending lock matters.
    unawaited(getIt<WalletService>().lockCurrentWallet());
  }

  @override
  void dispose() {
    _listener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
