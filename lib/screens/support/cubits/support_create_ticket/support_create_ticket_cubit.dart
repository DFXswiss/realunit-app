import 'dart:developer' as developer;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_support_service.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/models/support/support_issue_reason.dart';
import 'package:realunit_wallet/packages/service/dfx/models/support/support_issue_type.dart';
import 'package:realunit_wallet/packages/utils/xfile_extension.dart';
import 'package:realunit_wallet/screens/support/cubits/support_create_ticket/support_create_ticket_state.dart';

class SupportCreateTicketCubit extends Cubit<SupportCreateTicketState> {
  final DfxSupportService _supportService;

  SupportCreateTicketCubit(DfxSupportService supportService)
    : _supportService = supportService,
      super(const SupportCreateTicketState());

  void selectType(SupportIssueType type) {
    if (state.isSubmitting) return;
    emit(state.copyWith(selectedType: type, selectedReason: SupportIssueReason.other));
  }

  void selectReason(SupportIssueReason reason) {
    if (state.isSubmitting) return;
    emit(state.copyWith(selectedReason: reason));
  }

  void updateMessage(String message) {
    if (state.isSubmitting) return;
    emit(state.copyWith(message: message));
  }

  void selectAttachment(XFile file) {
    if (state.isSubmitting) return;
    emit(state.copyWith(attachment: file));
  }

  void clearAttachment() {
    if (state.isSubmitting) return;
    emit(state.copyWith(clearAttachment: true));
  }

  Future<void> submit() async {
    if (!state.canSubmit) return;

    // Hoist every field that createTicket reads before the await so a
    // concurrent UI change (or a late re-read of state) cannot mix a
    // pre-await attachment with a post-await type/message — or produce
    // file != null with fileName == null.
    final attachment = state.attachment;
    final selectedType = state.selectedType!;
    final selectedReason = state.selectedReason!;
    final message = state.message.trim();
    if (isClosed) return;
    emit(state.copyWith(isSubmitting: true, error: null));

    try {
      final base64 = await attachment?.toBase64DataUri();
      await _supportService.createTicket(
        type: selectedType,
        reason: selectedReason,
        name: _getTicketName(selectedType),
        message: message,
        file: base64,
        fileName: attachment?.name,
      );

      if (isClosed) return;
      emit(state.copyWith(isSubmitting: false, isSuccess: true));
    } catch (e) {
      developer.log('Could not create ticket: $e', name: '$SupportCreateTicketCubit');
      if (isClosed) return;
      emit(state.copyWith(isSubmitting: false, error: ApiException.userFacingMessage(e)));
    }
  }

  String _getTicketName(SupportIssueType type) {
    return switch (type) {
      SupportIssueType.genericIssue => 'General Issue',
      SupportIssueType.transactionIssue => 'Transaction Issue',
      SupportIssueType.kycIssue => 'KYC Issue',
      SupportIssueType.limitRequest => 'Limit Request',
      SupportIssueType.bugReport => 'Bug Report',
      _ => 'Support Request',
    };
  }
}
