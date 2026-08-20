part of 'kyc_confirm_email_cubit.dart';

abstract class KycConfirmEmailState extends Equatable {
  const KycConfirmEmailState();

  @override
  List<Object?> get props => [];
}

class KycConfirmEmailInitial extends KycConfirmEmailState {
  const KycConfirmEmailInitial();
}

class KycConfirmEmailLoading extends KycConfirmEmailState {
  const KycConfirmEmailLoading();
}

/// The API reports the address is confirmed (or reports no gate at all). The
/// page hands back to `KycCubit.checkKyc()`, which re-routes from the API.
class KycConfirmEmailConfirmed extends KycConfirmEmailState {
  const KycConfirmEmailConfirmed();
}

/// The address is still not confirmed. The page shows a retry hint and keeps
/// the user on the confirm step.
class KycConfirmEmailNotConfirmed extends KycConfirmEmailState {
  const KycConfirmEmailNotConfirmed();
}

/// The re-check itself failed (API / transport). The page shows the API text
/// 1:1 and keeps the user on the confirm step so they can retry.
class KycConfirmEmailFailure extends KycConfirmEmailState {
  final String message;

  const KycConfirmEmailFailure(this.message);

  @override
  List<Object?> get props => [message];
}
