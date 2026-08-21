import 'dart:developer' as developer;

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_kyc_service.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/bitbox_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/models/country/country.dart';
import 'package:realunit_wallet/packages/service/dfx/models/registration/dto/real_unit_registration_request_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/registration/registration.dart';
import 'package:realunit_wallet/packages/service/dfx/models/registration/registration_status.dart';
import 'package:realunit_wallet/packages/service/dfx/models/registration/registration_user_type.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_registration_service.dart';

part 'kyc_registration_submit_state.dart';

class KycRegistrationSubmitCubit extends Cubit<KycRegistrationSubmitState> {
  final DfxKycService _kycService;
  final RealUnitRegistrationService _registrationService;

  KycRegistrationSubmitCubit(
    RealUnitRegistrationService registrationService,
    DfxKycService kycService,
  ) : _registrationService = registrationService,
      _kycService = kycService,
      super(KycRegistrationSubmitInitial());

  Future<void> submit({
    required RegistrationUserType type,
    required String firstName,
    required String lastName,
    required String phoneNumber,
    required String birthday,
    required Country nationality,
    required String addressStreet,
    required String addressStreetNumber,
    required String addressPostalCode,
    required String addressCity,
    required Country addressCountry,
    required bool swissTaxResidence,
    List<CountryAndTin>? countryAndTINs,
  }) async {
    try {
      emit(KycRegistrationSubmitLoading());

      final user = await _kycService.getUser();
      final mail = user.mail;
      if (mail != null) {
        final registration = Registration(
          type: type,
          email: mail,
          firstName: firstName,
          lastName: lastName,
          phoneNumber: phoneNumber,
          birthday: birthday,
          nationality: nationality,
          addressStreet: addressStreet,
          addressStreetNumber: addressStreetNumber,
          addressPostalCode: addressPostalCode,
          addressCity: addressCity,
          addressCountry: addressCountry,
          swissTaxResidence: swissTaxResidence,
          countryAndTINs: countryAndTINs,
        );

        await _doCompleteRegistration(registration);
      } else {
        emit(const KycRegistrationSubmitFailure('Mail could not be fetched'));
      }
    } on ApiException catch (e) {
      developer.log(e.toString());
      emit(KycRegistrationSubmitFailure(e.message, cause: e));
      return;
    } catch (e) {
      developer.log(e.toString());
      emit(KycRegistrationSubmitFailure(e.toString(), cause: e));
      return;
    }
  }

  Future<void> _doCompleteRegistration(Registration registration) async {
    try {
      final status = await _registrationService.completeRegistration(registration);
      // The API returns a structured `RegistrationStatus` in every
      // success case — including `alreadyRegistered`
      // (DFXswiss/api#3733). We forward whatever the backend says and
      // let `KycCubit.checkKyc()` resolve the next step on the listener
      // side; no more swallowing of generic ApiExceptions as success.
      emit(KycRegistrationSubmitSuccess(status));
    } on BitboxNotConnectedException {
      emit(
        KycRegistrationSubmitBitboxRequired(registration: registration),
      );
    } on ApiException catch (e) {
      developer.log(e.toString());
      emit(KycRegistrationSubmitFailure(e.message, cause: e));
    } catch (e) {
      developer.log(e.toString());
      emit(KycRegistrationSubmitFailure(e.toString(), cause: e));
    }
  }

  Future<void> retrySubmit(Registration registration) async {
    emit(KycRegistrationSubmitLoading());
    await _doCompleteRegistration(registration);
  }
}
