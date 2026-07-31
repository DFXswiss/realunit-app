/// Catalog of interactive surfaces that **must** pass the responsive matrix
/// (device × text scale × real tap). Adding a new bottom sheet / sticky-CTA
/// flow without a matrix gate is a review-blocking gap.
///
/// This is a living list, not a proof of completeness: the self-test in
/// `responsive_surface_catalog_test.dart` verifies that every listed surface's
/// matrix test file exists, its production file exists, and that production
/// file actually references [ScrollableActionsLayout]. It cannot verify that
/// every sticky-CTA surface in the app has been listed here — that is a
/// review responsibility for every new sticky-CTA surface.
///
/// Line coverage % of the repo is a different metric — see docs/testing.md.
library;

/// One surface under the responsive layout contract.
class ResponsiveSurface {
  const ResponsiveSurface({
    required this.id,
    required this.description,
    required this.matrixTestPath,
    required this.productionPath,
  });

  final String id;
  final String description;

  /// Path under `test/` that runs [kFullResponsiveMatrix] (or a documented
  /// subset) with [expectFullyTappable] on primary CTAs.
  final String matrixTestPath;

  /// Path under `lib/` of the production widget that must use
  /// [ScrollableActionsLayout] (or equivalent Expanded + scroll + sticky
  /// actions).
  final String productionPath;
}

