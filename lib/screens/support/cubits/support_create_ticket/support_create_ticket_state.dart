import 'package:equatable/equatable.dart';
import 'package:image_picker/image_picker.dart';
import 'package:realunit_wallet/packages/service/dfx/models/support/support_issue_reason.dart';
import 'package:realunit_wallet/packages/service/dfx/models/support/support_issue_type.dart';

final class SupportCreateTicketState extends Equatable {
  final SupportIssueType? selectedType;
  final SupportIssueReason? selectedReason;
  final String message;
  final XFile? attachment;
  final bool isSubmitting;
  final bool isSuccess;
  final String? error;

  const SupportCreateTicketState({
    this.selectedType,
    this.selectedReason,
    this.message = '',
    this.attachment,
    this.isSubmitting = false,
    this.isSuccess = false,
    this.error,
  });

  SupportCreateTicketState copyWith({
    SupportIssueType? selectedType,
    SupportIssueReason? selectedReason,
    String? message,
    XFile? attachment,
    bool clearAttachment = false,
    bool? isSubmitting,
    bool? isSuccess,
    String? error,
  }) {
    return SupportCreateTicketState(
      selectedType: selectedType ?? this.selectedType,
      selectedReason: selectedReason ?? this.selectedReason,
      message: message ?? this.message,
      attachment: clearAttachment ? null : (attachment ?? this.attachment),
      isSubmitting: isSubmitting ?? this.isSubmitting,
      isSuccess: isSuccess ?? this.isSuccess,
      error: error,
    );
  }

  bool get canSubmit =>
      selectedType != null &&
      selectedReason != null &&
      message.trim().isNotEmpty &&
      !isSubmitting;

  @override
  List<Object?> get props => [
        selectedType,
        selectedReason,
        message,
        attachment,
        isSubmitting,
        isSuccess,
        error,
      ];
}
