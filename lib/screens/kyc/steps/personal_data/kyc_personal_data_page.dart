import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_kyc_service.dart';
import 'package:realunit_wallet/packages/service/dfx/models/country/country.dart';
import 'package:realunit_wallet/packages/utils/swiss_payment_text.dart';
import 'package:realunit_wallet/screens/kyc/cubits/kyc/kyc_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/personal_data/cubit/kyc_personal_data/kyc_personal_data_cubit.dart';
import 'package:realunit_wallet/setup/di.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';
import 'package:realunit_wallet/widgets/form/country_field.dart';
import 'package:realunit_wallet/widgets/form/labeled_text_field.dart';
import 'package:realunit_wallet/widgets/form/phone_number_field.dart';

/// The PersonalData KYC step.
///
/// Registration normally satisfies this step without the user ever seeing it. It surfaces when the
/// step was re-opened deliberately — identification rejected the submitted data as not matching the
/// document — and the account has to correct it before identification can be retried. Until this
/// page existed the API asked for a step the app could not render, and onboarding dead-ended.
class KycPersonalDataPage extends StatelessWidget {
  final String url;

  const KycPersonalDataPage({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => KycPersonalDataCubit(getIt<DfxKycService>()),
      child: KycPersonalDataView(url: url),
    );
  }
}

class KycPersonalDataView extends StatefulWidget {
  final String url;

  const KycPersonalDataView({super.key, required this.url});

  @override
  State<KycPersonalDataView> createState() => _KycPersonalDataViewState();
}

class _KycPersonalDataViewState extends State<KycPersonalDataView> {
  final _formKey = GlobalKey<FormState>();
  final firstNameCtrl = TextEditingController();
  final lastNameCtrl = TextEditingController();
  final phoneCtrl = ValueNotifier<String?>(null);
  final streetCtrl = TextEditingController();
  final houseNumberCtrl = TextEditingController();
  final zipCtrl = TextEditingController();
  final cityCtrl = TextEditingController();
  final countryCtrl = ValueNotifier<Country?>(null);

  String? _required(String? value) {
    if (value == null || value.isEmpty) return '';
    if (!isSwissPaymentText(value)) return S.of(context).swissPaymentTextInvalid;
    return null;
  }

  void _submit() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // The country field and the phone field validate themselves, but neither writes into the Form,
    // so an untouched one leaves its notifier null and would submit an incomplete body.
    final country = countryCtrl.value;
    final phone = phoneCtrl.value;
    if (country == null || phone == null || phone.isEmpty) return;

    context.read<KycPersonalDataCubit>().submit(
      url: widget.url,
      firstName: firstNameCtrl.text,
      lastName: lastNameCtrl.text,
      phone: phone,
      street: streetCtrl.text,
      houseNumber: houseNumberCtrl.text,
      zip: zipCtrl.text,
      city: cityCtrl.text,
      country: country,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.of(context).kycPersonalDataTitle)),
      body: BlocListener<KycPersonalDataCubit, KycPersonalDataState>(
        listener: (context, state) {
          if (state is KycPersonalDataSuccess) {
            // The API decides what comes next; re-reading it is what moves the flow on.
            context.read<KycCubit>().checkKyc();
          }
          if (state is KycPersonalDataFailure) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(S.of(context).kycPersonalDataFailed(state.message)),
                backgroundColor: RealUnitColors.status.red600,
              ),
            );
          }
        },
        child: SingleChildScrollView(
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
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(S.of(context).kycPersonalDataDescription),
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
                            textCapitalization: TextCapitalization.words,
                            validator: _required,
                          ),
                        ),
                        Expanded(
                          child: LabeledTextField(
                            label: S.of(context).lastName,
                            hintText: 'Mustermann',
                            controller: lastNameCtrl,
                            textCapitalization: TextCapitalization.words,
                            validator: _required,
                          ),
                        ),
                      ],
                    ),
                    PhoneNumberField(controller: phoneCtrl),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 10,
                      children: [
                        Expanded(
                          flex: 2,
                          child: LabeledTextField(
                            hintText: S.of(context).streetHint,
                            controller: streetCtrl,
                            label: S.of(context).street,
                            keyboardType: TextInputType.streetAddress,
                            textCapitalization: TextCapitalization.words,
                            validator: _required,
                          ),
                        ),
                        Expanded(
                          child: LabeledTextField(
                            hintText: '13',
                            controller: houseNumberCtrl,
                            label: S.of(context).number,
                            keyboardType: TextInputType.streetAddress,
                            validator: _required,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 10,
                      children: [
                        Expanded(
                          flex: 2,
                          child: LabeledTextField(
                            hintText: '8000',
                            controller: zipCtrl,
                            label: S.of(context).postcodeAbr,
                            // Alphanumeric in many residence countries (NL "1011 AB", UK "EC1A 1BB"),
                            // so not a number-only keyboard — mirrors the registration address step.
                            keyboardType: TextInputType.text,
                            validator: _required,
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: LabeledTextField(
                            hintText: S.of(context).cityHint,
                            controller: cityCtrl,
                            label: S.of(context).city,
                            keyboardType: TextInputType.text,
                            textCapitalization: TextCapitalization.words,
                            validator: _required,
                          ),
                        ),
                      ],
                    ),
                    CountryField(
                      label: S.of(context).country,
                      purpose: CountryFieldPurpose.residence,
                      onChanged: (country) => countryCtrl.value = country,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16.0),
                      child: BlocBuilder<KycPersonalDataCubit, KycPersonalDataState>(
                        builder: (context, state) {
                          return AppFilledButton(
                            state: state is KycPersonalDataLoading ? .loading : .idle,
                            onPressed: _submit,
                            label: S.of(context).next,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    firstNameCtrl.dispose();
    lastNameCtrl.dispose();
    phoneCtrl.dispose();
    streetCtrl.dispose();
    houseNumberCtrl.dispose();
    zipCtrl.dispose();
    cityCtrl.dispose();
    countryCtrl.dispose();
    super.dispose();
  }
}
