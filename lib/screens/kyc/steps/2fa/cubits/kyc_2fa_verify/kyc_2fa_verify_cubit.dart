import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_kyc_service.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';

part 'kyc_2fa_verify_state.dart';

class Kyc2FaVerifyCubit extends Cubit<Kyc2FaVerifyState> {
  final DfxKycService _dfxKycService;

  Kyc2FaVerifyCubit(DfxKycService dfxKycService)
    : _dfxKycService = dfxKycService,
      super(const Kyc2FaVerifyInitial());

  Future<void> verifyCode(String code) async {
    try {
      emit(const Kyc2FaVerifyLoading());
      await _dfxKycService.verify2FaCode(code);
      emit(const Kyc2FaVerifySuccess());
    } on ApiException catch (e) {
      emit(Kyc2FaVerifyFailure(errorMessage: e.message));
    } catch (e) {
      emit(Kyc2FaVerifyFailure(errorMessage: e.toString()));
    }
  }
}
