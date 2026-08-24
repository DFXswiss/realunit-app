import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/sell_payment_info.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';
import 'package:realunit_wallet/screens/buy/buy_page.dart';
import 'package:realunit_wallet/screens/buy/buy_payment_details_page.dart';
import 'package:realunit_wallet/screens/create_wallet/create_wallet_page.dart';
import 'package:realunit_wallet/screens/dashboard/dashboard_page.dart';
import 'package:realunit_wallet/screens/debug_auth/debug_auth_page.dart';
import 'package:realunit_wallet/screens/hardware_connect_bitbox/bitbox_address_recovery_page.dart';
import 'package:realunit_wallet/screens/home/home_page.dart';
import 'package:realunit_wallet/screens/kyc/kyc_page_manager.dart';
import 'package:realunit_wallet/screens/legal/legal_disclaimer_page.dart';
import 'package:realunit_wallet/screens/legal/subpages/legal_document_page.dart';
import 'package:realunit_wallet/screens/onboarding/onboarding_completed_page.dart';
import 'package:realunit_wallet/screens/pay/pay_scan_page.dart';
import 'package:realunit_wallet/screens/pin/setup_pin_page.dart';
import 'package:realunit_wallet/screens/pin/verify_pin_page.dart';
import 'package:realunit_wallet/screens/receive/receive_page.dart';
import 'package:realunit_wallet/screens/restore_wallet/restore_wallet_page.dart';
import 'package:realunit_wallet/screens/sell/sell_page.dart';
import 'package:realunit_wallet/screens/sell_bitbox/sell_bitbox_page.dart';
import 'package:realunit_wallet/screens/send/send_recipient_page.dart';
import 'package:realunit_wallet/screens/settings/settings_page.dart';
import 'package:realunit_wallet/screens/settings_contact/settings_contact_page.dart';
import 'package:realunit_wallet/screens/settings_currencies/settings_currencies_page.dart';
import 'package:realunit_wallet/screens/settings_languages/settings_languages_page.dart';
import 'package:realunit_wallet/screens/settings_legal_documents/settings_legal_documents_page.dart';
import 'package:realunit_wallet/screens/settings_legal_documents/subpages/settings_aktionariat_documents_page.dart';
import 'package:realunit_wallet/screens/settings_legal_documents/subpages/settings_dfx_documents_page.dart';
import 'package:realunit_wallet/screens/settings_network/settings_network_page.dart';
import 'package:realunit_wallet/screens/settings_security/settings_security_page.dart';
import 'package:realunit_wallet/screens/settings_seed/settings_seed_page.dart';
import 'package:realunit_wallet/screens/settings_tax_report/settings_tax_report_page.dart';
import 'package:realunit_wallet/screens/settings_user_data/settings_user_data_page.dart';
import 'package:realunit_wallet/screens/settings_user_data/subpages/edit_address/settings_edit_address_page.dart';
import 'package:realunit_wallet/screens/settings_user_data/subpages/edit_name/settings_edit_name_page.dart';
import 'package:realunit_wallet/screens/settings_user_data/subpages/edit_phone_number/settings_edit_phone_number_page.dart';
import 'package:realunit_wallet/screens/settings_wallet_address/settings_wallet_address_page.dart';
import 'package:realunit_wallet/screens/support/subpages/support_chat_page.dart';
import 'package:realunit_wallet/screens/support/subpages/support_create_ticket_page.dart';
import 'package:realunit_wallet/screens/support/subpages/support_email_capture_page.dart';
import 'package:realunit_wallet/screens/support/subpages/support_tickets_page.dart';
import 'package:realunit_wallet/screens/support/support_page.dart';
import 'package:realunit_wallet/screens/transaction_history/transaction_history_page.dart';
import 'package:realunit_wallet/screens/verify_seed/verify_seed_page.dart';
import 'package:realunit_wallet/screens/web_view/web_view_page.dart';
import 'package:realunit_wallet/screens/welcome/welcome_page.dart';
import 'package:realunit_wallet/setup/routing/boot_navigation.dart';
import 'package:realunit_wallet/setup/routing/routes/app_link_entry.dart';
import 'package:realunit_wallet/setup/routing/routes/app_routes.dart';
import 'package:realunit_wallet/setup/routing/routes/legal_routes.dart';
import 'package:realunit_wallet/setup/routing/routes/onboarding_routes.dart';
import 'package:realunit_wallet/setup/routing/routes/pin_routes.dart';
import 'package:realunit_wallet/setup/routing/routes/settings_routes.dart';
import 'package:realunit_wallet/setup/routing/routes/support_routes.dart';

