import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:realunit_wallet/styles/colors.dart';

class LabeledTextField extends StatelessWidget {
  final String? label;
  final String? initialValue;
  final TextEditingController? controller;
  final String? hintText;
  final TextInputType? keyboardType;
  final void Function(String)? onChanged;
  final String? Function(String?)? validator;
  final int? maxLines;
  final bool hideErrorText;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;

  const LabeledTextField({
    super.key,
    this.label,
    this.initialValue,
    this.controller,
    this.hintText,
    this.keyboardType,
    this.onChanged,
    this.validator,
    this.maxLines = 1,
    this.hideErrorText = true,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: .start,
      children: [
        if (label != null)
          Padding(
            padding: const .symmetric(horizontal: 12, vertical: 4),
            child: Text(
              label!,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: .bold,
                height: 18 / 13,
              ),
            ),
          ),
        TextFormField(
          initialValue: initialValue,
          onChanged: onChanged,
          controller: controller,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: .next,
          textCapitalization: textCapitalization,
          decoration: InputDecoration(
            hintText: hintText,
            enabledBorder: const OutlineInputBorder(
              borderRadius: .all(.circular(8.0)),
              borderSide: BorderSide(color: RealUnitColors.neutral300),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: .all(.circular(8.0)),
              borderSide: BorderSide(color: RealUnitColors.realUnitBlue, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: const .all(.circular(8.0)),
              borderSide: BorderSide(color: RealUnitColors.status.red600),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: const .all(.circular(8.0)),
              borderSide: BorderSide(color: RealUnitColors.status.red600, width: 2),
            ),
            contentPadding: const .symmetric(horizontal: 10, vertical: 14),
            hintStyle: const TextStyle(color: RealUnitColors.neutral400),
            errorStyle: hideErrorText
                ? const TextStyle(
                    height: -1,
                    fontSize: 0,
                  )
                : null,
          ),
          maxLines: maxLines,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          validator: validator,
        ),
      ],
    );
  }
}
