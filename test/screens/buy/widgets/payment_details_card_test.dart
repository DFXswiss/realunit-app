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

// The card uses IconButton (needs a Material ancestor) and renders a tall list of
// rows — host it in a scrollable Scaffold so it lays out without overflow.
Widget _host({
  String purposeOfPayment = '',
  String? paymentRequest,
  BuyPaymentInfo buyPaymentInfo = _info,
}) => Scaffold(
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

    testWidgets('renders the purpose of payment when purposeOfPayment is set', (tester) async {
      await tester.pumpApp(_host(purposeOfPayment: 'REF-XYZ'));

      expect(find.text(S.current.purposeOfPayment), findsOneWidget);
      expect(find.text('REF-XYZ'), findsOneWidget);
    });

    testWidgets('omits the purpose row when purposeOfPayment is empty', (tester) async {
      await tester.pumpApp(_host());

      expect(find.text(S.current.purposeOfPayment), findsNothing);
    });

    testWidgets('renders copy icons for the rows', (tester) async {
      await tester.pumpApp(_host());

      expect(find.byIcon(Icons.copy_outlined), findsWidgets);
    });

    testWidgets('tapping a copy icon writes the value to the clipboard', (tester) async {
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
          _rawIbanInfo.iban.replaceAll(' ', ''),
          reason:
              'The clipboard must receive the raw, ungrouped IBAN — a grouped IBAN with '
              'spaces can fail validation in some banking transfer forms.',
        );
      },
    );

    testWidgets('strips spaces when the IBAN arrives already grouped', (tester) async {
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

      final ibanRow = find.ancestor(
        of: find.text(S.current.iban),
        matching: find.byType(Row),
      );
      await tester.tap(
        find.descendant(of: ibanRow, matching: find.byIcon(Icons.copy_outlined)),
      );
      await tester.pump();

      expect(copied, _info.iban.replaceAll(' ', ''));
      expect(copied!.contains(' '), isFalse);
    });

    testWidgets('shows no tab selector when there is no payment request', (tester) async {
      await tester.pumpApp(_host());

      expect(find.byType(TabSelector<PaymentInfoOptions>), findsNothing);
    });

    testWidgets('shows the tab selector and a QR code when a payment request exists', (
      tester,
    ) async {
      await tester.pumpApp(
        _host(paymentRequest: 'SPC\n0200\nsome-payload'),
      );

      expect(find.byType(TabSelector<PaymentInfoOptions>), findsOneWidget);

      // Switch to the QR tab and verify the QR image renders.
      await tester.tap(find.text(S.current.qrCode));
      await tester.pumpAndSettle();

      expect(find.byType(QrImageView), findsOneWidget);
    });

    testWidgets(
      'copy control meets the 44×44 minimum tap target so it is hittable on an iPhone (2026-08-13)',
      (tester) async {
        await tester.pumpApp(_host(purposeOfPayment: 'DA6E-2904-5F41'));

        final copyButton = find.widgetWithIcon(IconButton, Icons.copy_outlined).first;
        expect(copyButton, findsOneWidget);

        final size = tester.getSize(copyButton);
        expect(
          size.width,
          greaterThanOrEqualTo(44),
          reason:
              'Copy tap target width ${size.width} < 44 — too small for an iPhone finger '
              '(incident 2026-08-13: payment details could not be copied into the bank app).',
        );
        expect(
          size.height,
          greaterThanOrEqualTo(44),
          reason:
              'Copy tap target height ${size.height} < 44 — too small for an iPhone finger '
              '(incident 2026-08-13: payment details could not be copied into the bank app).',
        );

        await expectFullyTappable(
          tester,
          copyButton,
          within: find.byType(PaymentDetailsCard),
        );
      },
    );

    testWidgets(
      'tapping copy on the purpose-of-payment row writes the remittance reference',
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

        await tester.pumpApp(_host(purposeOfPayment: 'DA6E-2904-5F41'));

        final purposeRow = find.ancestor(
          of: find.text(S.current.purposeOfPayment),
          matching: find.byType(Row),
        );
        await tester.tap(
          find.descendant(of: purposeRow, matching: find.byIcon(Icons.copy_outlined)),
        );
        await tester.pump();

        expect(copied, 'DA6E-2904-5F41');
      },
    );
  });
}
