import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:realunit_wallet/styles/colors.dart';

/// Bordered file-preview body: either a 48×48 thumbnail with file name and
/// action icons, or a centered placeholder row.
///
/// Does not render a section/field label — callers supply that themselves.
class FilePreviewField extends StatelessWidget {
  final XFile? selectedFile;
  final VoidCallback onTap;
  final VoidCallback? onRemove;
  final bool enabled;
  final String placeholderText;
  final TextStyle? placeholderStyle;
  final Color placeholderIconColor;
  final Color borderColor;
  final double borderRadius;
  final double? height;
  final EdgeInsetsGeometry padding;

  const FilePreviewField({
    super.key,
    required this.selectedFile,
    required this.onTap,
    this.onRemove,
    this.enabled = true,
    required this.placeholderText,
    this.placeholderStyle,
    required this.placeholderIconColor,
    required this.borderColor,
    required this.borderRadius,
    this.height,
    required this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: .infinity,
        height: height,
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: .circular(borderRadius),
          border: .all(color: borderColor),
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
                      cacheWidth: (48 * MediaQuery.devicePixelRatioOf(context)).round(),
                      errorBuilder: (context, error, stackTrace) {
                        // Visible fallback replaces Flutter's grey box; log keeps
                        // the decode failure visible. May fire again on rebuilds
                        // that stay in the error state.
                        developer.log(
                          'Could not decode file preview: $error',
                          name: '$FilePreviewField',
                        );
                        return Container(
                          width: 48,
                          height: 48,
                          color: RealUnitColors.neutral200,
                          child: const Icon(
                            Icons.broken_image_rounded,
                            color: RealUnitColors.neutral500,
                          ),
                        );
                      },
                    ),
                  ),
                  Expanded(
                    child: Text(
                      selectedFile!.name,
                      maxLines: 1,
                      overflow: .ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  const Icon(
                    Icons.edit_rounded,
                    color: RealUnitColors.realUnitBlue,
                  ),
                  if (onRemove != null)
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
                    color: placeholderIconColor,
                  ),
                  Flexible(
                    child: Text(
                      placeholderText,
                      maxLines: 1,
                      overflow: .ellipsis,
                      style: placeholderStyle,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
