import 'package:flutter/material.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/widgets/form/dropdown_field.dart';
import 'package:realunit_wallet/widgets/form/labeled_text_field.dart';

/// The dial prefixes the field can decompose a stored number into. A seeded value that starts with
/// none of these leaves `prefix` null, and the field then never writes edits back to the controller —
/// so callers that pre-fill the controller must check against this list first.
const phoneNumberPrefixes = ['+41', '+49'];

class PhoneNumberField extends StatefulWidget {
  final ValueNotifier<String?> controller;

  const PhoneNumberField({super.key, required this.controller});

  @override
  State<PhoneNumberField> createState() => _PhoneNumberFieldState();
}

class _PhoneNumberFieldState extends State<PhoneNumberField> {
  final prefixes = phoneNumberPrefixes;
  String? prefix;
  String? number;

  @override
  void initState() {
    super.initState();
    final value = widget.controller.value;
    if (value != null) {
      for (var p in prefixes) {
        if (value.startsWith(p)) {
          prefix = p;
          number = value.substring(p.length);
          break;
        }
      }
    } else {
      prefix = prefixes.first;
    }
  }

  void updatePhoneNumber() {
    if (prefix != null && number != null) {
      final value = '$prefix$number';
      widget.controller.value = value;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: .start,
      children: [
        Padding(
          padding: const .symmetric(horizontal: 12, vertical: 4),
          child: Text(
            S.of(context).phoneNumber,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: .bold,
              height: 18 / 13,
            ),
          ),
        ),
        Row(
          crossAxisAlignment: .start,
          spacing: 10,
          children: [
            Expanded(
              flex: 3,
              child: DropdownField<String>(
                initialValue: prefix,
                items: prefixes
                    .map((d) => DropdownMenuItem(value: d, child: Text(d.toString())))
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    prefix = v;
                    updatePhoneNumber();
                  }
                },
              ),
            ),
            Expanded(
              flex: 6,
              child: LabeledTextField(
                hintText: '1231234567',
                initialValue: number,
                keyboardType: .phone,
                onChanged: (v) {
                  number = v;
                  updatePhoneNumber();
                },
                hideErrorText: false,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return S.of(context).registerPhoneNumberInvalid;
                  }
                  if (!RegExp(r'^[0-9]+$').hasMatch(value)) {
                    return S.of(context).registerPhoneNumberOnlyDigits;
                  }
                  // Length is validated by the API (libphonenumber); the client
                  // must not gate on it — see CONTRIBUTING "the API decides".
                  return null;
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}
