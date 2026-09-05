import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_referral_service.dart';

part 'referral_eligibility_state.dart';

/// Loads `summary.eligible` for dashboard / settings entry gates.
/// Failures hide the entry (same idea as sell: API decides eligibility)
/// after one retry so a transient outage does not hide the card. A
/// timed-out GET is not retried — a second 15s budget would keep the
/// card hidden for half a minute.
class ReferralEligibilityCubit extends Cubit<ReferralEligibilityState> {
  final RealUnitReferralService _service;
  int _reloadGeneration = 0;

  ReferralEligibilityCubit(this._service)
    : super(const ReferralEligibilityInitial());

  Future<void> load() async {
    if (state is ReferralEligibilityLoading) return;
    emit(const ReferralEligibilityLoading());
    try {
      final summary = await _service.getSummary();
      if (isClosed) return;
      emit(ReferralEligibilityLoaded(eligible: summary.eligible));
    } on TimeoutException {
      if (isClosed) return;
      emit(
        const ReferralEligibilityLoaded(eligible: false, unavailable: true),
      );
    } catch (_) {
      // One retry so a transient summary outage does not hide the card.
      try {
        final summary = await _service.getSummary();
        if (isClosed) return;
        emit(ReferralEligibilityLoaded(eligible: summary.eligible));
      } catch (_) {
        if (isClosed) return;
        emit(
          const ReferralEligibilityLoaded(eligible: false, unavailable: true),
        );
      }
    }
  }

  /// Resume / Settings return: retry the gate without a loading flash.
  /// A tile that is already shown stays shown if this GET fails.
  Future<void> reload() async {
    if (state is ReferralEligibilityLoading || isClosed) return;
    final generation = ++_reloadGeneration;
    try {
      final summary = await _service.getSummary();
      if (isClosed || generation != _reloadGeneration) return;
      emit(ReferralEligibilityLoaded(eligible: summary.eligible));
    } on TimeoutException {
      if (isClosed || generation != _reloadGeneration) return;
      if (state is ReferralEligibilityLoaded) return;
      emit(
        const ReferralEligibilityLoaded(eligible: false, unavailable: true),
      );
    } catch (_) {
      if (isClosed || generation != _reloadGeneration) return;
      if (state is ReferralEligibilityLoaded) return;
      emit(
        const ReferralEligibilityLoaded(eligible: false, unavailable: true),
      );
    }
  }
}
