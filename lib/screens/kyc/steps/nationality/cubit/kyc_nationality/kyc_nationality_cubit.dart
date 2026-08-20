import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_kyc_service.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/models/country/country.dart';

part 'kyc_nationality_state.dart';

class KycNationalityCubit extends Cubit<KycNationalityState> {
  final DfxKycService _kycService;

  KycNationalityCubit(DfxKycService kycService)
    : _kycService = kycService,
      super(const KycNationalityInitial());

  Future<void> registerNationality({
    required String url,
    required Country nationality,
  }) async {
    try {
      emit(const KycNationalityLoading());
      await _kycService.setData(url, {
        'nationality': {'id': nationality.id},
      });
      emit(const KycNationalitySuccess());
    } on ApiException catch (e) {
      emit(KycNationalityFailure(e.message));
    } catch (e) {
      emit(KycNationalityFailure(e.toString()));
    }
  }
}
