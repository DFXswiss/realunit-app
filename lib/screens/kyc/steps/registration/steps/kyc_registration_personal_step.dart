import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/models/country/country.dart';
import 'package:realunit_wallet/packages/service/dfx/models/registration/registration_user_type.dart';
import 'package:realunit_wallet/packages/utils/swiss_payment_text.dart';
import 'package:realunit_wallet/screens/kyc/steps/registration/cubits/registration_step/kyc_registration_step_cubit.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';
import 'package:realunit_wallet/widgets/form/birthday_field.dart';
import 'package:realunit_wallet/widgets/form/country_field.dart';
import 'package:realunit_wallet/widgets/form/dropdown_field.dart';
import 'package:realunit_wallet/widgets/form/labeled_text_field.dart';
import 'package:realunit_wallet/widgets/form/phone_number_field.dart';

class KycRegistrationPersonalStep extends StatelessWidget {
  final ValueNotifier<RegistrationUserType> typeCtrl;
  final TextEditingController firstNameCtrl;
  final TextEditingController lastNameCtrl;
  final ValueNotifier<String?> birthdayCtrl;
  final ValueNotifier<String?> phoneCtrl;
  final ValueNotifier<Country?> nationalityCtrl;
  final TextEditingController? referralCodeCtrl;
  final Country? initialNationality;

  KycRegistrationPersonalStep({
    super.key,
    required this.typeCtrl,
    required this.firstNameCtrl,
    required this.lastNameCtrl,
    required this.phoneCtrl,
    required this.nationalityCtrl,
    required this.birthdayCtrl,
    this.referralCodeCtrl,
    this.initialNationality,
  });

  final _formKey = GlobalKey<FormState>();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SafeArea(
        child: GestureDetector(
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          behavior: HitTestBehavior.opaque,
          child: Form(
            key: _formKey,
            child: Column(
              spacing: 16,
              children: [
                DropdownField<RegistrationUserType>(
                  label: S.of(context).registerAccountType,
                  hintText: RegistrationUserType.human.toString(),
                  items: [
                    RegistrationUserType.values.first,
                  ].map((d) => DropdownMenuItem(value: d, child: Text(d.name(context)))).toList(),
                  initialValue: RegistrationUserType.human,
                  onChanged: (v) {
                    if (v != null) typeCtrl.value = v;
                  },
                  validator: (v) => v == null ? '' : null,
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 10,
                  children: [
                    Expanded(
                      child: LabeledTextField(
                        label: S.of(context).firstName,
                        hintText: 'Max',
                        controller: firstNameCtrl,
                        // keyboardType: TextInputType.name, https://github.com/flutter/flutter/issues/67282
                        textCapitalization: TextCapitalization.words,
                        validator: (value) {
                          if (value == null || value.isEmpty) return '';
                          if (!isSwissPaymentText(value)) return S.of(context).swissPaymentTextInvalid;
                          return null;
                        },
                      ),
                    ),
                    Expanded(
                      child: LabeledTextField(
                        label: S.of(context).lastName,
                        hintText: 'Mustermann',
                        controller: lastNameCtrl,
                        // keyboardType: TextInputType.name, https://github.com/flutter/flutter/issues/67282
                        textCapitalization: TextCapitalization.words,
                        validator: (value) {
                          if (value == null || value.isEmpty) return '';
                          if (!isSwissPaymentText(value)) return S.of(context).swissPaymentTextInvalid;
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                BirthdayField(
                  controller: birthdayCtrl,
                ),
                PhoneNumberField(
                  controller: phoneCtrl,
                ),
                CountryField(
                  label: S.of(context).registerCitizenship,
                  purpose: CountryFieldPurpose.nationality,
                  initialValue: initialNationality,
                  onChanged: (country) => nationalityCtrl.value = country,
                ),
                if (referralCodeCtrl != null)
                  LabeledTextField(
                    label: S.of(context).referralCodeOptional,
                    hintText: S.of(context).referralCodeHint,
                    controller: referralCodeCtrl!,
                    textCapitalization: TextCapitalization.characters,
                  ),
                Padding(
                  padding: const .symmetric(vertical: 16.0),
                  child: AppFilledButton(
                    onPressed: () {
                      FocusManager.instance.primaryFocus?.unfocus();
                      if (_formKey.currentState?.validate() ?? false) {
                        context.read<KycRegistrationStepCubit>().next();
                      }
                    },
                    label: S.of(context).next,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
