import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_kyc_service.dart';
import 'package:realunit_wallet/screens/kyc/cubits/kyc/kyc_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/2fa/cubits/kyc_2fa/kyc_2fa_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/2fa/cubits/kyc_2fa_verify/kyc_2fa_verify_cubit.dart';
import 'package:realunit_wallet/setup/di.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';
import 'package:realunit_wallet/widgets/buttons/app_text_button.dart';
import 'package:realunit_wallet/widgets/form/labeled_text_field.dart';

class Kyc2FaPage extends StatelessWidget {
  const Kyc2FaPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => Kyc2FaCubit(
            getIt<DfxKycService>(),
          ),
        ),
        BlocProvider(
          create: (_) => Kyc2FaVerifyCubit(
            getIt<DfxKycService>(),
          ),
        ),
      ],
      child: const Kyc2FaView(),
    );
  }
}

class Kyc2FaView extends StatefulWidget {
  const Kyc2FaView({super.key});

  @override
  State<Kyc2FaView> createState() => _Kyc2FaViewState();
}

class _Kyc2FaViewState extends State<Kyc2FaView> {
  final _formKey = GlobalKey<FormState>();

  final codeCtrl = TextEditingController();

  @override
  void initState() {
    context.read<Kyc2FaCubit>().requestCode();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.of(context).twoFa)),
      body: MultiBlocListener(
        listeners: [
          BlocListener<Kyc2FaVerifyCubit, Kyc2FaVerifyState>(
            listener: (context, state) {
              if (state is Kyc2FaVerifySuccess) {
                context.read<KycCubit>().checkKyc();
              }
              if (state is Kyc2FaVerifyFailure) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(state.errorMessage),
                    backgroundColor: RealUnitColors.status.red600,
                  ),
                );
              }
            },
          ),
          BlocListener<Kyc2FaCubit, Kyc2FaState>(
            listener: (context, state) {
              if (state is Kyc2FaFailure) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(state.errorMessage),
                    backgroundColor: RealUnitColors.status.red600,
                  ),
                );
              }
            },
          ),
        ],
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: SafeArea(
            child: GestureDetector(
              onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
              behavior: HitTestBehavior.opaque,
              child: Form(
                key: _formKey,
                child: Column(
                  spacing: 24.0,
                  children: [
                    Text(
                      S.of(context).twoFaDescription,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: RealUnitColors.neutral500,
                        fontSize: 14,
                        height: 18 / 14,
                        letterSpacing: 0.0,
                      ),
                    ),
                    LabeledTextField(
                      hintText: '123456',
                      controller: codeCtrl,
                      keyboardType: TextInputType.number,
                      hideErrorText: false,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return S.of(context).twoFaCodeRequired;
                        }
                        if (!RegExp(r'^[0-9]+$').hasMatch(value)) {
                          return S.of(context).registerPhoneNumberOnlyDigits;
                        }
                        if (value.length != 6) {
                          return S.of(context).twoFaCodeTooShort;
                        }
                        return null;
                      },
                    ),
                    Column(
                      spacing: 4.0,
                      children: [
                        BlocBuilder<Kyc2FaVerifyCubit, Kyc2FaVerifyState>(
                          builder: (context, state) {
                            return AppFilledButton(
                              state: state is Kyc2FaVerifyLoading ? .loading : .idle,
                              onPressed: () {
                                if (_formKey.currentState?.validate() ?? false) {
                                  context.read<Kyc2FaVerifyCubit>().verifyCode(codeCtrl.text);
                                }
                              },
                              label: S.of(context).next,
                            );
                          },
                        ),
                        BlocBuilder<Kyc2FaCubit, Kyc2FaState>(
                          builder: (context, state) {
                            final isLoading = state is Kyc2FaLoading;
                            return AppTextButton(
                              fullWidth: false,
                              onPressed: isLoading
                                  ? null
                                  : () => context.read<Kyc2FaCubit>().requestCode(),
                              label: isLoading
                                  ? '${S.of(context).sending}...'
                                  : S.of(context).twoFaResendCode,
                            );
                          },
                        ),
                      ],
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
    codeCtrl.dispose();
    super.dispose();
  }
}
