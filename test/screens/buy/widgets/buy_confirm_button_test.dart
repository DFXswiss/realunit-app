import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/buy/buy_payment_info.dart';
import 'package:realunit_wallet/screens/buy/buy_payment_details_page.dart';
import 'package:realunit_wallet/screens/buy/cubits/buy_confirm/buy_confirm_cubit.dart';
import 'package:realunit_wallet/screens/buy/widgets/buy_confirm_button.dart';
import 'package:realunit_wallet/screens/buy/widgets/payment_details_card.dart';
import 'package:realunit_wallet/setup/routing/routes/app_routes.dart';
import 'package:realunit_wallet/styles/currency.dart';
import 'package:realunit_wallet/widgets/tab_selector.dart';

class _MockBuyConfirmCubit extends MockCubit<BuyConfirmState> implements BuyConfirmCubit {}

const _info = BuyPaymentInfo(
  amount: 300,
  id: 42,
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

// The quote echoes the charged amount; a fractional echo must render rounded.
const _quotedFractional = BuyPaymentInfo(
  amount: 300.75,
  id: 42,
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

void main() {
  late _MockBuyConfirmCubit cubit;

  setUp(() {
    cubit = _MockBuyConfirmCubit();
    when(() => cubit.state).thenReturn(const BuyConfirmInitial());
    when(() => cubit.confirmPayment(any())).thenAnswer((_) async {});
    when(() => cubit.deactivateQuote(any())).thenAnswer((_) async {});
  });

  Widget host({GoRouter? router}) {
    final view = BlocProvider<BuyConfirmCubit>.value(
      value: cubit,
      child: const BuyConfirmButtonView(buyPaymentInfo: _info),
    );
    if (router != null) {
      return MaterialApp.router(
        routerConfig: router,
        locale: const Locale('de'),
        localizationsDelegates: [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
      );
    }
    return MaterialApp(
      locale: const Locale('de'),
      localizationsDelegates: [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: S.delegate.supportedLocales,
      home: Scaffold(body: view),
    );
  }

  group('$BuyConfirmButtonView', () {
    testWidgets('renders the binding-buy label', (tester) async {
      await tester.pumpWidget(host());

      expect(find.text(S.current.buyPaymentConfirm), findsOneWidget);
    });

    testWidgets('renders the secondary deactivate label', (tester) async {
      await tester.pumpWidget(host());

      expect(find.text(S.current.pendingTransactionDeactivate), findsOneWidget);
    });

    testWidgets('tapping confirms the payment for the quote id', (tester) async {
      await tester.pumpWidget(host());

      await tester.tap(find.text(S.current.buyPaymentConfirm));
      await tester.pump();

      verify(() => cubit.confirmPayment(42)).called(1);
    });

    testWidgets('shows a snackbar when deactivate fails', (tester) async {
      whenListen(
        cubit,
        Stream.fromIterable([
          const BuyDeactivateFailure(),
        ]),
        initialState: const BuyConfirmInitial(),
      );

      await tester.pumpWidget(host());
      await tester.pump();

      expect(find.text(S.current.pendingTransactionDeactivateFailed), findsOneWidget);
    });

    testWidgets('deactivate dialog cancel does not call deactivateQuote', (tester) async {
      await tester.pumpWidget(host());

      await tester.tap(find.text(S.current.pendingTransactionDeactivate));
      await tester.pump();

      expect(find.text(S.current.pendingTransactionDeactivateConfirm), findsOneWidget);

      await tester.tap(find.text(S.current.cancel));
      await tester.pump();

      verifyNever(() => cubit.deactivateQuote(any()));
    });

    testWidgets('deactivate dialog confirm calls deactivateQuote once', (tester) async {
      await tester.pumpWidget(host());

      await tester.tap(find.text(S.current.pendingTransactionDeactivate));
      await tester.pump();

      expect(find.text(S.current.pendingTransactionDeactivateConfirm), findsOneWidget);

      await tester.tap(
        find.widgetWithText(TextButton, S.current.pendingTransactionDeactivate),
      );
      await tester.pump();

      verify(() => cubit.deactivateQuote(42)).called(1);
    });

    testWidgets('BuyDeactivateSuccess pops the pushed confirm route', (tester) async {
      // Production uses GoRouter context.pop(). Start on /parent, then push
      // /parent/child so there is a stack entry. Emit success only after
      // the confirm view is mounted.
      final states = StreamController<BuyConfirmState>();
      addTearDown(states.close);
      whenListen(
        cubit,
        states.stream,
        initialState: const BuyConfirmInitial(),
      );

      final router = GoRouter(
        initialLocation: '/parent',
        routes: [
          GoRoute(
            path: '/parent',
            builder: (_, _) => const Scaffold(body: Text('parent-marker')),
            routes: [
              GoRoute(
                path: 'child',
                builder: (_, _) => Scaffold(
                  body: BlocProvider<BuyConfirmCubit>.value(
                    value: cubit,
                    child: const BuyConfirmButtonView(buyPaymentInfo: _info),
                  ),
                ),
              ),
            ],
          ),
        ],
      );

      await tester.pumpWidget(host(router: router));
      await tester.pump();
      expect(find.text('parent-marker'), findsOneWidget);

      router.push('/parent/child');
      await tester.pump();
      await tester.pump();
      expect(find.byType(BuyConfirmButtonView), findsOneWidget);

      states.add(const BuyDeactivateSuccess());
      await tester.pump();

      expect(find.text('parent-marker'), findsOneWidget);
      expect(find.byType(BuyConfirmButtonView), findsNothing);
    });

    testWidgets('shows a loading indicator while confirming', (tester) async {
      when(() => cubit.state).thenReturn(const BuyConfirmLoading());

      await tester.pumpWidget(host());

      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    });

    testWidgets('deactivate label is inert while BuyConfirmLoading', (tester) async {
      when(() => cubit.state).thenReturn(const BuyConfirmLoading());

      await tester.pumpWidget(host());
      await tester.tap(find.text(S.current.pendingTransactionDeactivate));
      await tester.pump();

      expect(find.text(S.current.pendingTransactionDeactivateConfirm), findsNothing);
      verifyNever(() => cubit.deactivateQuote(any()));
    });

    testWidgets('shows a loading indicator while deactivating', (tester) async {
      when(() => cubit.state).thenReturn(const BuyDeactivateLoading());

      await tester.pumpWidget(host());

      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    });

    testWidgets('confirm tap is inert during BuyDeactivateLoading', (tester) async {
      when(() => cubit.state).thenReturn(const BuyDeactivateLoading());

      await tester.pumpWidget(host());
      await tester.tap(find.text(S.current.buyPaymentConfirm));
      await tester.pump();

      verifyNever(() => cubit.confirmPayment(any()));
    });

    testWidgets('shows a snackbar with the generic error on failure', (tester) async {
      whenListen(
        cubit,
        Stream.fromIterable([
          const BuyConfirmFailure(BuyConfirmError.unknown),
        ]),
        initialState: const BuyConfirmInitial(),
      );

      await tester.pumpWidget(host());
      await tester.pump();

      expect(find.text(S.current.buyPaymentConfirmFailed), findsOneWidget);
    });

    testWidgets('shows the aktionariat-specific error on a 503 failure', (tester) async {
      whenListen(
        cubit,
        Stream.fromIterable([
          const BuyConfirmFailure(BuyConfirmError.aktionariat),
        ]),
        initialState: const BuyConfirmInitial(),
      );

      await tester.pumpWidget(host());
      await tester.pump();

      expect(find.text(S.current.buyPaymentConfirmFailedAktionariat), findsOneWidget);
    });

    testWidgets('shows the minimum-purchase error on an amount-too-low failure', (tester) async {
      whenListen(
        cubit,
        Stream.fromIterable([
          const BuyConfirmFailure(BuyConfirmError.amountTooLow),
        ]),
        initialState: const BuyConfirmInitial(),
      );

      await tester.pumpWidget(host());
      await tester.pump();

      expect(find.text(S.current.buyPaymentConfirmFailedAmountTooLow), findsOneWidget);
    });

    testWidgets('shows the aktionariat-specific error on a primary-email-required failure', (
      tester,
    ) async {
      whenListen(
        cubit,
        Stream.fromIterable([
          const BuyConfirmFailure(BuyConfirmError.primaryEmailRequired),
        ]),
        initialState: const BuyConfirmInitial(),
      );

      await tester.pumpWidget(host());
      await tester.pump();

      expect(find.text(S.current.buyPaymentConfirmFailedAktionariat), findsOneWidget);
    });

    GoRouter detailsRouter({BuyPaymentInfo info = _info}) => GoRouter(
      initialLocation: '/buy',
      routes: [
        GoRoute(
          name: AppRoutes.buy,
          path: '/buy',
          builder: (_, _) => Scaffold(
            body: BlocProvider<BuyConfirmCubit>.value(
              value: cubit,
              child: BuyConfirmButtonView(
                buyPaymentInfo: info,
              ),
            ),
          ),
        ),
        GoRoute(
          name: AppRoutes.buyPaymentDetails,
          path: '/buyPaymentDetails',
          builder: (_, state) => BuyPaymentDetailsPage(
            params: state.extra as BuyPaymentDetailsParams,
          ),
        ),
      ],
    );

    testWidgets('backward compatible: a reference-only success navigates to the '
        'details page, shows the reference as Verwendungszweck and no QR tab', (tester) async {
      whenListen(
        cubit,
        Stream.fromIterable([
          const BuyConfirmSuccess(
            reference: 'RU-REF-1',
            remittanceInfo: null,
            paymentRequest: null,
          ),
        ]),
        initialState: const BuyConfirmInitial(),
      );

      await tester.pumpWidget(host(router: detailsRouter()));
      await tester.pumpAndSettle();

      expect(find.text(S.current.buyPaymentDetailsTitle), findsOneWidget);
      expect(find.text(S.current.buyPaymentInstructionEmail), findsOneWidget);
      // Falls back to `reference` as the Verwendungszweck.
      expect(find.text('RU-REF-1'), findsOneWidget);
      // No QR encoding → no tab selector.
      expect(find.byType(TabSelector<PaymentInfoOptions>), findsNothing);
    });

    testWidgets('shows the charged amount echoed by the quote on the details '
        'page, rounded (300.75 → 301) — never derived from keystrokes', (tester) async {
      whenListen(
        cubit,
        Stream.fromIterable([
          const BuyConfirmSuccess(
            reference: 'RU-REF-3',
            remittanceInfo: null,
            paymentRequest: null,
          ),
        ]),
        initialState: const BuyConfirmInitial(),
      );

      await tester.pumpWidget(host(router: detailsRouter(info: _quotedFractional)));
      await tester.pumpAndSettle();

      // The details amount is the quote's own echoed charge, so it can never
      // disagree with the SEPA transfer / QR the backend built for the quote.
      expect(find.text('301'), findsOneWidget);
      expect(find.text('300.75'), findsNothing);
    });

    testWidgets('forward path: remittanceInfo + paymentRequest drive the '
        'Verwendungszweck and surface the QR tab', (tester) async {
      whenListen(
        cubit,
        Stream.fromIterable([
          const BuyConfirmSuccess(
            reference: 'RU-REF-2',
            remittanceInfo: 'RU-REMIT-2',
            paymentRequest: 'SPC\n0200\nsome-payload',
          ),
        ]),
        initialState: const BuyConfirmInitial(),
      );

      await tester.pumpWidget(host(router: detailsRouter()));
      await tester.pumpAndSettle();

      // The API-designated remittance info wins over the reference fallback.
      expect(find.text('RU-REMIT-2'), findsOneWidget);
      expect(find.text('RU-REF-2'), findsNothing);
      // The payment request encoding surfaces the QR tab.
      expect(find.byType(TabSelector<PaymentInfoOptions>), findsOneWidget);
    });
  });
}
