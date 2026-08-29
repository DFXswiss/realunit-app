part of 'referral_eligibility_cubit.dart';

abstract class ReferralEligibilityState extends Equatable {
  const ReferralEligibilityState();

  @override
  List<Object?> get props => [];
}

class ReferralEligibilityInitial extends ReferralEligibilityState {
  const ReferralEligibilityInitial();
}

class ReferralEligibilityLoading extends ReferralEligibilityState {
  const ReferralEligibilityLoading();
}

class ReferralEligibilityLoaded extends ReferralEligibilityState {
  final bool eligible;

  /// True when the last GET /summary failed (unmounted, 503, timeout).
  /// The tile stays hidden, but the gate is retried on a timer so a
  /// later mount can open it without backgrounding the app. A 200 with
  /// `eligible: false` is not unavailable — do not poll genuine
  /// non-shareholders.
  final bool unavailable;

  const ReferralEligibilityLoaded({
    required this.eligible,
    this.unavailable = false,
  });

  @override
  List<Object?> get props => [eligible, unavailable];
}
