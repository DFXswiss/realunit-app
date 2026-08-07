part of 'support_email_capture_cubit.dart';

abstract class SupportEmailCaptureState extends Equatable {
  const SupportEmailCaptureState();

  @override
  List<Object?> get props => [];
}

class SupportEmailCaptureInitial extends SupportEmailCaptureState {
  const SupportEmailCaptureInitial();
}

class SupportEmailCaptureLoading extends SupportEmailCaptureState {
  const SupportEmailCaptureLoading();
}

class SupportEmailCaptureSuccess extends SupportEmailCaptureState {
  const SupportEmailCaptureSuccess();
}

/// The email belongs to an existing account and the API has sent an
/// account-merge confirmation email (register/email returns `merge_requested`).
/// The user must confirm that email to link this wallet to the existing
/// account — the view routes to the shared KYC email-verification flow, not to
/// an error. Distinct from [SupportEmailCaptureFailure]: this is a normal,
/// recoverable branch, not a failure.
class SupportEmailCaptureMergeRequested extends SupportEmailCaptureState {
  const SupportEmailCaptureMergeRequested();
}

class SupportEmailCaptureFailure extends SupportEmailCaptureState {
  final String message;

  const SupportEmailCaptureFailure(this.message);

  @override
  List<Object?> get props => [message];
}
