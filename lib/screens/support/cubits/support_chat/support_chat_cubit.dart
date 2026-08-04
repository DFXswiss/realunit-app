import 'dart:developer' as developer;

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_support_service.dart';
import 'package:realunit_wallet/packages/service/dfx/models/support/support_issue.dart';
import 'package:realunit_wallet/packages/utils/xfile_extension.dart';
import 'package:realunit_wallet/screens/support/cubits/support_chat/support_chat_state.dart';

class SupportChatCubit extends Cubit<SupportChatState> {
  final DfxSupportService _supportService;
  final String _ticketUid;

  SupportChatCubit(DfxSupportService supportService, String ticketUid)
    : _supportService = supportService,
      _ticketUid = ticketUid,
      super(const SupportChatInitial()) {
    loadTicket();
  }

  Future<void> loadTicket() async {
    if (isClosed) return;
    emit(const SupportChatLoading());

    try {
      final ticket = await _supportService.getTicket(_ticketUid);
      if (isClosed) return;
      emit(SupportChatLoaded(ticket: SupportIssue.fromDto(ticket)));
    } catch (e) {
      developer.log('Could not load ticket: $e', name: '$SupportChatCubit');
      if (isClosed) return;
      emit(SupportChatError(e.toString()));
    }
  }

  void selectAttachment(XFile file) {
    final currentState = state;
    if (currentState is! SupportChatLoaded || currentState.isSending) return;
    emit(currentState.copyWith(attachment: file));
  }

  void clearAttachment() {
    final currentState = state;
    if (currentState is! SupportChatLoaded || currentState.isSending) return;
    emit(currentState.copyWith(clearAttachment: true));
  }

  /// Returns `true` after a successful POST (refetch is best-effort).
  /// Returns `false` on every early-exit, closed cubit, and send failure so
  /// the UI can clear the text field on success only — without inferring
  /// success from state.
  Future<bool> sendMessage(String message) async {
    final currentState = state;
    if (currentState is! SupportChatLoaded) return false;

    final trimmed = message.trim();
    final attachment = currentState.attachment;
    if (trimmed.isEmpty && attachment == null) return false;

    if (isClosed) return false;
    emit(currentState.copyWith(isSending: true));

    try {
      final base64 = await attachment?.toBase64DataUri();
      await _supportService.sendMessage(
        _ticketUid,
        message: trimmed.isEmpty ? null : message,
        file: base64,
        fileName: attachment?.name,
      );
    } catch (e) {
      developer.log('Could not send message: $e', name: '$SupportChatCubit');
      if (isClosed) return false;
      emit(currentState.copyWith(isSending: false));
      return false;
    }

    // POST succeeded — the message is at support. Refetch is independent so a
    // failed getTicket must not report the send as a failure (which would leave
    // text/attachment and invite a double send).
    try {
      final ticket = await _supportService.getTicket(_ticketUid);
      if (isClosed) return false;
      emit(SupportChatLoaded(ticket: SupportIssue.fromDto(ticket)));
      return true;
    } catch (e) {
      developer.log(
        'Could not reload ticket after send: $e',
        name: '$SupportChatCubit',
      );
      if (isClosed) return false;
      // Keep the pre-send ticket content; clear isSending and the attachment so
      // the input does not keep a file that was already uploaded.
      emit(currentState.copyWith(isSending: false, clearAttachment: true));
      return true;
    }
  }
}
