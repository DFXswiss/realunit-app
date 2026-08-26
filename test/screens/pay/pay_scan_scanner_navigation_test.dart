// Gate for the QR scanner double-stack bug: a live camera delivers the same
// LNURL on every frame. Pushing the quote step and resetting the cubit in the
// same turn drops the Decoded guard, so frame 2 pushes a second PayQuotePage.
// This test fires two BarcodeCaptures against the real cubit and expects
// PayQuoteView exactly once; after pop, a third capture is accepted again.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_pay_service.dart';
import 'package:realunit_wallet/screens/pay/pay_quote_page.dart';
import 'package:realunit_wallet/screens/pay/pay_scan_page.dart';

import '../../helper/helper.dart';

class _MockPayService extends Mock implements RealUnitPayService {}

void main() {
  // LUD-01 LNURL from pay_scan_cubit_test.dart.
  const lnurl =
      'LNURL1DP68GURN8GHJ7CTSDYHXGENC9EEHW6TNWVHHVVF0D3H82UNVWQHHQMZLV93XXVFJXV5T0E5A';

  setUpAll(() {
    stubMobileScannerChannel();

    // PayQuotePage resolves RealUnitPayService from getIt and triggers load();
    // throw so the pushed route builds deterministically without a backend.
    final payService = _MockPayService();
    when(() => payService.getPaymentDetails(any())).thenThrow(
      const ApiException(code: 'TEST', message: 'no backend in widget test'),
    );
    GetIt.instance.registerSingleton<RealUnitPayService>(payService);
  });

  tearDownAll(() async => GetIt.instance.reset());

  testWidgets(
    'two identical captures push PayQuoteView once; re-arms after pop',
    (tester) async {
      await tester.pumpApp(const PayScanPage());

      final scanner = tester.widget<MobileScanner>(find.byType(MobileScanner));
      const capture = BarcodeCapture(barcodes: [Barcode(rawValue: lnurl)]);
      scanner.onDetect!(capture);
      scanner.onDetect!(capture); // second frame — must not push again
      await tester.pumpAndSettle();

      expect(find.byType(PayQuoteView), findsOne);

      // Quote may be in an error state from the mocked service; pop via the
      // navigator on that view rather than pageBack if a sheet blocks.
      Navigator.of(tester.element(find.byType(PayQuoteView))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(PayQuoteView), findsNothing);

      final scannerAfterPop = tester.widget<MobileScanner>(find.byType(MobileScanner));
      scannerAfterPop.onDetect!(capture);
      await tester.pumpAndSettle();
      expect(find.byType(PayQuoteView), findsOne);
    },
  );
}
