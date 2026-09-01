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

  const ReferralEligibilityLoaded({required this.eligible});

  @override
  List<Object?> get props => [eligible];
}
