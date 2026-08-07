import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_registration_service.dart';

part 'kyc_confirm_email_state.dart';

/// Re-checks the API-side e-mail confirmation flag for an already-registered
/// wallet. The gate is API-driven: `KycCubit` routes here only when
/// `getRegistrationInfo().emailConfirmed == false`, and this cubit re-fetches
/// the same fact when the user reports they clicked the confirmation link. When
/// the backend reports the address is confirmed (an explicit `true`, including
/// grandfathered accounts) or no longer reports the flag at all (a pre-rollout
/// backend, `null`), the flow proceeds. See CONTRIBUTING.md "API as Decision
/// Authority".
class KycConfirmEmailCubit extends Cubit<KycConfirmEmailState> {
  // Mirrors `KycCubit._checkKycTimeout`: the same `getRegistrationInfo()`
  // call is watch-dogged so a stalled request (socket up, backend never
  // responds) cannot wedge the button in its loading state forever. On
  // expiry the `TimeoutException` falls into the fail-closed `catch` below.
  static const _recheckTimeout = Duration(seconds: 30);

  final RealUnitRegistrationService _registrationService;

  // Mirrors `KycCubit._runGeneration`: `Future.timeout` does not cancel the
  // underlying HTTP call, so a late response from a superseded tap must not
  // emit over a newer one. Each `recheck()` captures its own generation and any
  // continuation bails when the generation no longer matches the current one.
  int _runGeneration = 0;

  KycConfirmEmailCubit(this._registrationService)
    : super(const KycConfirmEmailInitial());

  /// Re-fetches the registration info and reports whether the address is now
  /// confirmed. Only an explicit `emailConfirmed == false` keeps the user on
  /// the gate; `true` and `null` both proceed — the app never invents a gate
  /// the API did not ask for.
  Future<void> recheck() async {
    final generation = ++_runGeneration;
    if (isClosed) return;
    emit(const KycConfirmEmailLoading());
    try {
      final info = await _registrationService
          .getRegistrationInfo()
          .timeout(_recheckTimeout);
      if (isClosed || generation != _runGeneration) return;
      if (info.emailConfirmed == false) {
        emit(const KycConfirmEmailNotConfirmed());
        return;
      }
      emit(const KycConfirmEmailConfirmed());
    } catch (_) {
      if (isClosed || generation != _runGeneration) return;
      // A failed re-check (network / backend) must not wedge the button in its
      // loading state, and must not let the user through — fail closed. Surface
      // the same retry affordance as a still-unconfirmed address so the user
      // can tap again once connectivity returns.
      emit(const KycConfirmEmailNotConfirmed());
    }
  }
}
