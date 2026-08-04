import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/styles/colors.dart';

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
        GestureDetector(
          onTap: enabled ? onTap : null,
          child: Container(
            width: .infinity,
            padding: const .symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: .circular(12),
              border: .all(
                color: selectedFile != null
                    ? RealUnitColors.realUnitBlue
                    : RealUnitColors.neutral200,
              ),
            ),
            child: selectedFile != null
                ? Row(
                    spacing: 12.0,
                    children: [
                      ClipRRect(
                        borderRadius: .circular(4),
                        child: Image.file(
                          File(selectedFile!.path),
                          width: 48,
                          height: 48,
                          fit: .cover,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          selectedFile!.name,
                          maxLines: 1,
                          overflow: .ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      const Icon(
                        Icons.edit_rounded,
                        color: RealUnitColors.realUnitBlue,
                      ),
                      GestureDetector(
                        onTap: enabled ? onRemove : null,
                        behavior: .opaque,
                        // 48dp minimum tap target (Material accessibility).
                        child: const SizedBox(
                          width: 48,
                          height: 48,
                          child: Center(
                            child: Icon(
                              Icons.close_rounded,
                              color: RealUnitColors.neutral500,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : Row(
                    spacing: 8.0,
                    mainAxisAlignment: .center,
                    children: [
                      Icon(
                        Icons.add_a_photo_rounded,
                        color: placeholderColor,
                      ),
                      Flexible(
                        child: Text(
                          S.of(context).supportChooseAttachment,
                          maxLines: 1,
                          overflow: .ellipsis,
                          style: placeholderStyle,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}
