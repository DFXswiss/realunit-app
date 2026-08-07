import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_registration_service.dart';
import 'package:realunit_wallet/screens/kyc/steps/email/subpages/kyc_email_verification_page.dart';
import 'package:realunit_wallet/screens/support/cubits/support_email_capture/support_email_capture_cubit.dart';
import 'package:realunit_wallet/setup/di.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';
import 'package:realunit_wallet/widgets/form/labeled_text_field.dart';

class SupportEmailCapturePage extends StatelessWidget {
  // Optional entry-point-specific description. The page registers a
  // *primary* email regardless of caller; only the explanatory copy
  // differs (Support vs. buy-confirm gate). `null` keeps the default
  // Support wording, so existing callers stay unchanged.
  final String? description;

  const SupportEmailCapturePage({super.key, this.description});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => SupportEmailCaptureCubit(
        getIt<RealUnitRegistrationService>(),
      ),
      child: SupportEmailCaptureView(description: description),
    );
  }
}

class SupportEmailCaptureView extends StatelessWidget {
  final String? description;

  const SupportEmailCaptureView({super.key, this.description});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.of(context).supportEmailCaptureTitle)),
      body: SupportEmailCaptureForm(description: description),
    );
  }
}

class SupportEmailCaptureForm extends StatefulWidget {
  final String? description;

  const SupportEmailCaptureForm({super.key, this.description});

  @override
  State<SupportEmailCaptureForm> createState() => _SupportEmailCaptureFormState();
}

class _SupportEmailCaptureFormState extends State<SupportEmailCaptureForm> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<SupportEmailCaptureCubit, SupportEmailCaptureState>(
      listener: (context, state) async {
        if (state is SupportEmailCaptureSuccess) {
          // Signal to the caller that the email is now set on the
          // user record so it can re-init its cubit and route to the
          // Support page.
          Navigator.of(context).pop(true);
          return;
        }
        if (state is SupportEmailCaptureMergeRequested) {
          // The email belongs to an existing account and the API has already
          // sent an account-merge confirmation email. Route to the same
          // verification page the KYC email step uses so the user can confirm.
          // On confirmation this wallet is linked to the existing account, so
          // its primary email is now set — signal the caller exactly like a
          // direct registration success. If the user backs out unconfirmed,
          // stay on the form so they can retry.
          final isConfirmed = await Navigator.push<bool>(
            context,
            MaterialPageRoute<bool>(
              builder: (_) => const KycEmailVerificationPage(),
            ),
          );
          if (isConfirmed == true && context.mounted) {
            Navigator.of(context).pop(true);
          }
          return;
        }
        if (state is SupportEmailCaptureFailure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: RealUnitColors.status.red600,
            ),
          );
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
                crossAxisAlignment: .start,
                spacing: 16,
                children: [
                  Padding(
                    padding: const .only(top: 16),
                    child: Text(
                      widget.description ?? S.of(context).supportEmailCaptureDescription,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  LabeledTextField(
                    label: S.of(context).email,
                    hintText: 'max@mustermann.ch',
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
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
                  BlocBuilder<SupportEmailCaptureCubit, SupportEmailCaptureState>(
                    builder: (context, state) {
                      return AppFilledButton(
                        state: state is SupportEmailCaptureLoading
                            ? .loading
                            : .idle,
                        onPressed: () {
                          FocusManager.instance.primaryFocus?.unfocus();
                          if (_formKey.currentState?.validate() ?? false) {
                            context.read<SupportEmailCaptureCubit>().submit(
                              _emailCtrl.text.trim(),
                            );
                          }
                        },
                        label: S.of(context).supportEmailCaptureContinue,
                      );
                    },
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
