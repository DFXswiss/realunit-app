import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_kyc_service.dart';
import 'package:realunit_wallet/packages/service/dfx/models/country/country.dart';
import 'package:realunit_wallet/packages/service/dfx/models/registration/kyc/kyc_personal_data.dart';

part 'kyc_personal_data_state.dart';

class KycPersonalDataCubit extends Cubit<KycPersonalDataState> {
  final DfxKycService _kycService;

  KycPersonalDataCubit(DfxKycService kycService)
    : _kycService = kycService,
      super(const KycPersonalDataInitial());

  Future<void> submit({
    required String url,
    required KycAccountType accountType,
    required String firstName,
    required String lastName,
    required String phone,
    required String street,
    required String houseNumber,
    required String zip,
    required String city,
    required Country country,
  }) async {
    try {
      emit(const KycPersonalDataLoading());
      await _kycService.setData(
        url,
        KycPersonalData(
          // Passed in, never assumed: the page refuses to render for anything but a personal
          // account, and sending the same value it checked keeps the two from drifting apart.
          accountType: accountType,
          firstName: firstName,
          lastName: lastName,
          phone: phone,
          address: KycAddress(
            street: street,
            // Always sent. The form requires it, and an omitted key would leave the stored value
            // unchanged rather than clearing it — wrong for a form whose purpose is correction.
            houseNumber: houseNumber,
            zip: zip,
            city: city,
            country: country.id,
          ),
        ).toJson(),
      );
      emit(const KycPersonalDataSuccess());
    } catch (e) {
      emit(KycPersonalDataFailure(e.toString()));
    }
  }
}
