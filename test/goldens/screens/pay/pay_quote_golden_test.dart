import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/screens/pay/cubits/pay_quote/pay_quote_cubit.dart';
import 'package:realunit_wallet/screens/pay/pay_quote_page.dart';

import '../../../helper/helper.dart';

class _MockPayQuoteCubit extends MockCubit<PayQuoteState> implements PayQuoteCubit {}

void main() {
  late _MockPayQuoteCubit quoteCubit;

  setUp(() {
    quoteCubit = _MockPayQuoteCubit();
    when(() => quoteCubit.state).thenReturn(const PayQuoteLoading());
  });

  // PayQuotePage resolves its cubit from getIt and calls load(); the golden
  // renders PayQuoteView directly with a mocked cubit so every state is
  // deterministic without the service/DI graph.
  group('$PayQuoteView', () {
    goldenTest(
      'loading state',
      fileName: 'pay_quote_page_loading',
      constraints: phoneConstraints,
      // The CupertinoActivityIndicator animates forever, so pumpAndSettle
      // would time out; pumpOnce captures the first frame.
      pumpBeforeTest: pumpOnce,
      builder: () => wrapForGolden(
        BlocProvider<PayQuoteCubit>.value(
          value: quoteCubit,
          child: const PayQuoteView(),
        ),
      ),
    );

    // Real Sepolia OCP capture (DFXswiss/api #3819): a CHF 2.00 payment link
    // whose Ethereum method settles 2.0 ZCHF. The screen renders the amounts
    // straight from the quote — the app never computes them.
    goldenTest(
      'ready quote with CHF amount and ZCHF needed',
      fileName: 'pay_quote_page_ready',
      constraints: phoneConstraints,
      builder: () {
        when(() => quoteCubit.state).thenReturn(
          const PayQuoteReady(
            paymentLinkId: 'pl_realunit_ocp_sepolia',
            quoteId: 'plq_realunit_ocp_sepolia',
            fiatAsset: 'CHF',
            fiatAmount: 2,
            zchfAmount: 2.0,
          ),
        );
        return wrapForGolden(
          BlocProvider<PayQuoteCubit>.value(
            value: quoteCubit,
            child: const PayQuoteView(),
          ),
        );
      },
    );

    goldenTest(
      'ready quote with merchant and REALU swap details',
      fileName: 'pay_quote_page_ready_with_merchant',
      constraints: phoneConstraints,
      builder: () {
        when(() => quoteCubit.state).thenReturn(
          const PayQuoteReady(
            paymentLinkId: 'pl_realunit_ocp_sepolia',
            quoteId: 'plq_realunit_ocp_sepolia',
            fiatAsset: 'CHF',
            fiatAmount: 2,
            zchfAmount: 2.0,
            merchantName: 'Café Zürich',
            merchantCity: 'Zürich',
            realuAmount: 5,
            realuEstimatedZchf: 1.98,
            realuFeesTotal: 0.02,
          ),
        );
        return wrapForGolden(
          BlocProvider<PayQuoteCubit>.value(
            value: quoteCubit,
            child: const PayQuoteView(),
          ),
        );
      },
    );

    goldenTest(
      'expired quote message',
      fileName: 'pay_quote_page_expired',
      constraints: phoneConstraints,
      builder: () {
        when(() => quoteCubit.state).thenReturn(const PayQuoteExpired());
        return wrapForGolden(
          BlocProvider<PayQuoteCubit>.value(
            value: quoteCubit,
            child: const PayQuoteView(),
          ),
        );
      },
    );
  });
}
