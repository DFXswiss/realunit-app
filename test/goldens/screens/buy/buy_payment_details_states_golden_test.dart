import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/buy/buy_payment_info.dart';
import 'package:realunit_wallet/screens/buy/buy_payment_details_page.dart';
import 'package:realunit_wallet/styles/currency.dart';

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

// A plain (non-SVG) payment request drives the `QrImageView` branch of the card
// (`payment_details_card.dart:128-134`). The QR encoding is a pure function of
// this fixed string, so the render is byte-stable (same determinism the
// `receive_page_default` golden relies on).
const _qrPayload = 'SPC\n0200\n1\n'
    'CH0000000000000000000\nRealUnit AG\nBahnhofstrasse 1\n8001 Zurich\nCH\n'
    '100.00\nCHF\nRU-2026-000123';

// A payment request that *contains* `<svg` drives the `SvgPicture.string` branch
// (`payment_details_card.dart:122-127`). Fixed markup with `mm` units — this
// also exercises `SvgParser.normalize` — renders deterministically.
const _qrSvg = '<svg xmlns="http://www.w3.org/2000/svg" '
    'width="46mm" height="46mm" viewBox="0 0 46 46">'
    '<rect width="46" height="46" fill="#ffffff"/>'
    '<rect x="4" y="4" width="10" height="10" fill="#000000"/>'
    '<rect x="6" y="6" width="6" height="6" fill="#ffffff"/>'
    '<rect x="8" y="8" width="2" height="2" fill="#000000"/>'
    '<rect x="32" y="4" width="10" height="10" fill="#000000"/>'
    '<rect x="34" y="6" width="6" height="6" fill="#ffffff"/>'
    '<rect x="36" y="8" width="2" height="2" fill="#000000"/>'
    '<rect x="4" y="32" width="10" height="10" fill="#000000"/>'
    '<rect x="6" y="34" width="6" height="6" fill="#ffffff"/>'
    '<rect x="8" y="36" width="2" height="2" fill="#000000"/>'
    '<rect x="20" y="20" width="6" height="6" fill="#000000"/>'
    '<rect x="28" y="28" width="4" height="4" fill="#000000"/>'
    '</svg>';

void main() {
  // `buy_payment_details_default` (no QR, purpose present) lives in
  // `buy_payment_details_golden_test.dart`. This file adds the QR-tab surfaces
  // and the empty-purpose row omission.
  group('$BuyPaymentDetailsPage', () {
    // With a payment request the TabSelector row appears
    // (`payment_details_card.dart:45-64`); the default tab is `text`, so the
    // Details table is what shows underneath.
    goldenTest(
      'QR available — Details tab active, TabSelector visible',
      fileName: 'buy_payment_details_qr_details_tab',
      constraints: phoneConstraints,
      builder: () => wrapForGolden(
        const BuyPaymentDetailsPage(
          params: BuyPaymentDetailsParams(
            buyPaymentInfo: _info,
            amount: '100',
            purposeOfPayment: 'RU-2026-000123',
            paymentRequest: _qrPayload,
          ),
        ),
      ),
    );

    // Tapping the QR-Code tab flips the ValueNotifier to `qrCode`
    // (`payment_details_card.dart:119-135`) — QrImageView variant.
    goldenTest(
      'QR-Code tab selected — QrImageView',
      fileName: 'buy_payment_details_qr_code_tab',
      constraints: phoneConstraints,
      pumpBeforeTest: (tester) async {
        await tester.pumpAndSettle();
        await tester.tap(find.text('QR-Code'));
        await tester.pumpAndSettle();
      },
      builder: () => wrapForGolden(
        const BuyPaymentDetailsPage(
          params: BuyPaymentDetailsParams(
            buyPaymentInfo: _info,
            amount: '100',
            purposeOfPayment: 'RU-2026-000123',
            paymentRequest: _qrPayload,
          ),
        ),
      ),
    );

    // Same tab, SVG-string variant (`payment_details_card.dart:122-127`). The
    // extra frames give flutter_svg's string loader time to decode.
    goldenTest(
      'QR-Code tab selected — SvgPicture.string',
      fileName: 'buy_payment_details_qr_code_tab_svg',
      constraints: phoneConstraints,
      pumpBeforeTest: (tester) async {
        await tester.pumpAndSettle();
        await tester.tap(find.text('QR-Code'));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
      },
      builder: () => wrapForGolden(
        const BuyPaymentDetailsPage(
          params: BuyPaymentDetailsParams(
            buyPaymentInfo: _info,
            amount: '100',
            purposeOfPayment: 'RU-2026-000123',
            paymentRequest: _qrSvg,
          ),
        ),
      ),
    );

    // Empty `purposeOfPayment` omits the purpose row
    // (`payment_details_card.dart:82`).
    goldenTest(
      'purpose row hidden — empty purposeOfPayment',
      fileName: 'buy_payment_details_no_purpose',
      constraints: phoneConstraints,
      builder: () => wrapForGolden(
        const BuyPaymentDetailsPage(
          params: BuyPaymentDetailsParams(
            buyPaymentInfo: _info,
            amount: '100',
            purposeOfPayment: '',
          ),
        ),
      ),
    );
  });
}
