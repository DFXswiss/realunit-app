import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/bitbox_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/models/user/dto/real_unit_user_data_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_registration_service.dart';

part 'kyc_link_wallet_state.dart';

/// Drives the streamlined "Add this wallet" page. The userData is supplied by
/// the parent `KycCubit` (which already fetched it via `getRegistrationInfo()` as
/// part of its routing decision) — this cubit never re-fetches. On submit,
/// calls `RealUnitRegistrationService.registerWallet`. Mirror of
/// `KycRegistrationSubmitCubit` for the AddWallet branch — distinct state
/// shape because the page collects no input.
class KycLinkWalletCubit extends Cubit<KycLinkWalletState> {
  final RealUnitRegistrationService _registrationService;

  KycLinkWalletCubit(RealUnitRegistrationService registrationService, RealUnitUserDataDto userData)
    : _registrationService = registrationService,
      super(KycLinkWalletReady(userData));

  Future<void> submit(RealUnitUserDataDto userData) async {
    try {
      emit(KycLinkWalletSubmitting(userData));
      await _registrationService.registerWallet(userData);
      emit(const KycLinkWalletSuccess());
    } on BitboxNotConnectedException {
      emit(KycLinkWalletBitboxRequired(userData));
    } on ApiException catch (e) {
      emit(KycLinkWalletFailure(e.message, cause: e));
    } catch (e) {
      emit(KycLinkWalletFailure(e.toString(), cause: e));
    }
  }

  /// Re-runs registration after the BitBox connection was established via the
  /// `ConnectBitboxPage` sheet. Mirror of `KycRegistrationSubmitCubit.retrySubmit`.
  Future<void> retrySubmit(RealUnitUserDataDto userData) => submit(userData);
}
