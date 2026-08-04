import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/buy/buy_payment_info.dart';
import 'package:realunit_wallet/screens/buy/buy_payment_details_page.dart';
import 'package:realunit_wallet/screens/buy/widgets/payment_details_card.dart';
import 'package:realunit_wallet/setup/routing/routes/app_routes.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/styles/currency.dart';
import 'package:realunit_wallet/widgets/tab_selector.dart';

import '../../helper/helper.dart';

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

BuyPaymentDetailsParams _params({
  String purposeOfPayment = 'RU-2026-000123',
  String? paymentRequest,
}) =>
    BuyPaymentDetailsParams(
      buyPaymentInfo: _info,
      amount: '100',
      purposeOfPayment: purposeOfPayment,
      paymentRequest: paymentRequest,
    );

void main() {
  group('$BuyPaymentDetailsPage', () {
    testWidgets('renders title, instruction, purpose hint and the details card',
        (tester) async {
      await tester.pumpApp(BuyPaymentDetailsPage(params: _params()));

      expect(find.text(S.current.buyPaymentDetailsTitle), findsOneWidget);
      expect(find.text(S.current.buyPaymentInstructionEmail), findsOneWidget);
      expect(find.text(S.current.buyPaymentPurposeHint), findsOneWidget);
      expect(find.byType(PaymentDetailsCard), findsOneWidget);
    });

    testWidgets('renders the recurring savings-plan hint with autorenew icon',
        (tester) async {
      await tester.pumpApp(BuyPaymentDetailsPage(params: _params()));

      expect(find.text(S.current.buyRecurringPaymentHint), findsOneWidget);
      final icon = tester.widget<Icon>(find.byIcon(Icons.autorenew));
      expect(icon.color, RealUnitColors.realUnitBlue);
      expect(icon.size, 24);
    });

    testWidgets('renders the purpose of payment as the Verwendungszweck '
        'inside the details card', (tester) async {
      await tester.pumpApp(BuyPaymentDetailsPage(params: _params()));

      // The confirm remittance info appears as the Verwendungszweck value.
      expect(find.text(S.current.purposeOfPayment), findsOneWidget);
      expect(find.text('RU-2026-000123'), findsOneWidget);
    });

    testWidgets('backward compatible: with paymentRequest null the purpose '
        'renders inside the card and there is no QR tab', (tester) async {
      await tester.pumpApp(
        BuyPaymentDetailsPage(params: _params(paymentRequest: null)),
      );

      // Purpose of payment is rendered as the Verwendungszweck inside the card.
      expect(
        find.descendant(
          of: find.byType(PaymentDetailsCard),
          matching: find.text('RU-2026-000123'),
        ),
        findsOneWidget,
      );
      // No payment request → no tab selector / QR.
      expect(find.byType(TabSelector<PaymentInfoOptions>), findsNothing);
    });

    testWidgets('shows no standalone reference line above the card',
        (tester) async {
      await tester.pumpApp(BuyPaymentDetailsPage(params: _params()));

      // The purpose value only lives inside the card, never as a
      // "Ihre Referenz: ..." line above it.
      expect(find.textContaining('RU-2026-000123:'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(PaymentDetailsCard),
          matching: find.text('RU-2026-000123'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('renders the back-to-main button', (tester) async {
      await tester.pumpApp(BuyPaymentDetailsPage(params: _params()));

      expect(find.text(S.current.buyBackToMain), findsOneWidget);
    });

    testWidgets('back-to-main button navigates to dashboard', (tester) async {
      final router = GoRouter(
        initialLocation: '/buyPaymentDetails',
        routes: [
          GoRoute(
            name: AppRoutes.dashboard,
            path: '/dashboard',
            builder: (_, _) => const Scaffold(body: Text('DASHBOARD-AREA')),
          ),
          GoRoute(
            name: AppRoutes.buyPaymentDetails,
            path: '/buyPaymentDetails',
            builder: (_, _) => BuyPaymentDetailsPage(params: _params()),
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          locale: const Locale('de'),
          localizationsDelegates: [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: S.delegate.supportedLocales,
        ),
      );

      await tester.ensureVisible(find.text(S.current.buyBackToMain));
      await tester.tap(find.text(S.current.buyBackToMain));
      await tester.pumpAndSettle();

      expect(find.text('DASHBOARD-AREA'), findsOneWidget);
    });
  });
}