final GoRouter routerConfig = GoRouter(
  initialLocation: '/home',
  // Custom-scheme opens (realunit-wallet://…, canonical realunit-wallet://open)
  // only foreground the app; they must not force any navigation. Cold start:
  // the redirect hands off to the normal boot entry. Warm resume: the redirect
  // lets the scheme URL fall through unmatched and onException keeps the
  // current configuration — the only true no-op that survives imperatively
  // pushed routes (e.g. the KYC flow). See app_link_entry.dart.
  redirect: (context, state) => appLinkSchemeRedirect(
    state,
    effectiveLocation(routerConfig.routerDelegate.currentConfiguration),
    routerConfig,
  ),
  onException: appLinkOnException,
  routes: <RouteBase>[
    GoRoute(
      name: AppRoutes.home,
      path: '/home',
      builder: (_, _) => const HomePage(),
    ),

    GoRoute(
      name: OnboardingRoutes.welcome,
      path: '/welcome',
      builder: (_, _) => const WelcomePage(),
    ),

    GoRoute(
      name: OnboardingRoutes.createWallet,
      path: '/createWallet',
      builder: (_, _) => const CreateWalletPage(),
    ),

    GoRoute(
      name: OnboardingRoutes.restoreWallet,
      path: '/restoreWallet',
      builder: (_, _) => const RestoreWalletPage(),
    ),

    GoRoute(
      name: OnboardingRoutes.verifySeed,
      path: '/verifySeed',
      builder: (_, state) => VerifySeedPage(wallet: state.extra as SoftwareWallet),
    ),

    GoRoute(
      name: OnboardingRoutes.completed,
      path: '/onboardingComplete',
      builder: (_, _) => const OnboardingCompletedPage(),
    ),

    if (kDebugMode)
      GoRoute(
        name: OnboardingRoutes.debugAuth,
        path: '/debugAuth',
        builder: (_, _) => const DebugAuthPage(),
      ),

    GoRoute(
      name: PinRoutes.gate,
      path: '/pinGate',
      builder: (_, state) {
        final params = state.extra as VerifyPinParams;
        return VerifyPinPage(
          description: params.description,
          onAuthenticated: params.onAuthenticated,
        );
      },
    ),

    GoRoute(
      name: PinRoutes.setup,
      path: '/setupPin',
      builder: (_, _) => const SetupPinPage(),
    ),

    GoRoute(
      name: PinRoutes.verify,
      path: '/verifyPin',
      builder: (_, _) => VerifyPinPage.appLock(),
    ),

    GoRoute(
      name: AppRoutes.dashboard,
      path: '/dashboard',
      builder: (_, _) => const DashboardPage(),
      routes: [
        GoRoute(
          name: AppRoutes.transactionHistory,
          path: 'transactionHistory',
          builder: (_, _) => const TransactionHistoryPage(),
        ),
      ],
    ),

    GoRoute(
      name: AppRoutes.buy,
      path: '/buy',
      builder: (_, _) => const BuyPage(),
    ),

    GoRoute(
      name: AppRoutes.buyPaymentDetails,
      path: '/buyPaymentDetails',
      builder: (_, state) => BuyPaymentDetailsPage(
        params: state.extra as BuyPaymentDetailsParams,
      ),
    ),

    GoRoute(
      name: AppRoutes.sell,
      path: '/sell',
      builder: (_, _) => const SellPage(),
    ),

    GoRoute(
      name: AppRoutes.sellBitbox,
      path: '/sellBitbox',
      builder: (_, state) => SellBitboxPage(paymentInfo: state.extra as SellPaymentInfo),
    ),

    GoRoute(
      name: AppRoutes.pay,
      path: '/pay',
      builder: (_, state) => PayScanPage(
        initialPayload: state.extra is String ? state.extra as String : null,
      ),
    ),

    GoRoute(
      name: AppRoutes.send,
      path: '/send',
      builder: (_, _) => const SendRecipientPage(),
    ),

    GoRoute(
      name: LegalRoutes.disclaimer,
      path: '/legalDisclaimer',
      builder: (_, _) => const LegalDisclaimerPage(),
    ),

    GoRoute(
      name: LegalRoutes.document,
      path: '/legalDocument',
      builder: (_, state) {
        final extra = state.extra;
        return LegalDocumentPage(
          params: extra as LegalDocumentParams,
        );
      },
    ),

    GoRoute(
      name: LegalRoutes.terms,
      path: '/termsOfUse',
      builder: (context, state) => LegalDocumentPage(
        params: LegalDocumentParams(
          title: S.of(context).termsOfUse,
          assetBaseName: 'terms_of_use',
        ),
      ),
    ),

    GoRoute(
      name: AppRoutes.kyc,
      path: '/kyc',
      builder: (_, state) => KycPageManager(kycContext: state.extra as String?),
    ),

    GoRoute(
      name: AppRoutes.receive,
      path: '/receive',
      builder: (_, _) => const ReceivePage(isBottomSheet: false),
    ),

    GoRoute(
      name: AppRoutes.bitboxAddressRecovery,
      path: '/bitboxAddressRecovery',
      builder: (_, _) => const BitboxAddressRecoveryPage(),
    ),

    GoRoute(
      name: SettingsRoutes.settings,
      path: '/settings',
      builder: (_, _) => const SettingsPage(),
      routes: [
        GoRoute(
          name: SettingsRoutes.aktionariatDocuments,
          path: 'aktionariatDocuments',
          builder: (_, _) => const SettingsAktionariatDocumentsPage(),
        ),
        GoRoute(
          name: SettingsRoutes.contact,
          path: 'contact',
          builder: (_, _) => const SettingsContactPage(),
        ),
        GoRoute(
          name: SettingsRoutes.currencies,
          path: 'currencies',
          builder: (_, _) => const SettingsCurrenciesPage(),
        ),
        GoRoute(
          name: SettingsRoutes.dfxDocuments,
          path: 'dfxDocuments',
          builder: (_, _) => const SettingsDfxDocumentsPage(),
        ),
        GoRoute(
          name: SettingsRoutes.languages,
          path: 'languages',
          builder: (_, _) => const SettingsLanguagePage(),
        ),
        GoRoute(
          name: SettingsRoutes.legalDocuments,
          path: 'legalDocuments',
          builder: (_, _) => const SettingsLegalDocumentsPage(),
        ),
        GoRoute(
          name: SettingsRoutes.network,
          path: 'network',
          builder: (_, _) => SettingsNetworkPage(),
        ),
        GoRoute(
          name: SettingsRoutes.security,
          path: 'security',
          builder: (_, _) => const SettingsSecurityPage(),
        ),
        GoRoute(
          name: SettingsRoutes.changePin,
          path: 'security/changePin',
          builder: (_, state) {
            final params = state.extra as ChangePinParams;
            return SetupPinPage(
              promptBiometrics: false,
              onCompleted: params.onCompleted,
            );
          },
        ),
        GoRoute(
          name: SettingsRoutes.taxReport,
          path: 'taxReport',
          builder: (_, _) => const SettingsTaxReportPage(),
        ),
        GoRoute(
          name: SettingsRoutes.seed,
          path: 'seed',
          builder: (_, _) => const SettingsSeedPage(),
        ),
        GoRoute(
          name: SettingsRoutes.walletAddress,
          path: 'walletAddress',
          builder: (_, _) => const SettingsWalletAddressPage(),
        ),
        GoRoute(
          name: SettingsRoutes.userData,
          path: 'userData',
          builder: (_, _) => const SettingsUserDataPage(),
          routes: [
            GoRoute(
              name: SettingsRoutes.editName,
              path: 'editName',
              builder: (_, _) => const SettingsEditNamePage(),
            ),
            GoRoute(
              name: SettingsRoutes.editAddress,
              path: 'editAddress',
              builder: (_, _) => const SettingsEditAddressPage(),
            ),
            GoRoute(
              name: SettingsRoutes.editPhone,
              path: 'editPhoneNumber',
              builder: (_, _) => const SettingsEditPhoneNumberPage(),
            ),
          ],
        ),
      ],
    ),

    GoRoute(
      name: SupportRoutes.support,
      path: '/support',
      builder: (_, _) => const SupportPage(),
      routes: [
        GoRoute(
          name: SupportRoutes.emailCapture,
          path: 'email',
          builder: (_, state) => SupportEmailCapturePage(
            description: state.extra as String?,
          ),
        ),
        GoRoute(
          name: SupportRoutes.tickets,
          path: 'tickets',
          builder: (_, _) => const SupportTicketsPage(),
        ),
        GoRoute(
          name: SupportRoutes.createTicket,
          path: 'create',
          builder: (_, _) => const SupportCreateTicketPage(),
        ),
        GoRoute(
          name: SupportRoutes.chat,
          path: 'chat/:uid',
          builder: (_, state) => SupportChatPage(
            ticketUid: state.pathParameters['uid']!,
          ),
        ),
      ],
    ),

    GoRoute(
      name: AppRoutes.webView,
      path: '/webView',
      builder: (_, state) => WebViewPage(state.extra as WebViewRouteParams),
    ),
  ],
);
