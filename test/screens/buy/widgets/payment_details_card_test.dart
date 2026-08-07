import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/buy/buy_payment_info.dart';
import 'package:realunit_wallet/screens/buy/widgets/payment_details_card.dart';
import 'package:realunit_wallet/styles/currency.dart';
import 'package:realunit_wallet/widgets/tab_selector.dart';

import '../../../helper/helper.dart';

const _info = BuyPaymentInfo(
  amount: 300,
  id: 1,
  iban: 'CH00 0000 0000 0000 0000 0',
  bic: 'BICCBIC',
  name: 'RealUnit AG',
  street: 'Bahnhofstrasse',
  number: '1',
  zip: '8001',
  city: 'Zurich',
  country: 'Switzerland',
  currency: Currency.chf,
);

const _rawIbanInfo = BuyPaymentInfo(
  amount: 300,
  id: 1,
  iban: 'CH9300762011623852957',
  bic: 'BICCBIC',
  name: 'RealUnit AG',
  street: 'Bahnhofstrasse',
  number: '1',
  zip: '8001',
  city: 'Zurich',
  country: 'Switzerland',
  currency: Currency.chf,
);

// The card uses InkWell (needs a Material ancestor) and renders a tall list of
// rows — host it in a scrollable Scaffold so it lays out without overflow.
Widget _host({
  String purposeOfPayment = '',
  String? paymentRequest,
  BuyPaymentInfo buyPaymentInfo = _info,
}) =>
    Scaffold(
      body: SingleChildScrollView(
        child: PaymentDetailsCard(
          buyPaymentInfo: buyPaymentInfo,
          amount: '100',
          purposeOfPayment: purposeOfPayment,
          paymentRequest: paymentRequest,
        ),
      ),
    );

void main() {
  group('$PaymentDetailsCard', () {
    testWidgets('renders the bank-transfer fields and the amount', (tester) async {
      await tester.pumpApp(_host());

      expect(find.text('CH00 0000 0000 0000 0000 0'), findsOneWidget);
      expect(find.text('BICCBIC'), findsOneWidget);
      expect(find.text('RealUnit AG'), findsOneWidget);
      expect(find.text('100'), findsOneWidget);
      expect(find.text('${S.current.amountIn} ${Currency.chf.code}'), findsOneWidget);
    });

    testWidgets('renders the purpose of payment when purposeOfPayment is set',
        (tester) async {
      await tester.pumpApp(_host(purposeOfPayment: 'REF-XYZ'));

      expect(find.text(S.current.purposeOfPayment), findsOneWidget);
      expect(find.text('REF-XYZ'), findsOneWidget);
    });

    testWidgets('omits the purpose row when purposeOfPayment is empty',
        (tester) async {
      await tester.pumpApp(_host());

      expect(find.text(S.current.purposeOfPayment), findsNothing);
    });

    testWidgets('renders copy icons for the rows', (tester) async {
      await tester.pumpApp(_host());

      expect(find.byIcon(Icons.copy_outlined), findsWidgets);
    });

    testWidgets('tapping a copy icon writes the value to the clipboard',
        (tester) async {
      String? copied;
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      });

      await tester.pumpApp(_host());

      await tester.tap(find.byIcon(Icons.copy_outlined).first);
      await tester.pump();

      expect(copied, isNotNull);
    });

    testWidgets(
      'copies the raw (ungrouped) IBAN to the clipboard even though the on-screen text is '
      'grouped',
      (tester) async {
        String? copied;
        final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        });
        addTearDown(() {
          messenger.setMockMethodCallHandler(SystemChannels.platform, null);
        });

        await tester.pumpApp(_host(buyPaymentInfo: _rawIbanInfo));

        // Displayed value is grouped...
        expect(find.text('CH93 0076 2011 6238 5295 7'), findsOneWidget);
        expect(find.text(_rawIbanInfo.iban), findsNothing);

        // ...but the copy button for that same row must copy the RAW value.
        final ibanRow = find.ancestor(
          of: find.text(S.current.iban),
          matching: find.byType(Row),
        );
        await tester.tap(
          find.descendant(of: ibanRow, matching: find.byIcon(Icons.copy_outlined)),
        );
        await tester.pump();

        expect(
          copied,
          _rawIbanInfo.iban,
          reason: 'The clipboard must receive the raw, ungrouped IBAN — a grouped IBAN with '
              'spaces can fail validation in some banking transfer forms.',
        );
      },
    );

    testWidgets('shows no tab selector when there is no payment request',
        (tester) async {
      await tester.pumpApp(_host());

      expect(find.byType(TabSelector<PaymentInfoOptions>), findsNothing);
    });

    testWidgets('shows the tab selector and a QR code when a payment request exists',
        (tester) async {
      await tester.pumpApp(
        _host(paymentRequest: 'SPC\n0200\nsome-payload'),
      );

      expect(find.byType(TabSelector<PaymentInfoOptions>), findsOneWidget);

      // Switch to the QR tab and verify the QR image renders.
      await tester.tap(find.text(S.current.qrCode));
      await tester.pumpAndSettle();

      expect(find.byType(QrImageView), findsOneWidget);
    });
  });
}
