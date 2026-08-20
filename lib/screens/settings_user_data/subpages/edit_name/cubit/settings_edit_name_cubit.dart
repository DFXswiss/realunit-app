import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_kyc_service.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/models/kyc/kyc_level.dart';

part 'settings_edit_name_state.dart';

class SettingsEditNameCubit extends Cubit<SettingsEditNameState> {
  final DfxKycService _kycService;

  SettingsEditNameCubit({required DfxKycService kycService})
    : _kycService = kycService,
      super(const SettingsEditNameInitial()) {
    _loadEdit();
  }

  Future<void> _loadEdit() async {
    try {
      emit(const SettingsEditNameLoading());
      final session = await _kycService.startStep(KycStepName.nameChange);

      // Per W3.2: the parent page only invokes this cubit when
      // `UserCapabilitiesDto.canEditName` is true, so an in-review state
      // is no longer reachable here. The pending branch is kept defensive
      // (race between the capability check and the start-step call) but
      // it is no longer the primary gating mechanism.
      final url = session.currentStep?.session.url;
      if (url == null) {
        emit(const SettingsEditNamePending());
        return;
      }
      emit(SettingsEditNameReady(url));
    } catch (e) {
      emit(SettingsEditNameFailure(ApiException.userFacingMessage(e)));
    }
  }

  void refresh() => _loadEdit();

  Future<void> submitName({
    required String firstName,
    required String lastName,
    required String fileBase64,
    required String fileName,
  }) async {
    final currentState = state;
    if (currentState is! SettingsEditNameReady) return;

    final url = currentState.url;
    try {
      emit(SettingsEditNameSubmitting(url));
      await _kycService.setData(url, {
        'firstName': firstName,
        'lastName': lastName,
        'file': fileBase64,
        'fileName': fileName,
      });
      emit(const SettingsEditNameSuccess());
    } catch (e) {
      emit(SettingsEditNameFailure(ApiException.userFacingMessage(e)));
    }
  }
}
