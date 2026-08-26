import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/dto/broadcast_transaction_request_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/dto/eip7702/eip7702_data_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/dto/real_unit_sell_payment_info_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/sell_payment_info.dart';
import 'package:realunit_wallet/screens/sell_bitbox/cubit/sell_bitbox_cubit.dart';
import 'package:realunit_wallet/screens/sell_bitbox/sell_bitbox_page.dart';
import 'package:realunit_wallet/styles/currency.dart';

import '../../../helper/helper.dart';

// SellBitboxCubit.start() schedules `_checkEthBalance` via scheduleMicrotask
// and installs a periodic ETH-polling Timer, so the real page can't be pumped
// deterministically (learned in #815). We render the shared [SellBitboxView]
// with a mocked cubit whose `state` getter is stubbed to the exact target
// state — the same seam the existing `sell_bitbox_golden_test.dart` uses. Each
// golden therefore anchors the View's rendering of one concrete cubit state
// (step widget + progress bar), NOT the cubit's state machine.
class _MockSellBitboxCubit extends MockCubit<SellBitboxState>
    implements SellBitboxCubit {}

Map<String, dynamic> _eip7702Json() => {
      'relayerAddress': '0xrelay',
      'delegationManagerAddress': '0xmgr',
      'delegatorAddress': '0xdr',
      'userNonce': 7,
      'domain': {
        'name': 'RealUnit',
        'version': '1',
        'chainId': 1,
        'verifyingContract': '0xverify',
      },
      'types': {
        'Delegation': <Map<String, dynamic>>[],
        'Caveat': <Map<String, dynamic>>[],
      },
      'message': {
        'delegate': '0xd',
        'delegator': '0xdr',
        'authority': '0xauth',
        'caveats': <Map<String, dynamic>>[],
        'salt': 0,
      },
      'tokenAddress': '0xtoken',
      'amountWei': '12345',
      'depositAddress': '0xdeposit',
    };

SellPaymentInfo _paymentInfo() => SellPaymentInfo(
      id: 42,
      eip7702: Eip7702Data.fromJson(_eip7702Json()),
      amount: 100,
      exchangeRate: 1.0,
      rate: 1.0,
      beneficiary: const BeneficiaryDto(iban: 'CH...'),
      estimatedAmount: 100.0,
      currency: Currency.chf,
      depositAddress: '0xDEP0517addressABCDEF1234',
      tokenAddress: '0xtoken',
      chainId: 1,
      ethBalance: 1.0,
      requiredGasEth: 0.001,
    );

// Fixed, deterministic signed-transaction stand-ins. None of these bytes are
// rendered by the step widgets (they only appear in the cubit's signing path),
// so any stable value keeps the golden byte-identical across regens.
BroadcastTransactionRequestDto _signedTx() => const BroadcastTransactionRequestDto(
      unsignedTx: '0xunsigned',
      r: '0x11',
      s: '0x22',
      v: 27,
    );

void main() {
  late _MockSellBitboxCubit cubit;

  setUp(() {
    cubit = _MockSellBitboxCubit();
  });

  Widget buildSubject() => BlocProvider<SellBitboxCubit>.value(
        value: cubit,
        child: SellBitboxView(paymentInfo: _paymentInfo()),
      );

  Widget forState(SellBitboxState state) {
    when(() => cubit.state).thenReturn(state);
    return wrapForGolden(buildSubject());
  }

  group('$SellBitboxView', () {
    // Step 1 (ETH) — waiting for the faucet top-up: hourglass, headline +
    // description, and a disabled Next button (onPressed: null).
    goldenTest(
      'waiting for eth — hourglass, disabled next',
      fileName: 'sell_bitbox_waiting_for_eth',
      constraints: phoneConstraints,
      builder: () => forState(SellBitboxWaitingForEth()),
    );

    // Step 1 (ETH) — gas is available: check icon, ready copy, active Next.
    goldenTest(
      'eth ready — check, active next',
      fileName: 'sell_bitbox_eth_ready',
      constraints: phoneConstraints,
      builder: () => forState(SellBitboxEthReady()),
    );

    // Step 2 (Swap) — preparing the unsigned transactions: spinner only, with
    // the progress bar advanced to segment 2/3. CupertinoActivityIndicator
    // never settles, so pump a single frame instead of pumpAndSettle.
    goldenTest(
      'preparing swap — spinner, progress 2/3',
      fileName: 'sell_bitbox_preparing_swap',
      constraints: phoneConstraints,
      pumpBeforeTest: pumpOnce,
      builder: () => forState(SellBitboxPreparingSwap()),
    );

    // Step 2 (Swap) — review card: From 100 REALU / To ≈ 100.00 ZCHF + confirm.
    goldenTest(
      'awaiting swap confirm — swap review card',
      fileName: 'sell_bitbox_awaiting_swap_confirm',
      constraints: phoneConstraints,
      builder: () => forState(
        SellBitboxAwaitingSwapConfirm('0xrawswap', '0xrawdeposit'),
      ),
    );

    // Step 2 (Swap) — signing/broadcasting in flight: spinner + "Swapping".
    goldenTest(
      'swapping — spinner',
      fileName: 'sell_bitbox_swapping',
      constraints: phoneConstraints,
      pumpBeforeTest: pumpOnce,
      builder: () => forState(SellBitboxSwapping()),
    );

    // Step 3 (Deposit) — review card: 100.00 ZCHF / truncated deposit address.
    goldenTest(
      'awaiting deposit confirm — deposit review card',
      fileName: 'sell_bitbox_awaiting_deposit_confirm',
      constraints: phoneConstraints,
      builder: () => forState(
        SellBitboxAwaitingDepositConfirm(_signedTx(), '0xrawdeposit'),
      ),
    );

    // Step 3 (Deposit) — deposit broadcast in flight: spinner + "Depositing".
    goldenTest(
      'depositing — spinner',
      fileName: 'sell_bitbox_depositing',
      constraints: phoneConstraints,
      pumpBeforeTest: pumpOnce,
      builder: () => forState(SellBitboxDepositing()),
    );

    // Step 3 (Deposit) — HTTP-only retry in flight on stored signed bytes:
    // same spinner layout but the "Retrying" copy.
    goldenTest(
      'retrying deposit — spinner, retrying copy',
      fileName: 'sell_bitbox_retrying_deposit',
      constraints: phoneConstraints,
      pumpBeforeTest: pumpOnce,
      builder: () => forState(SellBitboxRetryingDeposit()),
    );

    // Step 3 (Deposit) — retry, broadcast never landed (broadcastTxHash == null):
    // error icon + "deposit retry" title/description + Retry button.
    goldenTest(
      'deposit retry — broadcast failed variant',
      fileName: 'sell_bitbox_deposit_retry',
      constraints: phoneConstraints,
      builder: () => forState(
        SellBitboxDepositRetry(_signedTx(), _signedTx(), 'network error'),
      ),
    );

    // Step 3 (Deposit) — retry, deposit IS on-chain (broadcastTxHash != null):
    // only the confirm is pending, so the "confirm retry" copy variant renders.
    goldenTest(
      'deposit retry — confirm-only variant',
      fileName: 'sell_bitbox_confirm_retry',
      constraints: phoneConstraints,
      builder: () => forState(
        SellBitboxDepositRetry(
          _signedTx(),
          _signedTx(),
          'confirm failed',
          broadcastTxHash: '0xhash',
        ),
      ),
    );
  });
}
