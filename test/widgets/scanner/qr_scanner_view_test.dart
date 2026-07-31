import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/widgets/scanner/qr_scanner_view.dart';

import '../../helper/helper.dart';

void main() {
  setUpAll(stubMobileScannerChannel);

  group('$QrScannerView default error placeholder', () {
    testWidgets(
      'renders the compact icon placeholder without overflow at high textScale in a tight box',
      (tester) async {
        await tester.pumpApp(
          MediaQuery(
            data: const MediaQueryData(size: Size(400, 800))
                .copyWith(textScaler: const TextScaler.linear(3.0)),
            child: Center(
              child: SizedBox(
                width: 60,
                height: 60,
                child: QrScannerView(onDetect: (_) {}),
              ),
            ),
          ),
        );

        // Let the stubbed permission handshake resolve into the
        // permission-denied error state so the default error builder paints.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(tester.takeException(), isNull);
        expect(find.byIcon(Icons.error_outline), findsOneWidget);
        final icon = tester.widget<Icon>(find.byIcon(Icons.error_outline));
        expect(icon.size, 48);
      },
    );
  });
}
