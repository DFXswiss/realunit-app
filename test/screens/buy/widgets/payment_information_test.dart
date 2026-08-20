import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/buy/buy_payment_info.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/payment_info_error.dart';
import 'package:realunit_wallet/screens/buy/cubits/buy_payment_info/buy_payment_info_cubit.dart';
import 'package:realunit_wallet/screens/buy/widgets/payment_action_required.dart';
import 'package:realunit_wallet/screens/buy/widgets/payment_information.dart';
import 'package:realunit_wallet/styles/currency.dart';

import '../../../helper/helper.dart';

class _MockBuyPaymentInfoCubit extends MockCubit<BuyPaymentInfoState>
    implements BuyPaymentInfoCubit {}

Widget _host(BuyPaymentInfoCubit cubit) =>
    BlocProvider<BuyPaymentInfoCubit>.value(
      value: cubit,
      child: const PaymentInformation(),
    );

void main() {
  late _MockBuyPaymentInfoCubit cubit;

  setUp(() {
    cubit = _MockBuyPaymentInfoCubit();
  });

  group('$PaymentInformation state-driven rendering', () {
    testWidgets('Loading: CupertinoActivityIndicator', (tester) async {
      when(() => cubit.state).thenReturn(const BuyPaymentInfoLoading());

      await tester.pumpApp(_host(cubit));

      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    });

    testWidgets('Failure(registrationRequired): PaymentActionRequired',
        (tester) async {
      when(() => cubit.state).thenReturn(
        const BuyPaymentInfoFailure(PaymentInfoError.registrationRequired),
      );

      await tester.pumpApp(_host(cubit));

      expect(find.byType(PaymentActionRequired), findsOneWidget);
    });

    testWidgets('Failure(kycRequired): PaymentActionRequired', (tester) async {
      when(() => cubit.state).thenReturn(
        const BuyPaymentInfoFailure(PaymentInfoError.kycRequired),
      );

      await tester.pumpApp(_host(cubit));

      expect(find.byType(PaymentActionRequired), findsOneWidget);
    });

    testWidgets('Failure(unknown): PaymentActionRequired shows API message', (tester) async {
      when(() => cubit.state).thenReturn(
        const BuyPaymentInfoFailure(
          PaymentInfoError.unknown,
          message: 'The purchase could not be quoted. Please try again later.',
        ),
      );

      await tester.pumpApp(_host(cubit));

      expect(find.byType(PaymentActionRequired), findsOneWidget);
      expect(
        find.text('The purchase could not be quoted. Please try again later.'),
        findsOneWidget,
      );
      expect(find.text(S.current.paymentInformationFailed), findsNothing);
    });

    testWidgets(
      'Success: renders nothing — the CTA lives in PaymentActionButton',
      (tester) async {
        // On a valid quote PaymentInformation is silent: the binding-buy CTA
        // and the bank-transfer details are owned by other widgets now.
        when(() => cubit.state).thenReturn(
          const BuyPaymentInfoSuccess(
            BuyPaymentInfo(
              amount: 300,
              id: 1,
              iban: 'iban',
              bic: 'bic',
              name: 'name',
              street: 'street',
              number: 'number',
              zip: 'zip',
              city: 'city',
              country: 'country',
              currency: Currency.chf,
            ),
          ),
        );

        await tester.pumpApp(_host(cubit));

        expect(find.byType(PaymentActionRequired), findsNothing);
        expect(find.byType(CupertinoActivityIndicator), findsNothing);
      },
    );

    testWidgets(
      'Failure(minAmountNotMet) (without specialized class) falls through to SizedBox.shrink',
      (tester) async {
        // Using the generic BuyPaymentInfoFailure with minAmountNotMet — the
        // widget's branch only handles the branded errors, so the fallback
        // SizedBox.shrink should be returned.
        when(() => cubit.state).thenReturn(
          const BuyPaymentInfoFailure(PaymentInfoError.minAmountNotMet),
        );

        await tester.pumpApp(_host(cubit));

        expect(find.byType(PaymentActionRequired), findsNothing);
        expect(find.byType(CupertinoActivityIndicator), findsNothing);
      },
    );

    testWidgets('Initial (or unhandled): SizedBox.shrink', (tester) async {
      when(() => cubit.state).thenReturn(const BuyPaymentInfoInitial());

      await tester.pumpApp(_host(cubit));

      expect(find.byType(PaymentActionRequired), findsNothing);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
    });
  });
}