/// Living catalog — extend when adding sticky-CTA sheets/pages.
const kResponsiveSurfaceCatalog = <ResponsiveSurface>[
  ResponsiveSurface(
    id: 'bitbox_connect_sheet',
    description: 'BitBox pairing bottom sheet (all button-bearing states)',
    matrixTestPath:
        'test/screens/hardware_connect_bitbox/connect_bitbox_responsive_matrix_test.dart',
    productionPath: 'lib/screens/hardware_connect_bitbox/widgets/connect_content.dart',
  ),
  ResponsiveSurface(
    id: 'dashboard_page',
    description: 'Dashboard main page',
    matrixTestPath: 'test/screens/dashboard/dashboard_responsive_matrix_test.dart',
    productionPath: 'lib/screens/dashboard/dashboard_page.dart',
  ),
  ResponsiveSurface(
    id: 'create_wallet_view',
    description: 'Create wallet view',
    matrixTestPath: 'test/screens/create_wallet/create_wallet_responsive_matrix_test.dart',
    productionPath: 'lib/screens/create_wallet/create_wallet_view.dart',
  ),
  ResponsiveSurface(
    id: 'verify_pin_page',
    description: 'Verify PIN page',
    matrixTestPath: 'test/screens/pin/verify_pin_responsive_matrix_test.dart',
    productionPath: 'lib/screens/pin/verify_pin_page.dart',
  ),
  ResponsiveSurface(
    id: 'kyc_completed_page',
    description: 'KYC completed status page',
    matrixTestPath:
        'test/screens/kyc/subpages/kyc_status_pages_responsive_matrix_test.dart',
    productionPath: 'lib/screens/kyc/subpages/kyc_completed_page.dart',
  ),
  ResponsiveSurface(
    id: 'kyc_manual_review_page',
    description: 'KYC manual review status page',
    matrixTestPath:
        'test/screens/kyc/subpages/kyc_status_pages_responsive_matrix_test.dart',
    productionPath: 'lib/screens/kyc/subpages/kyc_manual_review_page.dart',
  ),
  ResponsiveSurface(
    id: 'kyc_pending_page',
    description: 'KYC pending status page',
    matrixTestPath:
        'test/screens/kyc/subpages/kyc_status_pages_responsive_matrix_test.dart',
    productionPath: 'lib/screens/kyc/subpages/kyc_pending_page.dart',
  ),
  ResponsiveSurface(
    id: 'kyc_account_merge_page',
    description: 'KYC account merge page',
    matrixTestPath: 'test/screens/kyc/kyc_merge_link_responsive_matrix_test.dart',
    productionPath: 'lib/screens/kyc/subpages/kyc_account_merge_page.dart',
  ),
  ResponsiveSurface(
    id: 'kyc_merge_processing_page',
    description: 'KYC merge processing page',
    matrixTestPath: 'test/screens/kyc/kyc_merge_link_responsive_matrix_test.dart',
    productionPath: 'lib/screens/kyc/subpages/kyc_merge_processing_page.dart',
  ),
  ResponsiveSurface(
    id: 'kyc_link_wallet_page',
    description: 'KYC link wallet page',
    matrixTestPath: 'test/screens/kyc/kyc_merge_link_responsive_matrix_test.dart',
    productionPath: 'lib/screens/kyc/steps/link_wallet/kyc_link_wallet_page.dart',
  ),
  ResponsiveSurface(
    id: 'kyc_financial_data_questions_page',
    description: 'KYC financial data questions page',
    matrixTestPath:
        'test/screens/kyc/steps/financial_data/kyc_financial_data_responsive_matrix_test.dart',
    productionPath:
        'lib/screens/kyc/steps/financial_data/subpages/kyc_financial_data_questions_page.dart',
  ),
  ResponsiveSurface(
    id: 'onboarding_completed_page',
    description: 'Onboarding completed page',
    matrixTestPath:
        'test/screens/onboarding/onboarding_completed_responsive_matrix_test.dart',
    productionPath: 'lib/screens/onboarding/onboarding_completed_page.dart',
  ),
  ResponsiveSurface(
    id: 'support_create_ticket_page',
    description: 'Support create ticket page',
    matrixTestPath:
        'test/screens/support/support_create_ticket_responsive_matrix_test.dart',
    productionPath: 'lib/screens/support/subpages/support_create_ticket_page.dart',
  ),
  ResponsiveSurface(
    id: 'settings_edit_address_page',
    description: 'Settings edit address form',
    matrixTestPath:
        'test/screens/settings_user_data/settings_user_data_responsive_matrix_test.dart',
    productionPath:
        'lib/screens/settings_user_data/subpages/edit_address/settings_edit_address_page.dart',
  ),
  ResponsiveSurface(
    id: 'settings_edit_name_page',
    description: 'Settings edit name form',
    matrixTestPath:
        'test/screens/settings_user_data/settings_user_data_responsive_matrix_test.dart',
    productionPath:
        'lib/screens/settings_user_data/subpages/edit_name/settings_edit_name_page.dart',
  ),
  ResponsiveSurface(
    id: 'settings_edit_phone_number_page',
    description: 'Settings edit phone number form',
    matrixTestPath:
        'test/screens/settings_user_data/settings_user_data_responsive_matrix_test.dart',
    productionPath:
        'lib/screens/settings_user_data/subpages/edit_phone_number/settings_edit_phone_number_page.dart',
  ),
  ResponsiveSurface(
    id: 'settings_edit_pending_page',
    description: 'Settings edit pending status page',
    matrixTestPath:
        'test/screens/settings_user_data/settings_user_data_responsive_matrix_test.dart',
    productionPath:
        'lib/screens/settings_user_data/subpages/others/settings_edit_pending_page.dart',
  ),
  ResponsiveSurface(
    id: 'settings_edit_failure_page',
    description: 'Settings edit failure status page',
    matrixTestPath:
        'test/screens/settings_user_data/settings_user_data_responsive_matrix_test.dart',
    productionPath:
        'lib/screens/settings_user_data/subpages/others/settings_edit_failure_page.dart',
  ),
  ResponsiveSurface(
    id: 'verify_seed_page',
    description: 'Verify seed phrase page (confirm CTA)',
    matrixTestPath: 'test/screens/verify_seed/verify_seed_responsive_matrix_test.dart',
    productionPath: 'lib/screens/verify_seed/verify_seed_page.dart',
  ),
  ResponsiveSurface(
    id: 'restore_wallet_view',
    description: 'Restore wallet from seed phrase view (next CTA)',
    matrixTestPath: 'test/screens/restore_wallet/restore_wallet_responsive_matrix_test.dart',
    productionPath: 'lib/screens/restore_wallet/restore_wallet_view.dart',
  ),
  ResponsiveSurface(
    id: 'buy_page',
    description: 'Buy page (primary CTA)',
    matrixTestPath: 'test/screens/buy/buy_responsive_matrix_test.dart',
    productionPath: 'lib/screens/buy/buy_page.dart',
  ),
  ResponsiveSurface(
    id: 'pay_quote_page',
    description: 'Pay quote page (confirm CTA)',
    matrixTestPath: 'test/screens/pay/pay_quote_responsive_matrix_test.dart',
    productionPath: 'lib/screens/pay/pay_quote_page.dart',
  ),
  ResponsiveSurface(
    id: 'sell_page',
    description: 'Sell page (primary CTA)',
    matrixTestPath: 'test/screens/sell/sell_responsive_matrix_test.dart',
    productionPath: 'lib/screens/sell/sell_page.dart',
  ),
  ResponsiveSurface(
    id: 'send_amount_page',
    description: 'Send amount page (next CTA)',
    matrixTestPath: 'test/screens/send/send_amount_responsive_matrix_test.dart',
    productionPath: 'lib/screens/send/send_amount_page.dart',
  ),
  ResponsiveSurface(
    id: 'send_confirm_page',
    description: 'Send confirmation page (confirm CTA)',
    matrixTestPath: 'test/screens/send/send_confirm_responsive_matrix_test.dart',
    productionPath: 'lib/screens/send/send_confirm_page.dart',
  ),
  ResponsiveSurface(
    id: 'send_process_result_sheet',
    description: 'Send process terminal result sheet (shrinkWrap mode)',
    matrixTestPath:
        'test/screens/send/send_process_result_sheet_responsive_matrix_test.dart',
    productionPath: 'lib/screens/send/send_process_page.dart',
  ),
  ResponsiveSurface(
    id: 'send_recipient_page',
    description: 'Send recipient manual-entry block (next CTA)',
    matrixTestPath: 'test/screens/send/send_recipient_responsive_matrix_test.dart',
    productionPath: 'lib/screens/send/send_recipient_page.dart',
  ),
  ResponsiveSurface(
    id: 'setup_pin_page',
    description: 'Setup PIN page (sticky numeric keypad as actions)',
    matrixTestPath: 'test/screens/pin/setup_pin_responsive_matrix_test.dart',
    productionPath: 'lib/screens/pin/setup_pin_page.dart',
  ),
  ResponsiveSurface(
    id: 'kyc_failure_page',
    description: 'KYC failure status page (no CTA — gates overflow + message reachability only)',
    matrixTestPath: 'test/screens/kyc/kyc_static_pages_responsive_matrix_test.dart',
    productionPath: 'lib/screens/kyc/subpages/kyc_failure_page.dart',
  ),
  ResponsiveSurface(
    id: 'kyc_signature_unsupported_page',
    description: 'KYC signature-unsupported status page (no CTA — gates overflow + message reachability only)',
    matrixTestPath: 'test/screens/kyc/kyc_static_pages_responsive_matrix_test.dart',
    productionPath: 'lib/screens/kyc/steps/signature_unsupported/kyc_signature_unsupported_page.dart',
  ),
  ResponsiveSurface(
    id: 'sell_confirm_sheet',
    description: 'Sell confirmation bottom sheet (shrinkWrap mode)',
    matrixTestPath: 'test/screens/sell/sell_sheets_responsive_matrix_test.dart',
    productionPath: 'lib/screens/sell/widgets/sell_confirm_sheet.dart',
  ),
  ResponsiveSurface(
    id: 'sell_executed_sheet',
    description: 'Sell executed/receipt bottom sheet (shrinkWrap mode)',
    matrixTestPath: 'test/screens/sell/sell_sheets_responsive_matrix_test.dart',
    productionPath: 'lib/screens/sell/widgets/sell_executed_sheet.dart',
  ),
  ResponsiveSurface(
    id: 'forgot_pin_bottom_sheet',
    description: 'Forgot-PIN bottom sheet (shrinkWrap mode)',
    matrixTestPath: 'test/screens/pin/pin_sheets_responsive_matrix_test.dart',
    productionPath: 'lib/screens/pin/widgets/forgot_pin_bottom_sheet.dart',
  ),
  ResponsiveSurface(
    id: 'enable_biometric_bottom_sheet',
    description: 'Enable-biometric bottom sheet (shrinkWrap mode)',
    matrixTestPath: 'test/screens/pin/pin_sheets_responsive_matrix_test.dart',
    productionPath: 'lib/screens/pin/widgets/enable_biometric_bottom_sheet.dart',
  ),
  // Migration covers 34 surfaces total (bitbox_connect_sheet + 33 above). No
  // further known candidates remain from the prior sweep. welcome_page was
  // reviewed and found safe (scrolls end-to-end, no separate sticky CTA) — not
  // a migration candidate. Not exhaustive — review responsibility for every
  // new sticky-CTA surface.
];
