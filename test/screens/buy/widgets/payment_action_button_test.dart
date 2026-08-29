import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/payment_info_error.dart';
import 'package:realunit_wallet/screens/buy/cubits/buy_converter/buy_converter_cubit.dart';
import 'package:realunit_wallet/screens/buy/cubits/buy_payment_info/buy_payment_info_cubit.dart';
import 'package:realunit_wallet/screens/buy/widgets/buy_confirm_button.dart';
import 'package:realunit_wallet/screens/buy/widgets/payment_action_button.dart';
import 'package:realunit_wallet/setup/routing/routes/app_routes.dart';
import 'package:realunit_wallet/setup/routing/routes/support_routes.dart';
import 'package:realunit_wallet/styles/currency.dart';

class _MockBuyConverterCubit extends MockCubit<BuyConverterState> implements BuyConverterCubit {}

class _MockBuyPaymentInfoCubit extends MockCubit<BuyPaymentInfoState>
    implements BuyPaymentInfoCubit {}

void main() {
  late BuyConverterCubit converterCubit;
  late BuyPaymentInfoCubit paymentInfoCubit;
  late List<String> pushedRoutes;
  // Result the modelled email-capture page pops with; the buy gate
  // re-fetches the quote after the capture flow returns regardless of the
  // value (mirrors the registration / KYC gates), so the re-fetch is
  // asserted on both paths.
  bool? emailCaptureResult;
  String? kycExtra;

  setUpAll(() {
    registerFallbackValue(Currency.chf);
  });

  setUp(() {
    converterCubit = _MockBuyConverterCubit();
    paymentInfoCubit = _MockBuyPaymentInfoCubit();
    pushedRoutes = <String>[];
    emailCaptureResult = true;
    kycExtra = null;

    // fiatText models the typed amount; with no live payable the re-fetch
    // falls back to it (quoteAmountText), so '250' is what the gates send.
    when(
      () => converterCubit.state,
    ).thenReturn(const BuyConverterState(currency: Currency.eur, fiatText: '250'));
    when(
      () => paymentInfoCubit.getPaymentInfo(
        amount: any(named: 'amount'),
        currency: any(named: 'currency'),
      ),
    ).thenAnswer((_) async {});
  });

  GoRouter buildRouter() {
    return GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => MultiBlocProvider(
            providers: [
              BlocProvider<BuyPaymentInfoCubit>.value(value: paymentInfoCubit),
              BlocProvider<BuyConverterCubit>.value(value: converterCubit),
            ],
            child: const Scaffold(
              body: PaymentActionButton(),
            ),
          ),
        ),
        GoRoute(
          name: SupportRoutes.emailCapture,
          path: '/support/email',
          builder: (_, _) {
            pushedRoutes.add(SupportRoutes.emailCapture);
            return _EmailCaptureStub(
              onReady: (popContext) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (popContext.mounted) popContext.pop(emailCaptureResult);
                });
              },
            );
          },
        ),
        GoRoute(
          name: AppRoutes.kyc,
          path: '/kyc',
          builder: (_, state) {
            pushedRoutes.add(AppRoutes.kyc);
            kycExtra = state.extra as String?;
            return _EmailCaptureStub(
              onReady: (popContext) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (popContext.mounted) popContext.pop();
                });
              },
            );
          },
        ),
      ],
    );
  }

  Future<void> pumpButton(WidgetTester tester) async {
    final router = buildRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
      ),
    );
    await tester.pumpAndSettle();
  }

  group('$PaymentActionButton primaryEmailRequired gate', () {
    testWidgets(
      'renders the Weiter CTA, not the binding-buy button',
      (tester) async {
        when(() => paymentInfoCubit.state).thenReturn(
          const BuyPaymentInfoFailure(PaymentInfoError.primaryEmailRequired),
        );

        await pumpButton(tester);

        expect(find.text(S.current.next), findsOne);
        // Pre-tap gate must NOT surface the confirm affordance.
        expect(find.byType(BuyConfirmButton), findsNothing);
        expect(find.text(S.current.buyPaymentConfirm), findsNothing);
      },
    );

    testWidgets(
      'tap pushes email capture (never confirm) and re-fetches the quote',
      (tester) async {
        when(() => paymentInfoCubit.state).thenReturn(
          const BuyPaymentInfoFailure(PaymentInfoError.primaryEmailRequired),
        );
        when(() => converterCubit.state).thenReturn(
          const BuyConverterState(
            currency: Currency.eur,
            fiatText: '250',
            payableText: '249.50',
          ),
        );

        await pumpButton(tester);

        await tester.tap(find.text(S.current.next));
        await tester.pumpAndSettle();

        // Routed to email capture, not to the binding-buy / details flow.
        expect(pushedRoutes, [SupportRoutes.emailCapture]);
        // After the capture flow returns, the quote is re-fetched with the
        // live payable (not the typed fiatText) so a now-valid quote surfaces.
        verify(
          () => paymentInfoCubit.getPaymentInfo(
            amount: '249.50',
            currency: Currency.eur,
          ),
        ).called(1);
      },
    );
  });

  group('$PaymentActionButton primaryEmailNotConfirmed gate', () {
    testWidgets(
      'renders the Weiter CTA, not the binding-buy button',
      (tester) async {
        when(() => paymentInfoCubit.state).thenReturn(
          const BuyPaymentInfoFailure(PaymentInfoError.primaryEmailNotConfirmed),
        );

        await pumpButton(tester);

        expect(find.text(S.current.next), findsOne);
        // Pre-tap gate must NOT surface the confirm affordance.
        expect(find.byType(BuyConfirmButton), findsNothing);
        expect(find.text(S.current.buyPaymentConfirm), findsNothing);
      },
    );

    testWidgets(
      'tap pushes kyc (never email capture) and re-fetches the quote',
      (tester) async {
        when(() => paymentInfoCubit.state).thenReturn(
          const BuyPaymentInfoFailure(
            PaymentInfoError.primaryEmailNotConfirmed,
            context: 'RealunitBuy',
          ),
        );
        when(() => converterCubit.state).thenReturn(
          const BuyConverterState(
            currency: Currency.eur,
            fiatText: '250',
            payableText: '249.50',
          ),
        );

        await pumpButton(tester);

        await tester.tap(find.text(S.current.next));
        await tester.pumpAndSettle();

        // Routed to KYC confirm-email, not to email capture.
        expect(pushedRoutes, [AppRoutes.kyc]);
        expect(kycExtra, 'RealunitBuy');
        // After the KYC flow returns, the quote is re-fetched with the
        // live payable (not the typed fiatText) so a confirmed email surfaces.
        verify(
          () => paymentInfoCubit.getPaymentInfo(
            amount: '249.50',
            currency: Currency.eur,
          ),
        ).called(1);
      },
    );
  });

  group('$PaymentActionButton maxAmountExceeded gate', () {
    testWidgets(
      'renders disabled Next, the max-amount label, not confirm or retry',
      (tester) async {
        when(() => paymentInfoCubit.state).thenReturn(
          const BuyPaymentInfoMaxAmountExceededFailure(
            PaymentInfoError.maxAmountExceeded,
            maxAmount: 90000.6,
          ),
        );
        when(() => converterCubit.state).thenReturn(
          const BuyConverterState(currency: Currency.chf, fiatText: '90001'),
        );

        await pumpButton(tester);

        expect(find.text(S.current.next), findsOne);
        expect(find.text(S.current.buyMaxAmount('90000', 'CHF')), findsOne);
        expect(find.byType(BuyConfirmButton), findsNothing);
        expect(find.text(S.current.buyPaymentConfirm), findsNothing);
        expect(find.text(S.current.retry), findsNothing);
      },
    );
  });
}

/// Minimal capture-page stub that pops with a caller-controlled value on
/// the first post-frame so the widget-under-test reads the result via
/// `pushNamed`.
class _EmailCaptureStub extends StatefulWidget {
  final void Function(BuildContext) onReady;
  const _EmailCaptureStub({required this.onReady});

  @override
  State<_EmailCaptureStub> createState() => _EmailCaptureStubState();
}

class _EmailCaptureStubState extends State<_EmailCaptureStub> {
  @override
  void initState() {
    super.initState();
    widget.onReady(context);
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('CAPTURE'));
}
