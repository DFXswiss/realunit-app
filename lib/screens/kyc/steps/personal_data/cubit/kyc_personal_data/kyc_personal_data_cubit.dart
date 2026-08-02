import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_kyc_service.dart';
import 'package:realunit_wallet/packages/service/dfx/models/country/country.dart';

part 'kyc_personal_data_state.dart';

class KycPersonalDataCubit extends Cubit<KycPersonalDataState> {
  final DfxKycService _kycService;

  KycPersonalDataCubit(DfxKycService kycService)
    : _kycService = kycService,
      super(const KycPersonalDataInitial());

  Future<void> submit({
    required String url,
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
      await _kycService.setData(url, {
        // The step only ever opens for accounts the app registered itself, and the type dropdown
        // offers `human` alone, so the account type is not re-asked here.
        'accountType': 'Personal',
        'firstName': firstName,
        'lastName': lastName,
        'phone': phone,
        'address': {
          'street': street,
          // Omitted rather than sent empty: the API treats houseNumber as optional and joins it onto
          // street, so a blank one would produce a trailing space in the stored address.
          if (houseNumber.isNotEmpty) 'houseNumber': houseNumber,
          'zip': zip,
          'city': city,
          'country': {'id': country.id},
        },
      });
      emit(const KycPersonalDataSuccess());
    } catch (e) {
      emit(KycPersonalDataFailure(e.toString()));
    }
  }
}
