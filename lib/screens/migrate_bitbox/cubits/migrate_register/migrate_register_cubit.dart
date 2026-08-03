import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/bitbox_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/models/registration/registration_status.dart';
import 'package:realunit_wallet/packages/service/dfx/models/user/dto/real_unit_user_data_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_registration_service.dart';
import 'package:realunit_wallet/packages/wallet/exceptions/signing_cancelled_exception.dart';
import 'package:realunit_wallet/packages/wallet/wallet_account.dart';

part 'migrate_register_state.dart';

class MigrateRegisterCubit extends Cubit<MigrateRegisterState> {
  MigrateRegisterCubit(
    this._registrationService, {
    required this.account,
    required this.userData,
    required this.bearerToken,
  }) : super(const MigrateRegisterReady());

  final RealUnitRegistrationService _registrationService;
  final AWalletAccount account;
  final RealUnitUserDataDto userData;
  final String bearerToken;

  Future<void> submit() async {
    emit(const MigrateRegisterSubmitting());
    try {
      final status = await _registrationService.registerWalletFor(
        account,
        userData,
        bearerToken,
      );
      switch (status) {
        case RegistrationStatus.completed:
        case RegistrationStatus.alreadyRegistered:
          emit(const MigrateRegisterSuccess());
        case RegistrationStatus.pendingReview:
        case RegistrationStatus.forwardingFailed:
          emit(const MigrateRegisterPending());
      }
    } on SigningCancelledException {
      emit(
        const MigrateRegisterFailure(
          MigrateRegisterFailureReason.signatureCancelled,
          canRetry: true,
        ),
      );
    } on BitboxNotConnectedException {
      emit(
        const MigrateRegisterFailure(
          MigrateRegisterFailureReason.bitboxNotConnected,
          canRetry: true,
        ),
      );
    } catch (e) {
      emit(
        MigrateRegisterFailure(
          MigrateRegisterFailureReason.generic,
          message: e.toString(),
          canRetry: true,
        ),
      );
    }
  }

  /// Mirror of KycLinkWalletCubit.retrySubmit.
  Future<void> retrySubmit() => submit();
}
