import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_kyc_service.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_legal_service.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_registration_service.dart';
import 'package:realunit_wallet/screens/kyc/cubits/kyc/kyc_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/2fa/kyc_2fa_page.dart';
import 'package:realunit_wallet/screens/kyc/steps/confirm_email/kyc_confirm_email_page.dart';
import 'package:realunit_wallet/screens/kyc/steps/email/kyc_email_page.dart';
import 'package:realunit_wallet/screens/kyc/steps/financial_data/kyc_financial_data_page.dart';
import 'package:realunit_wallet/screens/kyc/steps/ident/kyc_ident_page.dart';
import 'package:realunit_wallet/screens/kyc/steps/link_wallet/kyc_link_wallet_page.dart';
import 'package:realunit_wallet/screens/kyc/steps/nationality/kyc_nationality_page.dart';
import 'package:realunit_wallet/screens/kyc/steps/personal_data/kyc_personal_data_page.dart';
import 'package:realunit_wallet/screens/kyc/steps/registration/kyc_registration_page.dart';
import 'package:realunit_wallet/screens/kyc/steps/signature_unsupported/kyc_signature_unsupported_page.dart';
import 'package:realunit_wallet/screens/kyc/subpages/kyc_account_merge_page.dart';
import 'package:realunit_wallet/screens/kyc/subpages/kyc_completed_page.dart';
import 'package:realunit_wallet/screens/kyc/subpages/kyc_failure_page.dart';
import 'package:realunit_wallet/screens/kyc/subpages/kyc_loading_page.dart';
import 'package:realunit_wallet/screens/kyc/subpages/kyc_manual_review_page.dart';
import 'package:realunit_wallet/screens/kyc/subpages/kyc_merge_processing_page.dart';
import 'package:realunit_wallet/screens/kyc/subpages/kyc_pending_page.dart';
import 'package:realunit_wallet/screens/kyc/subpages/kyc_unsupported_step_page.dart';
import 'package:realunit_wallet/screens/legal/legal_disclaimer_page.dart';
import 'package:realunit_wallet/setup/di.dart';

class KycPageManager extends StatelessWidget {
  final String? kycContext;

  const KycPageManager({super.key, this.kycContext});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => KycCubit(
        getIt<DfxKycService>(),
        getIt<RealUnitRegistrationService>(),
        getIt<RealUnitLegalService>(),
        getIt<AppStore>(),
      )..checkKyc(context: kycContext),
      child: const KycViewManager(),
    );
  }
}

class KycViewManager extends StatelessWidget {
  const KycViewManager({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<KycCubit, KycState>(
      builder: (context, state) => switch (state) {
        KycLoading() => const KycLoadingPage(),
        KycFailure(:final message) => KycFailurePage(message: message),
        KycSignatureUnsupportedFailure() => const KycSignatureUnsupportedPage(),
        KycUnsupportedStepFailure() => const KycUnsupportedStepPage(),
        KycAccountMergeRequested() => const KycAccountMergePage(),
        KycMergeProcessing() => const KycMergeProcessingPage(),
        KycManualReview() => const KycManualReviewPage(),
        KycPending(:final pendingStep) => KycPendingPage(pendingStep: pendingStep),
        KycCompleted() => const KycCompletedPage(),
        KycSuccess(:final currentStep, :final urlOrToken, :final realUnitUserData) =>
          switch (currentStep) {
            KycStep.email => const KycEmailPage(),
            KycStep.confirmEmail => const KycConfirmEmailPage(),
            KycStep.legalDisclaimer => LegalDisclaimerPage(
              onCompleted: () {
                // Records acceptance server-side and re-runs `checkKyc()`
                // internally, so the API drives the next routing decision.
                context.read<KycCubit>().acceptLegalDisclaimer();
              },
            ),
            KycStep.registration => KycRegistrationPage(initialUserData: realUnitUserData),
            KycStep.personalData => KycPersonalDataPage(
              url: urlOrToken ?? '',
              initialUserData: realUnitUserData,
            ),
            KycStep.linkWallet => KycLinkWalletPage(userData: realUnitUserData),
            KycStep.nationality => KycNationalityPage(url: urlOrToken ?? ''),
            KycStep.twoFa => const Kyc2FaPage(),
            KycStep.ident => KycIdentPage(accessToken: urlOrToken ?? ''),
            KycStep.financialData => KycFinancialDataPage(url: urlOrToken ?? ''),
            // Exhaustive over KycStep so a new value is a compile error here
            // (forced handling) rather than a silent blank Scaffold. dfxApproval
            // was the missing case that fell through to the old blank fallback.
            KycStep.dfxApproval =>
              const KycPendingPage(pendingStep: KycStep.dfxApproval),
          },
        KycState() => const Scaffold(),
      },
    );
  }
}
