import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:realunit_wallet/styles/colors.dart';

class LabeledTextField extends StatelessWidget {
  final String? label;
  final String? initialValue;
  final TextEditingController? controller;
  final String? hintText;
  final String? prefixText;
  final TextInputType? keyboardType;
  final void Function(String)? onChanged;
  final String? Function(String?)? validator;
  final int? maxLines;
  final bool hideErrorText;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;
  final Widget? suffixIcon;
  final Iterable<String>? autofillHints;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final SmartDashesType? smartDashesType;
  final SmartQuotesType? smartQuotesType;
  final SpellCheckConfiguration? spellCheckConfiguration;
  final GestureTapCallback? onTap;
  final bool autocorrect;
  final bool enableSuggestions;
  final bool enableIMEPersonalizedLearning;
  final bool autofocus;
  final bool enabled;

  const LabeledTextField({
    super.key,
    this.label,
    this.initialValue,
    this.controller,
    this.hintText,
    this.prefixText,
    this.keyboardType,
    this.onChanged,
    this.validator,
    this.maxLines = 1,
    this.hideErrorText = true,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.suffixIcon,
    this.autofillHints,
    this.textInputAction = TextInputAction.next,
    this.onFieldSubmitted,
    this.smartDashesType,
    this.smartQuotesType,
    this.spellCheckConfiguration,
    this.onTap,
    this.autocorrect = false,
    this.enableSuggestions = false,
    this.enableIMEPersonalizedLearning = true,
    this.autofocus = false,
    this.enabled = true,
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
          autocorrect: autocorrect,
          enableSuggestions: enableSuggestions,
          enableIMEPersonalizedLearning: enableIMEPersonalizedLearning,
          autofocus: autofocus,
          enabled: enabled,
          onTap: onTap,
          textInputAction: textInputAction,
          onFieldSubmitted: onFieldSubmitted,
          textCapitalization: textCapitalization,
          decoration: InputDecoration(
            hintText: hintText,
            prefixText: prefixText,
            suffixIcon: suffixIcon,
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
          autofillHints: autofillHints,
          smartDashesType: smartDashesType,
          smartQuotesType: smartQuotesType,
          spellCheckConfiguration: spellCheckConfiguration,
          validator: validator,
        ),
      ],
    );
  }
}
