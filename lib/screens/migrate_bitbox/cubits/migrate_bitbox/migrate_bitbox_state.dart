part of 'migrate_bitbox_cubit.dart';

enum MigrateBitboxFailureReason {
  addressAlreadyLinked,
  registrationMissing,
  signatureCancelled,
  bitboxNotConnected,
  generic,
}

sealed class MigrateBitboxState extends Equatable {
  const MigrateBitboxState();

  @override
  List<Object?> get props => [];
}

class MigrateBitboxIntro extends MigrateBitboxState {
  const MigrateBitboxIntro();
}

/// The view reacts to this by opening the ConnectBitboxPage bottom sheet.
class MigrateBitboxAwaitingDevice extends MigrateBitboxState {
  const MigrateBitboxAwaitingDevice();
}

class MigrateBitboxLinking extends MigrateBitboxState {
  const MigrateBitboxLinking();
}

class MigrateBitboxRegisterReady extends MigrateBitboxState {
  const MigrateBitboxRegisterReady(this.userData, this.bitboxAddress);

  final RealUnitUserDataDto userData;
  final String bitboxAddress;

  @override
  List<Object?> get props => [userData, bitboxAddress];
}

/// Registration is parked in manual review (Aktionariat forward pending, or the
/// wallet was already registered elsewhere and needs staff review). The wizard
/// ends here; the balance stays on the software wallet and the user may re-open
/// the wizard later once the review completes.
class MigrateBitboxRegistrationPending extends MigrateBitboxState {
  const MigrateBitboxRegistrationPending();
}

class MigrateBitboxTransferReady extends MigrateBitboxState {
  const MigrateBitboxTransferReady({
    required this.fromAddress,
    required this.toAddress,
    required this.amount,
  });

  final String fromAddress;
  final String toAddress;
  final int amount;

  @override
  List<Object?> get props => [fromAddress, toAddress, amount];
}

/// Carries the same recipient/amount as [MigrateBitboxTransferReady] so the view
/// can build the embedded [SendProcessCubit] without needing to remember the
/// prior state itself.
class MigrateBitboxTransferring extends MigrateBitboxState {
  const MigrateBitboxTransferring({required this.toAddress, required this.amount});

  final String toAddress;
  final int amount;

  @override
  List<Object?> get props => [toAddress, amount];
}

class MigrateBitboxSettling extends MigrateBitboxState {
  const MigrateBitboxSettling();
}

class MigrateBitboxSettlingTimeout extends MigrateBitboxState {
  const MigrateBitboxSettlingTimeout();
}

class MigrateBitboxPreparingTransfer extends MigrateBitboxState {
  const MigrateBitboxPreparingTransfer();
}

class MigrateBitboxCompleting extends MigrateBitboxState {
  const MigrateBitboxCompleting();
}

class MigrateBitboxSuccess extends MigrateBitboxState {
  const MigrateBitboxSuccess(this.wallet);

  final BitboxWallet wallet;

  @override
  List<Object?> get props => [wallet];
}

class MigrateBitboxFailure extends MigrateBitboxState {
  const MigrateBitboxFailure(this.reason, {this.message, this.canRetry = false});

  final MigrateBitboxFailureReason reason;
  final String? message;
  final bool canRetry;

  @override
  List<Object?> get props => [reason, message, canRetry];
}
