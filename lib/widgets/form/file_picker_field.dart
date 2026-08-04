import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/form/file_preview_field.dart';

class FilePickerField extends StatelessWidget {
  final String label;
  final XFile? selectedFile;
  final VoidCallback onTap;
  final String? Function()? validator;

  const FilePickerField({
    super.key,
    required this.label,
    required this.selectedFile,
    required this.onTap,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    final error = validator?.call();

    return Column(
      crossAxisAlignment: .start,
      children: [
        Padding(
          padding: const .symmetric(horizontal: 12, vertical: 4),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: .bold,
              height: 18 / 13,
            ),
          ),
        ),
        FilePreviewField(
          selectedFile: selectedFile,
          onTap: onTap,
          onRemove: null,
          enabled: true,
          placeholderText: label,
          placeholderStyle: const TextStyle(
            color: RealUnitColors.neutral400,
          ),
          placeholderIconColor: RealUnitColors.neutral400,
          borderColor: error != null ? RealUnitColors.status.red600 : RealUnitColors.neutral300,
          borderRadius: 8,
          height: 76,
          padding: const .symmetric(horizontal: 10),
        ),
      ],
    );
  }
}
