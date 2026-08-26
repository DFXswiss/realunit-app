/// Catalog of production surfaces that construct [QrScannerView] and navigate
/// from a scan result. Adding a new scanner consumer without a catalog entry,
/// [pushThenRearm], and a real-cubit double-capture regression test is a
/// review-blocking gap.
///
/// Unlike the sticky-CTA catalog, the self-test in
/// `scanner_navigation_catalog_test.dart` also **discovers** every
/// `QrScannerView(` under `lib/` and fails if any consumer is missing here.
library;

/// One scanner surface under the push-then-rearm navigation contract.
class ScannerNavigationSurface {
  const ScannerNavigationSurface({
    required this.id,
    required this.description,
    required this.productionPath,
    required this.regressionTestPath,
  });

  final String id;
  final String description;

  /// Path under `lib/` of the production file that constructs [QrScannerView].
  final String productionPath;

  /// Path under `test/` of the real-cubit double-capture regression test.
  final String regressionTestPath;
}

/// Living catalog — extend when adding a new [QrScannerView] consumer that
/// navigates from a scan result.
const kScannerNavigationCatalog = <ScannerNavigationSurface>[
  ScannerNavigationSurface(
    id: 'send_recipient',
    description: 'Wallet-to-wallet send recipient scan',
    productionPath: 'lib/screens/send/send_recipient_page.dart',
    regressionTestPath: 'test/screens/send/send_recipient_scanner_navigation_test.dart',
  ),
  ScannerNavigationSurface(
    id: 'pay_scan',
    description: 'Open CryptoPay scan',
    productionPath: 'lib/screens/pay/pay_scan_page.dart',
    regressionTestPath: 'test/screens/pay/pay_scan_scanner_navigation_test.dart',
  ),
];
