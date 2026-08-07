import 'package:flutter/material.dart';
import 'package:realunit_wallet/styles/colors.dart';

class DropdownField<T> extends StatelessWidget {
  final String? label;
  final T? initialValue;
  final String? hintText;
  final void Function(T?)? onChanged;
  final String? Function(T?)? validator;
  final List<DropdownMenuItem<T>> items;
  final bool hideErrorText;
  final AutovalidateMode? autovalidateMode;

  const DropdownField({
    super.key,
    this.label,
    this.initialValue,
    this.hintText,
    this.onChanged,
    this.validator,
    required this.items,
    this.hideErrorText = true,
    this.autovalidateMode,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: .start,
      children: [
        if (label != null)
          Padding(
            padding: const .symmetric(
              horizontal: 12.0,
              vertical: 4.0,
            ),
            child: Text(
              label!,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: .bold,
                height: 18 / 13,
              ),
            ),
          ),
        ButtonTheme(
          alignedDropdown: true,
          child: DropdownButtonFormField<T>(
            initialValue: initialValue,
            validator: validator,
            autovalidateMode: autovalidateMode,
            onChanged: onChanged,
            items: items,
            isExpanded: true,
            isDense: true,
            borderRadius: .circular(8.0),
            decoration: InputDecoration(
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
              border: .none,
              contentPadding: const .symmetric(
                horizontal: 10.0,
              ),
              errorStyle: hideErrorText
                  ? const TextStyle(
                      height: -1,
                      fontSize: 0,
                    )
                  : null,
            ),
            hint: hintText != null
                ? Text(
                    hintText!,
                    style: const TextStyle(
                      color: RealUnitColors.neutral400,
                    ),
                  )
                : null,
            icon: const Padding(
              padding: .only(right: 8),
              child: Icon(Icons.arrow_drop_down),
            ),
          ),
        ),
      ],
    );
  }
}
