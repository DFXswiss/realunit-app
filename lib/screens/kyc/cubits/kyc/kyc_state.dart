part of 'kyc_cubit.dart';

enum KycStep {
  email,
  confirmEmail,
  registration,
  linkWallet,
  legalDisclaimer,
  nationality,
  twoFa,
  ident,
  financialData,
  dfxApproval,
}

abstract class KycState extends Equatable {
  const KycState();

  @override
  List<Object?> get props => [];
}

class KycInitial extends KycState {
  const KycInitial();
}

class KycLoading extends KycState {
  const KycLoading();
}

class KycPending extends KycState {
  final KycStep pendingStep;

  const KycPending(this.pendingStep);

  @override
  List<Object?> get props => [pendingStep];
}

class KycSuccess extends KycState {
  final KycStep currentStep;
  final String? urlOrToken;

  /// Server-side user record attached to the routing decision. Populated when
  /// `RealUnitRegistrationService.getRegistrationInfo()` returns userData
  /// alongside the state (`AddWallet` always, `NewRegistration` when the
  /// backend has fallback data). The cubit forwards the DTO so downstream
  /// pages do not need to re-fetch — see CONTRIBUTING.md "Single round-trip
  /// per decision".
  final RealUnitUserDataDto? realUnitUserData;

  const KycSuccess({
    required this.currentStep,
    this.urlOrToken,
    this.realUnitUserData,
  });

  @override
  List<Object?> get props => [currentStep, urlOrToken, realUnitUserData];
}

class KycCompleted extends KycState {
  const KycCompleted();
}

class KycAccountMergeRequested extends KycState {
  const KycAccountMergeRequested();
}

/// Emitted when the API reports `KycProcessStatus.mergeProcessing` — the user
/// confirmed a merge and the backend is still processing it. The app renders a
/// waiting state instead of interpreting the polling timeout as a failure.
class KycMergeProcessing extends KycState {
  const KycMergeProcessing();
}

/// Emitted when the API reports this wallet's RealUnit registration is parked in
/// manual review (`RealUnitRegistrationInfoDto.manualReview == true`) — the
/// Aktionariat forward failed and staff must re-forward it before onboarding can
/// complete. A terminal waiting state: the user cannot act, so the app renders a
/// "registration under review" screen with a refresh instead of routing further.
class KycManualReview extends KycState {
  const KycManualReview();
}

class KycUnsupportedStepFailure extends KycState {
  // Null when the backend says `PendingReview` but the step list contains no
  // `isRequired` step we can name — we still surface the failure (never a
  // silent `KycCompleted`) but cannot point the user at a specific step.
  final KycStepName? stepName;
  const KycUnsupportedStepFailure(this.stepName);

  @override
  List<Object?> get props => [stepName];
}

class KycFailure extends KycState {
  final String message;
  const KycFailure(this.message);

  @override
  List<Object?> get props => [message];
}

/// Emitted when the wallet currently in use cannot produce EIP-712 signatures
/// (today: the address+signature debug wallet) and the API has routed the
/// user to a state (`NewRegistration` / `AddWallet`) that would require one.
/// Signing capability is a physical property of the wallet — see
/// `docs/wallet-modes.md` for the full table.
class KycSignatureUnsupportedFailure extends KycState {
  const KycSignatureUnsupportedFailure();
}

/// The paired BitBox can sign in general, but its firmware refuses the
/// registration envelope specifically — its EIP-712 domain carries no chainId,
/// and confirming the resulting device warning answers with a NACK over
/// Bluetooth. Emitted only when the registration state actually needs a
/// signature. See `BitboxFirmware` for the measurements and affected range.
///
/// [version] is what the device reported, e.g. `"v9.26.4"`, or null when it
/// could not be read; carried so the screen can name it.
class KycBitboxFirmwareUnsupportedFailure extends KycState {
  const KycBitboxFirmwareUnsupportedFailure({this.version});

  final String? version;

  @override
  List<Object?> get props => [version];
}
