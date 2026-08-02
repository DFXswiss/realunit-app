import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_country_service.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_kyc_service.dart';
import 'package:realunit_wallet/packages/service/dfx/models/country/country.dart';
import 'package:realunit_wallet/packages/service/dfx/models/registration/kyc/kyc_personal_data.dart';
import 'package:realunit_wallet/packages/service/dfx/models/user/dto/real_unit_user_data_dto.dart';
import 'package:realunit_wallet/packages/utils/swiss_payment_text.dart';
import 'package:realunit_wallet/screens/kyc/cubits/kyc/kyc_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/personal_data/cubit/kyc_personal_data/kyc_personal_data_cubit.dart';
import 'package:realunit_wallet/screens/kyc/subpages/kyc_unsupported_step_page.dart';
import 'package:realunit_wallet/setup/di.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';
import 'package:realunit_wallet/widgets/form/country_field.dart';
import 'package:realunit_wallet/widgets/form/labeled_text_field.dart';
import 'package:realunit_wallet/widgets/form/phone_number_field.dart';
import 'package:realunit_wallet/widgets/scrollable_actions_layout.dart';

/// The PersonalData KYC step.
///
/// Registration normally satisfies this step without the user ever seeing it. It surfaces when the
/// step was re-opened deliberately — identification rejected the submitted data as not matching the
/// document — and the account has to correct it before identification can be retried. Until this
/// page existed the API asked for a step the app could not render, and onboarding dead-ended.
class KycPersonalDataPage extends StatelessWidget {
  final String url;
  final RealUnitUserDataDto? initialUserData;

  const KycPersonalDataPage({super.key, required this.url, this.initialUserData});

  @override
  Widget build(BuildContext context) {
    // The form can only express a personal account: submitting it sets `accountType` on the
    // account, and the API nulls every organization field whenever that value is `Personal`. So an
    // organization or sole-proprietorship account must never be offered this form — it would destroy
    // its organization data and drop the org-only steps from its required set.
    final userData = initialUserData;
    if (userData == null) {
      // Transient: the registration row carries no signed payload yet. Offer a retry rather than a
      // terminal screen, mirroring KycLinkWalletPage's missing-payload surface.
      return const _PersonalDataMissingUserDataPage();
    }
    if (userData.kycData.accountType != KycAccountType.personal) {
      // Same answer the app gives for any step it cannot render: an actionable handoff rather than a
      // dead end, and no internal step identifier surfaced to the user.
      return const KycUnsupportedStepPage();
    }

    return BlocProvider(
      create: (_) => KycPersonalDataCubit(getIt<DfxKycService>()),
      child: KycPersonalDataView(url: url, initialUserData: userData),
    );
  }
}

class KycPersonalDataView extends StatefulWidget {
  final String url;
  final RealUnitUserDataDto initialUserData;

  const KycPersonalDataView({super.key, required this.url, required this.initialUserData});

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
  Country? _initialCountry;

  @override
  void initState() {
    super.initState();

    // This is a correction form, not a fresh capture: the copy asks the user to check their details,
    // and every submit rewrites all of them, so shipping it empty would force a from-memory re-entry
    // and let a typo overwrite data that was already correct. Seeded from the payload the parent
    // cubit already fetched — no extra round-trip. Same shape as KycRegistrationView.initState.
    final kycData = widget.initialUserData.kycData;
    firstNameCtrl.text = kycData.firstName;
    lastNameCtrl.text = kycData.lastName;
    phoneCtrl.value = kycData.phone;
    streetCtrl.text = kycData.address.street;
    houseNumberCtrl.text = kycData.address.houseNumber ?? '';
    zipCtrl.text = kycData.address.zip;
    cityCtrl.text = kycData.address.city;

    // The DTO carries only the country id, so the field populates when the lookup resolves; the
    // form renders immediately either way.
    unawaited(_resolveInitialCountry(kycData.address.country));
  }

  Future<void> _resolveInitialCountry(int countryId) async {
    try {
      final countries = await getIt<DfxCountryService>().getAllCountries();
      if (!mounted) return;

      final country = countries.where((c) => c.id == countryId).firstOrNull;
      // Never clobber a pick the user already made: CountryField runs its own lookup, and if that one
      // resolves first the field is live before this seed arrives.
      if (country == null || countryCtrl.value != null) return;

      setState(() => _initialCountry = country);
      countryCtrl.value = country;
    } catch (_) {
      // Degrade to an empty picker — CountryField renders its own error and retry.
    }
  }

  String? _required(String? value) {
    if (value == null || value.isEmpty) return '';
    if (!isSwissPaymentText(value)) return S.of(context).swissPaymentTextInvalid;
    return null;
  }

  void _submit() {
    FocusManager.instance.primaryFocus?.unfocus();
    // CountryField registers a validator with the enclosing Form, so a successful validate()
    // guarantees countryCtrl is set. phoneCtrl is guaranteed by PhoneNumberField itself: it defaults
    // to its first prefix when unseeded and only accepts a seeded value it can decompose.
    if (!(_formKey.currentState?.validate() ?? false)) return;

    context.read<KycPersonalDataCubit>().submit(
      url: widget.url,
      accountType: widget.initialUserData.kycData.accountType,
      firstName: firstNameCtrl.text,
      lastName: lastNameCtrl.text,
      phone: phoneCtrl.value!,
      street: streetCtrl.text,
      houseNumber: houseNumberCtrl.text,
      zip: zipCtrl.text,
      city: cityCtrl.text,
      country: countryCtrl.value!,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.of(context).personalData)),
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
                      initialValue: _initialCountry,
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

/// Shown when the step is actionable but the registration row carries no signed payload to seed the
/// form from. Transient, so it offers a refresh rather than dead-ending.
class _PersonalDataMissingUserDataPage extends StatelessWidget {
  const _PersonalDataMissingUserDataPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.of(context).personalData)),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0),
        child: SafeArea(
          child: ScrollableActionsLayout(
            centerBody: true,
            body: Text(
              S.of(context).kycFailure,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            actions: [
              AppFilledButton(
                onPressed: () => context.read<KycCubit>().checkKyc(),
                label: S.of(context).refresh,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
