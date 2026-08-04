import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/form/file_preview_field.dart';

/// Attachment picker styled like the surrounding ticket-form fields
/// (`support_create_ticket_page`: bodyLarge section labels, radius 12,
/// `neutral200` border, blue when a file is selected).
class SupportAttachmentField extends StatelessWidget {
  final XFile? selectedFile;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  /// When false, taps (pick + remove) are ignored — same pattern as the chat
  /// input's `onPressed: isSending ? null : …` (no opacity/color change).
  final bool enabled;

  const SupportAttachmentField({
    super.key,
    required this.selectedFile,
    required this.onTap,
    required this.onRemove,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Same default the form's TextField uses for hintText (no hard-coded size/color).
    final placeholderStyle =
        theme.inputDecorationTheme.hintStyle ??
        theme.textTheme.bodyLarge?.copyWith(color: theme.hintColor);
    final placeholderColor = placeholderStyle?.color ?? theme.hintColor;

    return Column(
      crossAxisAlignment: .start,
      spacing: 12.0,
      children: [
        Text(
          S.of(context).supportAttachment,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: .w600,
          ),
        ),
        FilePreviewField(
          selectedFile: selectedFile,
          onTap: onTap,
          onRemove: onRemove,
          enabled: enabled,
          placeholderText: S.of(context).supportChooseAttachment,
          placeholderStyle: placeholderStyle,
          placeholderIconColor: placeholderColor,
          borderColor: selectedFile != null
              ? RealUnitColors.realUnitBlue
              : RealUnitColors.neutral200,
          borderRadius: 12,
          height: null,
          padding: const .symmetric(horizontal: 12, vertical: 12),
        ),
      ],
    );
  }
}
