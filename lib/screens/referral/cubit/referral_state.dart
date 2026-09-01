part of 'referral_cubit.dart';

abstract class ReferralState extends Equatable {
  const ReferralState();

  @override
  List<Object?> get props => [];
}

class ReferralInitial extends ReferralState {
  const ReferralInitial();
}

class ReferralLoading extends ReferralState {
  const ReferralLoading();
}

class ReferralNotEligible extends ReferralState {
  const ReferralNotEligible();
}

class ReferralNeedsTerms extends ReferralState {
  final ReferralSummaryDto summary;
  final String? errorMessage;

  const ReferralNeedsTerms({required this.summary, this.errorMessage});

  @override
  List<Object?> get props => [
    summary.eligible,
    summary.termsAccepted,
    errorMessage,
  ];
}

class ReferralTermsAccepting extends ReferralState {
  final ReferralSummaryDto summary;

  const ReferralTermsAccepting({required this.summary});

  @override
  List<Object?> get props => [summary.eligible, summary.termsAccepted];
}

class ReferralOverviewLoaded extends ReferralState {
  final ReferralSummaryDto summary;
  final List<ReferralInviteDto> invites;

  const ReferralOverviewLoaded({required this.summary, required this.invites});

  @override
  List<Object?> get props => [
    summary.openCount,
    summary.creditedCount,
    summary.realuSum,
    summary.chfSum,
    invites.map((i) => i.id).toList(),
  ];
}

class ReferralCreateReady extends ReferralState {
  final ReferralSummaryDto summary;
  final String? errorMessage;

  const ReferralCreateReady({required this.summary, this.errorMessage});

  @override
  List<Object?> get props => [summary.openCount, errorMessage];
}

class ReferralCreating extends ReferralState {
  final ReferralSummaryDto summary;
  final String guestName;

  const ReferralCreating({required this.summary, required this.guestName});

  @override
  List<Object?> get props => [summary.openCount, guestName];
}

class ReferralInviteCreated extends ReferralState {
  final ReferralSummaryDto summary;
  final ReferralCreatedInviteDto invite;

  const ReferralInviteCreated({required this.summary, required this.invite});

  @override
  List<Object?> get props => [invite.code, invite.url, invite.guestName];
}

class ReferralFailure extends ReferralState {
  final String message;

  const ReferralFailure({required this.message});

  @override
  List<Object?> get props => [message];
}
