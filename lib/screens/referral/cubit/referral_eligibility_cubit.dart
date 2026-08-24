import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_referral_service.dart';

part 'referral_eligibility_state.dart';

/// Loads `summary.eligible` for dashboard / settings entry gates.
/// Failures hide the entry (same idea as sell: API decides eligibility).
class ReferralEligibilityCubit extends Cubit<ReferralEligibilityState> {
  final RealUnitReferralService _service;

  ReferralEligibilityCubit(this._service)
    : super(const ReferralEligibilityInitial());

  Future<void> load() async {
    emit(const ReferralEligibilityLoading());
    try {
      final summary = await _service.getSummary();
      emit(ReferralEligibilityLoaded(eligible: summary.eligible));
    } catch (_) {
      emit(const ReferralEligibilityLoaded(eligible: false));
    }
  }
}
