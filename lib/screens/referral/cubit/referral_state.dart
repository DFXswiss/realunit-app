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

  /// True while [ReferralCubit.load] is retrying from the create-invite
  /// needs-terms Retry so the copy stays instead of a blank spinner.
  final bool retrying;

  const ReferralNeedsTerms({
    required this.summary,
    this.errorMessage,
    this.retrying = false,
  });

  @override
  List<Object?> get props => [
    summary.eligible,
    summary.termsAccepted,
    errorMessage,
    retrying,
  ];
}

class ReferralTermsAccepting extends ReferralState {
  final ReferralSummaryDto summary;

  /// Previous accept error kept on screen while this POST retries.
  final String? errorMessage;

  const ReferralTermsAccepting({required this.summary, this.errorMessage});

  @override
  List<Object?> get props => [
    summary.eligible,
    summary.termsAccepted,
    errorMessage,
  ];
}

class ReferralOverviewLoaded extends ReferralState {
  final ReferralSummaryDto summary;
  final List<ReferralInviteDto> invites;

  /// Set when the invite list call failed. Summary tiles stay visible.
  final String? invitesError;

  /// True while [ReferralCubit.reloadInvites] is in flight.
  final bool invitesLoading;

  const ReferralOverviewLoaded({
    required this.summary,
    required this.invites,
    this.invitesError,
    this.invitesLoading = false,
  });

  @override
  List<Object?> get props => [
    summary.openCount,
    summary.creditedCount,
    summary.realuSum,
    summary.chfSum,
    summary.sharePrice,
    invites.map((i) => i.id).toList(),
    invitesError,
    invitesLoading,
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

  /// Previous create error kept on screen while this POST retries.
  final String? errorMessage;

  const ReferralCreating({
    required this.summary,
    required this.guestName,
    this.errorMessage,
  });

  @override
  List<Object?> get props => [summary.openCount, guestName, errorMessage];
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

  /// True while [ReferralCubit.load] is retrying this error so Retry can
  /// load in place instead of replacing the copy with a blank spinner.
  final bool retrying;

  const ReferralFailure({required this.message, this.retrying = false});

  @override
  List<Object?> get props => [message, retrying];
}
