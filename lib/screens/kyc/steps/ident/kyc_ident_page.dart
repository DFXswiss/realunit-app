import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/screens/kyc/cubits/kyc/kyc_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/ident/cubits/kyc_ident/kyc_ident_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/ident/sumsub_ident_sdk_adapter.dart';
import 'package:realunit_wallet/screens/settings/bloc/settings_bloc.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';

class KycIdentPage extends StatelessWidget {
  final String accessToken;

  const KycIdentPage({
    super.key,
    required this.accessToken,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => KycIdentCubit(identPort: const SumsubIdentSdkAdapter()),
      child: KycIdentView(
        accessToken: accessToken,
      ),
    );
  }
}

class KycIdentView extends StatelessWidget {
  final String accessToken;

  const KycIdentView({super.key, required this.accessToken});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.of(context).identityCheck)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: BlocListener<KycIdentCubit, KycIdentState>(
          listener: (context, state) {
            if (state is KycIdentSuccess) {
              context.read<KycCubit>().checkKyc();
            }
            if (state is KycIdentFailure) {
              if (state.status == FailureStatus.finallyRejected) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      S.of(context).identityCheckFinallyFailed,
                    ),
                    backgroundColor: RealUnitColors.status.red600,
                  ),
                );
                return;
              } else if (state.status == FailureStatus.error) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(state.errorMessage ?? (throw StateError('ident error without message'))),
                    backgroundColor: RealUnitColors.status.red600,
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      S.of(context).identityCheckFailed,
                    ),
                    backgroundColor: RealUnitColors.status.red600,
                  ),
                );
              }
            }
          },
          child: SafeArea(
            child: Column(
              spacing: 16.0,
              children: [
                const SizedBox(height: 44.0),
                Text(
                  S.of(context).identityCheckProcess,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    height: 24 / 20,
                    letterSpacing: -0.2,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 16.0),
                  child: Image.asset('assets/images/illustrations/ident_verification.png'),
                ),
                Text(
                  S.of(context).identityCheckProcessDescription,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: RealUnitColors.neutral900,
                    fontSize: 14,
                    height: 18 / 14,
                    letterSpacing: 0.0,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  child: SizedBox(
                    width: double.infinity,
                    child: BlocBuilder<KycIdentCubit, KycIdentState>(
                      builder: (context, state) {
                        if (state is KycIdentFailure) {
                          if (state.status == FailureStatus.finallyRejected) {
                            return AppFilledButton(
                              onPressed: null,
                              label: S.of(context).next,
                            );
                          }
                        }
                        return AppFilledButton(
                          state: state is KycIdentLoading ? .loading : .idle,
                          onPressed: () {
                            context.read<KycIdentCubit>().startIdent(
                              accessToken,
                              localeCode: context.read<SettingsBloc>().state.language.code,
                            );
                          },
                          label: S.of(context).next,
                        );
                      },
                    ),
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
