import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_kyc_service.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';

part 'settings_edit_phone_number_state.dart';

class SettingsEditPhoneNumberCubit extends Cubit<SettingsEditPhoneNumberState> {
  final DfxKycService _kycService;

  SettingsEditPhoneNumberCubit({required DfxKycService kycService})
    : _kycService = kycService,
      super(const SettingsEditPhoneNumberInitial());

  Future<void> editPhoneNumber(String phone) async {
    try {
      emit(const SettingsEditPhoneNumberSubmitting());
      await _kycService.updateUser({'phone': phone});
      emit(const SettingsEditPhoneNumberSuccess());
    } catch (e) {
      emit(SettingsEditPhoneNumberFailure(ApiException.userFacingMessage(e)));
    }
  }
}
