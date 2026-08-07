import 'dart:developer' as developer;

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/models/registration/registration_email_status.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_registration_service.dart';

part 'support_email_capture_state.dart';

class SupportEmailCaptureCubit extends Cubit<SupportEmailCaptureState> {
  final RealUnitRegistrationService _service;

  SupportEmailCaptureCubit(RealUnitRegistrationService service)
    : _service = service,
      super(const SupportEmailCaptureInitial());

  Future<void> submit(String email) async {
    try {
      emit(const SupportEmailCaptureLoading());
      final status = await _service.registerEmail(email);

      switch (status) {
        case RegistrationEmailStatus.emailRegistered:
          emit(const SupportEmailCaptureSuccess());
        case RegistrationEmailStatus.mergeRequested:
          // The email is already known to DFX, so the API has sent an
          // account-merge confirmation email. Signal the view to route to the
          // shared email-verification flow so the user can confirm and link
          // this wallet to the existing account.
          emit(const SupportEmailCaptureMergeRequested());
      }
    } on ApiException catch (e) {
      developer.log(e.toString());
      emit(SupportEmailCaptureFailure(e.message));
    } catch (e) {
      developer.log(e.toString());
      emit(SupportEmailCaptureFailure(e.toString()));
    }
  }
}
