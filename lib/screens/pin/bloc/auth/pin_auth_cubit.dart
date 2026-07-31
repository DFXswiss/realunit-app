import 'package:clock/clock.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/packages/storage/secure_storage.dart';
import 'package:realunit_wallet/screens/pin/constants/pin_constants.dart';
import 'package:realunit_wallet/setup/routing/boot_navigation.dart';

part 'pin_auth_state.dart';

class PinAuthCubit extends Cubit<PinAuthState> {
  PinAuthCubit(
    SecureStorage secureStorage,
  ) : _secureStorage = secureStorage,
      super(const PinAuthState());

  final SecureStorage _secureStorage;

  DateTime? _lastBackgroundTime;
  String? _resumeLocation;

  Future<void> initialize() async {
    final isPinSetup = await _secureStorage.hasPinHash();
    emit(
      state.copyWith(
        isPinSetup: isPinSetup,
        isPinVerified: !isPinSetup,
      ),
    );
  }

  void onPinSetupComplete() => emit(
    state.copyWith(isPinSetup: true, isPinVerified: true),
  );

  void onPinVerified() => emit(state.copyWith(isPinVerified: true));

  /// Captures the background timestamp (for the re-lock timeout) and the route
  /// to restore after any resulting PIN re-lock. The timestamp uses `??=` — only
  /// the first backgrounding of an episode arms the timeout. The resume route
  /// instead takes the freshest non-null value: the caller passes null when the
  /// app is backgrounded on a gate route (see `lifecycle_initializer`), so a
  /// nested re-lock — backgrounding again while `/verifyPin` is showing — keeps
  /// the good in-flight capture instead of overwriting it with the gate.
  void onAppHidden(String? currentLocation) {
    _lastBackgroundTime ??= clock.now();
    if (currentLocation != null) _resumeLocation = currentLocation;
  }

  /// The captured pre-background route, or null. Read (not consumed) here; the
  /// consumer (`_navigate`) clears it via [clearResumeLocation] once it has
  /// either restored the route or reached a final landing.
  String? peekResumeLocation() => _resumeLocation;

  void clearResumeLocation() => _resumeLocation = null;

  void onAppResumed() {
    if (!state.isPinSetup) return;

    final lastBackground = _lastBackgroundTime;
    if (lastBackground == null) return;

    final elapsed = clock.now().difference(lastBackground);
    if (elapsed >= lockoutDuration) {
      emit(state.copyWith(isPinVerified: false));
    } else if (state.isPinVerified) {
      // The episode ended without a re-lock — nothing will consume the capture,
      // so drop it eagerly, or a much later unrelated re-lock could restore a
      // route from a long-finished episode. Kept while the PIN gate is showing
      // (isPinVerified == false): a short away-switch on `/verifyPin` is the
      // nested re-lock whose in-flight capture must survive.
      _resumeLocation = null;
    }
    _lastBackgroundTime = null;
  }

  Future<void> reset() async {
    await Future.wait([
      _secureStorage.deletePinHash(),
      _secureStorage.deleteBiometricEnabled(),
      _secureStorage.resetPinLockout(),
    ]);
    _resumeLocation = null;
    // A stashed payment deeplink must not survive into a freshly reset /
    // re-onboarded wallet (Forgot PIN / Delete Wallet).
    clearPendingPaymentDeeplink();
    emit(const PinAuthState());
  }
}
