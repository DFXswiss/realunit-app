import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/models/balance.dart';
import 'package:realunit_wallet/packages/utils/default_assets.dart';
import 'package:realunit_wallet/screens/sell/cubits/sell_balance/sell_balance_cubit.dart';
import 'package:realunit_wallet/screens/send/cubits/send_amount/send_amount_cubit.dart';
import 'package:realunit_wallet/screens/send/cubits/send_process/send_process_cubit.dart';
import 'package:realunit_wallet/screens/send/cubits/send_recipient/send_recipient_cubit.dart';
import 'package:realunit_wallet/screens/send/send_amount_page.dart';
import 'package:realunit_wallet/screens/send/send_confirm_page.dart';
import 'package:realunit_wallet/screens/send/send_process_page.dart';
import 'package:realunit_wallet/screens/send/send_recipient_page.dart';

import '../../../helper/helper.dart';

class _MockSendRecipientCubit extends MockCubit<SendRecipientState> implements SendRecipientCubit {}

class _MockSellBalanceCubit extends MockCubit<Balance> implements SellBalanceCubit {}

class _MockSendAmountCubit extends MockCubit<SendAmountState> implements SendAmountCubit {}

class _MockSendProcessCubit extends MockCubit<SendProcessState> implements SendProcessCubit {}

Balance _balance(int shares) => Balance(
  chainId: realUnitAsset.chainId,
  contractAddress: realUnitAsset.address,
  walletAddress: '0xwallet',
  balance: BigInt.from(shares),
  asset: realUnitAsset,
);

void main() {
  setUpAll(() {
    registerFallbackValue(BigInt.zero);
    stubMobileScannerChannel();
  });

  group('$SendRecipientView', () {
    late _MockSendRecipientCubit recipientCubit;

    setUp(() {
      recipientCubit = _MockSendRecipientCubit();
      when(() => recipientCubit.state).thenReturn(const SendRecipientEmpty());
    });

    goldenTest(
      'scan + manual-entry state',
      fileName: 'send_recipient_page_empty',
      constraints: phoneConstraints,
      // The camera preview never reaches an isInitialized frame headlessly, so
      // pumpAndSettle would await a settle that never comes. pumpOnce captures
      // the deterministic placeholder frame.
      pumpBeforeTest: pumpOnce,
      builder: () => wrapForGolden(
        BlocProvider<SendRecipientCubit>.value(
          value: recipientCubit,
          child: const SendRecipientView(),
        ),
      ),
    );
  });

  group('$SendAmountView', () {
    late _MockSellBalanceCubit balanceCubit;
    late _MockSendAmountCubit amountCubit;

    setUp(() {
      balanceCubit = _MockSellBalanceCubit();
      amountCubit = _MockSendAmountCubit();
      when(() => balanceCubit.state).thenReturn(_balance(42));
      when(() => amountCubit.availableShares).thenReturn(BigInt.from(42));
      when(() => amountCubit.availableSharesChanged(any())).thenReturn(null);
      when(() => amountCubit.state).thenReturn(const SendAmountState());
    });

    goldenTest(
      'amount entry with available balance',
      fileName: 'send_amount_page_empty',
      constraints: phoneConstraints,
      builder: () => wrapForGolden(
        MultiBlocProvider(
          providers: [
            BlocProvider<SellBalanceCubit>.value(value: balanceCubit),
            BlocProvider<SendAmountCubit>.value(value: amountCubit),
          ],
          child: const SendAmountView(recipient: '0xRecipient'),
        ),
      ),
    );

    goldenTest(
      'over-balance amount shows the insufficient error',
      fileName: 'send_amount_page_insufficient',
      constraints: phoneConstraints,
      builder: () {
        when(() => amountCubit.state).thenReturn(
          const SendAmountState(
            text: '99',
            amount: 99,
            status: SendAmountStatus.insufficientBalance,
          ),
        );
        return wrapForGolden(
          MultiBlocProvider(
            providers: [
              BlocProvider<SellBalanceCubit>.value(value: balanceCubit),
              BlocProvider<SendAmountCubit>.value(value: amountCubit),
            ],
            child: const SendAmountView(recipient: '0xRecipient'),
          ),
        );
      },
    );
  });

  group('$SendConfirmPage', () {
    goldenTest(
      'transfer summary',
      fileName: 'send_confirm_page',
      constraints: phoneConstraints,
      builder: () => wrapForGolden(
        const SendConfirmPage(
          recipient: '0x9F5713DEacB8e9CAB6c2d3FaE1AFc2715F8D2D71',
          amount: 5,
        ),
      ),
    );
  });

  group('$SendProcessView', () {
    late _MockSendProcessCubit processCubit;

    setUp(() {
      processCubit = _MockSendProcessCubit();
      when(() => processCubit.state).thenReturn(const SendProcessInitial());
    });

    // Terminal states (success/failure) are surfaced via a modal sheet from the
    // listener, not the build tree — exercised in the widget test. The build
    // tree shows the in-progress indicator with a per-state label.
    goldenTest(
      'in-progress signing state',
      fileName: 'send_process_page_signing',
      constraints: phoneConstraints,
      // The CupertinoActivityIndicator animates forever; pumpOnce captures the
      // first frame.
      pumpBeforeTest: pumpOnce,
      builder: () {
        when(() => processCubit.state).thenReturn(const SendProcessSigning());
        return wrapForGolden(
          BlocProvider<SendProcessCubit>.value(
            value: processCubit,
            child: const SendProcessView(),
          ),
        );
      },
    );
  });
}
