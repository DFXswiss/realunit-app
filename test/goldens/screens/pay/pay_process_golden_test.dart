import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/screens/pay/cubits/pay_process/pay_process_cubit.dart';
import 'package:realunit_wallet/screens/pay/pay_process_page.dart';

import '../../../helper/helper.dart';

class _MockPayProcessCubit extends MockCubit<PayProcessState> implements PayProcessCubit {}

void main() {
  late _MockPayProcessCubit processCubit;

  setUp(() {
    processCubit = _MockPayProcessCubit();
    when(() => processCubit.state).thenReturn(const PayProcessInitial());
  });

  // PayProcessPage resolves its cubit from getIt and calls start(); the golden
  // renders PayProcessView directly with a mocked cubit. Terminal states
  // (success/failure/retry) are surfaced via modal sheets from the listener,
  // not the build tree — exercised in the widget test. The build tree shows the
  // in-progress indicator with a per-state label, captured here.
  group('$PayProcessView', () {
    goldenTest(
      'in-progress swapping state',
      fileName: 'pay_process_page_swapping',
      constraints: phoneConstraints,
      // The CupertinoActivityIndicator animates forever, so pumpAndSettle would
      // time out; pumpOnce captures the first frame.
      pumpBeforeTest: pumpOnce,
      builder: () {
        when(() => processCubit.state).thenReturn(const PayProcessSwapping());
        return wrapForGolden(
          BlocProvider<PayProcessCubit>.value(
            value: processCubit,
            child: const PayProcessView(),
          ),
        );
      },
    );

    goldenTest(
      'awaiting settlement state',
      fileName: 'pay_process_page_awaiting_settlement',
      constraints: phoneConstraints,
      pumpBeforeTest: pumpOnce,
      builder: () {
        when(() => processCubit.state).thenReturn(const PayProcessAwaitingSettlement('0xtx'));
        return wrapForGolden(
          BlocProvider<PayProcessCubit>.value(
            value: processCubit,
            child: const PayProcessView(),
          ),
        );
      },
    );

    goldenTest(
      'pay-retry state label',
      fileName: 'pay_process_page_pay_retry',
      constraints: phoneConstraints,
      pumpBeforeTest: pumpOnce,
      builder: () {
        when(
          () => processCubit.state,
        ).thenReturn(const PayProcessPayRetry(PayRetryReason.quoteExpired));
        return wrapForGolden(
          BlocProvider<PayProcessCubit>.value(
            value: processCubit,
            child: const PayProcessView(),
          ),
        );
      },
    );
  });
}
