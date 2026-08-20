import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_registration_service.dart';
import 'package:realunit_wallet/screens/kyc/cubits/kyc/kyc_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/email/cubits/email_step/kyc_email_step_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/email/subpages/kyc_email_verification_page.dart';
import 'package:realunit_wallet/setup/di.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';
import 'package:realunit_wallet/widgets/form/labeled_text_field.dart';

class KycEmailPage extends StatelessWidget {
  const KycEmailPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => KycEmailStepCubit(
        getIt<RealUnitRegistrationService>(),
      ),
      child: const KycEmailView(),
    );
  }
}

class KycEmailView extends StatelessWidget {
  const KycEmailView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.of(context).registerEmail)),
      body: const KycEmailForm(),
    );
  }
}

class KycEmailForm extends StatefulWidget {
  const KycEmailForm({super.key});

  @override
  State<KycEmailForm> createState() => _KycEmailFormState();
}

class _KycEmailFormState extends State<KycEmailForm> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<KycEmailStepCubit, KycEmailStepState>(
      listener: (context, state) async {
        if (state is KycEmailStepFailure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: RealUnitColors.status.red600,
            ),
          );
        }
        if (state is KycEmailStepSuccess) {
          if (state.status == .emailRegistered) {
            context.read<KycCubit>().checkKyc();
          }
          if (state.status == .mergeRequested) {
            final isConfirmed = await Navigator.push<bool>(
              context,
              MaterialPageRoute<bool>(
                builder: (BuildContext context) => const KycEmailVerificationPage(),
              ),
            );
            if (isConfirmed == true && context.mounted) {
              // Merge confirmed. `checkKyc()` re-fetches `getRegistrationInfo`
              // and routes this wallet by the API `state`: AddWallet → link
              // wallet, NewRegistration → full registration form,
              // AlreadyRegistered → forward. The KYC flow is the single source
              // of registration routing — see CONTRIBUTING.md "API as Decision
              // Authority".
              context.read<KycCubit>().checkKyc();
            }
          }
        }
      },
      child: SingleChildScrollView(
        padding: const .symmetric(horizontal: 20),
        child: SafeArea(
          child: GestureDetector(
            onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  LabeledTextField(
                    label: S.of(context).email,
                    hintText: 'max@mustermann.ch',
                    controller: _emailCtrl,
                    keyboardType: .emailAddress,
                    hideErrorText: false,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return S.of(context).registerEmailRequired;
                      }
                      if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) {
                        return S.of(context).registerEmailInvalid;
                      }
                      return null;
                    },
                  ),
                  Padding(
                    padding: const .symmetric(vertical: 16.0),
                    child: BlocBuilder<KycEmailStepCubit, KycEmailStepState>(
                      builder: (context, state) {
                        return AppFilledButton(
                          state: state is KycEmailStepLoading ? .loading : .idle,
                          onPressed: () {
                            FocusManager.instance.primaryFocus?.unfocus();
                            if (_formKey.currentState?.validate() ?? false) {
                              context.read<KycEmailStepCubit>().registerEmail(
                                _emailCtrl.text.trim(),
                              );
                            }
                          },
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
    );
  }
}
