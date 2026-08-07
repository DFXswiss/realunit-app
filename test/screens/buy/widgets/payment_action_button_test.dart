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

class _MockBuyConverterCubit extends MockCubit<BuyConverterState>
    implements BuyConverterCubit {}

class _MockBuyPaymentInfoCubit extends MockCubit<BuyPaymentInfoState>
    implements BuyPaymentInfoCubit {}

void main() {
  late BuyConverterCubit converterCubit;
  late BuyPaymentInfoCubit paymentInfoCubit;
  late TextEditingController amountController;
  late List<String> pushedRoutes;
  // Result the modelled email-capture page pops with; the buy gate
  // re-fetches the quote after the capture flow returns regardless of the
  // value (mirrors the registration / KYC gates), so the re-fetch is
  // asserted on both paths.
  bool? emailCaptureResult;

  setUpAll(() {
    registerFallbackValue(Currency.chf);
  });

  setUp(() {
    converterCubit = _MockBuyConverterCubit();
    paymentInfoCubit = _MockBuyPaymentInfoCubit();
    amountController = TextEditingController(text: '250');
    pushedRoutes = <String>[];
    emailCaptureResult = true;

    when(() => converterCubit.state)
        .thenReturn(const BuyConverterState(currency: Currency.eur));
    when(
      () => paymentInfoCubit.getPaymentInfo(
        amount: any(named: 'amount'),
        currency: any(named: 'currency'),
      ),
    ).thenAnswer((_) async {});
  });

  tearDown(() => amountController.dispose());

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
            child: Scaffold(
              body: PaymentActionButton(amountController: amountController),
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
          builder: (_, _) {
            pushedRoutes.add(AppRoutes.kyc);
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

        await pumpButton(tester);

        await tester.tap(find.text(S.current.next));
        await tester.pumpAndSettle();

        // Routed to email capture, not to the binding-buy / details flow.
        expect(pushedRoutes, [SupportRoutes.emailCapture]);
        // After the capture flow returns, the quote is re-fetched with the
        // current amount + currency so a now-valid quote surfaces the CTA.
        verify(
          () => paymentInfoCubit.getPaymentInfo(
            amount: '250',
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
          const BuyPaymentInfoFailure(PaymentInfoError.primaryEmailNotConfirmed),
        );

        await pumpButton(tester);

        await tester.tap(find.text(S.current.next));
        await tester.pumpAndSettle();

        // Routed to KYC confirm-email, not to email capture.
        expect(pushedRoutes, [AppRoutes.kyc]);
        // After the KYC flow returns, the quote is re-fetched with the
        // current amount + currency so a now-confirmed email surfaces the CTA.
        verify(
          () => paymentInfoCubit.getPaymentInfo(
            amount: '250',
            currency: Currency.eur,
          ),
        ).called(1);
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
