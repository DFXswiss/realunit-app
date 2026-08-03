part of 'migrate_register_cubit.dart';

enum MigrateRegisterFailureReason {
  signatureCancelled,
  bitboxNotConnected,
  generic,
}

sealed class MigrateRegisterState extends Equatable {
  const MigrateRegisterState();

  @override
  List<Object?> get props => [];
}

class MigrateRegisterReady extends MigrateRegisterState {
  const MigrateRegisterReady();
}

class MigrateRegisterSubmitting extends MigrateRegisterState {
  const MigrateRegisterSubmitting();
}

class MigrateRegisterPending extends MigrateRegisterState {
  const MigrateRegisterPending();
}

class MigrateRegisterSuccess extends MigrateRegisterState {
  const MigrateRegisterSuccess();
}

class MigrateRegisterFailure extends MigrateRegisterState {
  const MigrateRegisterFailure(
    this.reason, {
    this.message,
    this.canRetry = false,
  });

  final MigrateRegisterFailureReason reason;
  final String? message;
  final bool canRetry;

  @override
  List<Object?> get props => [reason, message, canRetry];
}
