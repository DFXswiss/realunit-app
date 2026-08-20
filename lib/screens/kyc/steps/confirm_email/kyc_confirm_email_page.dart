import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_registration_service.dart';
import 'package:realunit_wallet/screens/kyc/cubits/kyc/kyc_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/confirm_email/cubits/kyc_confirm_email_cubit.dart';
import 'package:realunit_wallet/setup/di.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';

class KycConfirmEmailPage extends StatelessWidget {
  const KycConfirmEmailPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => KycConfirmEmailCubit(
        getIt<RealUnitRegistrationService>(),
      ),
      child: const KycConfirmEmailView(),
    );
  }
}

class KycConfirmEmailView extends StatelessWidget {
  const KycConfirmEmailView({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocListener<KycConfirmEmailCubit, KycConfirmEmailState>(
      listener: (context, state) {
        if (state is KycConfirmEmailNotConfirmed) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(S.of(context).registerEmailConfirmationNotYet),
              backgroundColor: RealUnitColors.status.red600,
            ),
          );
        }
        if (state is KycConfirmEmailFailure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: RealUnitColors.status.red600,
            ),
          );
        }
        if (state is KycConfirmEmailConfirmed) {
          // Confirmation flipped true (or the API reports no gate). Hand back to
          // the KYC flow, which re-fetches `getRegistrationInfo` and routes on
          // whatever the API now reports — see CONTRIBUTING.md "API as Decision
          // Authority".
          context.read<KycCubit>().checkKyc();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(S.of(context).registerEmailConfirmation),
        ),
        body: SingleChildScrollView(
          padding: const .symmetric(horizontal: 20),
          child: SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 44.0),
                SvgPicture.asset(
                  'assets/images/illustrations/email_verification.svg',
                  width: 75,
                ),
                const SizedBox(height: 20.0),
                Column(
                  spacing: 8.0,
                  children: [
                    Text(
                      S.of(context).registerEmailConfirmationTitle,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    Text(
                      S.of(context).registerEmailConfirmationDescription,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: RealUnitColors.neutral500,
                      ),
                    ),
                    Padding(
                      padding: const .symmetric(vertical: 16.0),
                      child: BlocBuilder<KycConfirmEmailCubit, KycConfirmEmailState>(
                        builder: (context, state) {
                          return AppFilledButton(
                            state: state is KycConfirmEmailLoading ? .loading : .idle,
                            onPressed: () =>
                                context.read<KycConfirmEmailCubit>().recheck(),
                            label: S.of(context).registerEmailConfirmationButton,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
