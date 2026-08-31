import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/config/api_config.dart';
import 'package:realunit_wallet/packages/config/network_mode.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_blockchain_api_service.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_faucet_service.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/payment/sell_exceptions.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/dto/broadcast_transaction_request_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/dto/eip7702/eip7702_data_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/faucet/faucet_response_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/dto/real_unit_sell_payment_info_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/dto/real_unit_unsigned_transactions_request_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/sell_payment_info.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_sell_payment_info_service.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';
import 'package:realunit_wallet/packages/wallet/wallet_account.dart';
import 'package:realunit_wallet/screens/sell_bitbox/cubit/sell_bitbox_cubit.dart';
import 'package:realunit_wallet/styles/currency.dart';
import 'package:web3dart/web3dart.dart';

import '../../helper/fake_bitbox_credentials.dart';

class _MockFaucet extends Mock implements DfxFaucetService {}

class _MockBlockchain extends Mock implements DfxBlockchainApiService {}

class _MockSellService extends Mock implements RealUnitSellPaymentInfoService {}

class _MockAppStore extends Mock implements AppStore {}

class _MockWallet extends Mock implements AWallet {}

class _MockWalletAccount extends Mock implements AWalletAccount {}

class _StubSoftwareCreds extends Fake implements CredentialsWithKnownAddress {
  @override
  EthereumAddress get address =>
      EthereumAddress.fromHex('0x9F5713dEAcb8e9CaB6c2D3FaE1aFc2715F8D2D71');
}

SellPaymentInfo _info({
  double ethBalance = 1.0,
  double requiredGasEth = 0.001,
}) => SellPaymentInfo(
  id: 42,
  eip7702: Eip7702Data.fromJson(_eip7702Json()),
  amount: 100,
  exchangeRate: 1.0,
  rate: 1.0,
  beneficiary: const BeneficiaryDto(iban: 'CH...'),
  estimatedAmount: 100.0,
  currency: Currency.chf,
  depositAddress: '0xdeposit',
  tokenAddress: '0xtoken',
  chainId: 1,
  ethBalance: ethBalance,
  requiredGasEth: requiredGasEth,
);

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

void main() {
  late _MockFaucet faucet;
  late _MockBlockchain blockchain;
  late _MockSellService sellService;
  late _MockAppStore appStore;
  late _MockWallet wallet;
  late _MockWalletAccount account;

  setUpAll(() {
    registerFallbackValue(
      const BroadcastTransactionRequestDto(unsignedTx: '', r: '', s: '', v: 0),
    );
    // confirmPaymentWithTxHash(any(), any()) needs a non-null SellPaymentInfo
    // fallback so mocktail can fabricate a placeholder argument matcher.
    registerFallbackValue(_info());
  });

  setUp(() {
    faucet = _MockFaucet();
    blockchain = _MockBlockchain();
    sellService = _MockSellService();
    appStore = _MockAppStore();
    wallet = _MockWallet();
    account = _MockWalletAccount();

    when(() => appStore.wallet).thenReturn(wallet);
    when(() => appStore.apiConfig).thenReturn(const ApiConfig(networkMode: NetworkMode.mainnet));
    when(() => appStore.primaryAddress).thenReturn('0xwallet');
    when(() => wallet.currentAccount).thenReturn(account);
  });

  SellBitboxCubit build({SellPaymentInfo? info}) => SellBitboxCubit(
    paymentInfo: info ?? _info(),
    faucetService: faucet,
    blockchainService: blockchain,
    sellService: sellService,
    appStore: appStore,
  )..start();

  // Helper: wait until the cubit settles into a non-Checking state. start()
  // schedules _checkEthBalance via scheduleMicrotask, so the first emit lands
  // after a microtask.
  Future<SellBitboxState> settle(SellBitboxCubit cubit) async {
    if (cubit.state is! SellBitboxCheckingEth) return cubit.state;
    return cubit.stream.firstWhere((s) => s is! SellBitboxCheckingEth);
  }

  group('start / _checkEthBalance', () {
    test('disconnected BitBox → SellBitboxBitboxRequired', () async {
      when(() => account.primaryAddress).thenReturn(
        FakeBitboxCredentials(behavior: FakeBitboxBehavior.disconnect)..bitboxManager = null,
      );

      final cubit = build();
      final state = await settle(cubit);

      expect(state, isA<SellBitboxBitboxRequired>());
      await cubit.close();
    });

    test('ethBalance >= requiredGasEth → SellBitboxEthReady', () async {
      // Use a non-Bitbox credentials so the disconnected check is skipped
      // and the ethBalance branch is exercised directly.
      when(() => account.primaryAddress).thenReturn(_StubSoftwareCreds());

      final cubit = build();
      final state = await settle(cubit);

      expect(state, isA<SellBitboxEthReady>());
      await cubit.close();
    });

    test('ethBalance < required + faucet success → WaitingForEth', () async {
      when(() => account.primaryAddress).thenReturn(_StubSoftwareCreds());
      when(() => faucet.requestFaucet()).thenAnswer(
        (_) async => const FaucetResponseDto(txId: '0xfaucet', amount: 0.01),
      );

      final cubit = build(info: _info(ethBalance: 0, requiredGasEth: 0.001));
      // First non-checking state should be WaitingForEth (RequestingFaucet
      // is fleeting between the two awaits).
      final state = await cubit.stream.firstWhere((s) => s is SellBitboxWaitingForEth);

      expect(state, isA<SellBitboxWaitingForEth>());
      verify(() => faucet.requestFaucet()).called(1);
      await cubit.close();
    });

    test('faucet throws → SellBitboxError', () async {
      when(() => account.primaryAddress).thenReturn(_StubSoftwareCreds());
      when(() => faucet.requestFaucet()).thenAnswer((_) async => throw Exception('faucet down'));

      final cubit = build(info: _info(ethBalance: 0, requiredGasEth: 0.001));
      final state = await cubit.stream.firstWhere((s) => s is SellBitboxError);

      expect(state, isA<SellBitboxError>());
      await cubit.close();
    });
  });

  group('proceedToSwap', () {
    test('success: emits Preparing → AwaitingSwapConfirm with both raw txs', () async {
      when(() => account.primaryAddress).thenReturn(_StubSoftwareCreds());
      when(() => sellService.createUnsignedTransactions(any())).thenAnswer(
        (_) async => const RealUnitUnsignedTransactionsRequestDto(
          swap: '0xswap',
          deposit: '0xdeposit',
        ),
      );

      final cubit = build();
      await settle(cubit);
      await cubit.proceedToSwap();

      final state = cubit.state as SellBitboxAwaitingSwapConfirm;
      expect(state.rawSwapTransaction, '0xswap');
      expect(state.rawDepositTransaction, '0xdeposit');
      await cubit.close();
    });

    test('failure: emits Error', () async {
      when(() => account.primaryAddress).thenReturn(_StubSoftwareCreds());
      when(
        () => sellService.createUnsignedTransactions(any()),
      ).thenAnswer((_) async => throw Exception('api 500'));

      final cubit = build();
      await settle(cubit);
      await cubit.proceedToSwap();

      expect(cubit.state, isA<SellBitboxError>());
      await cubit.close();
    });
  });

  group('confirmSwap', () {
    test('no-op outside SellBitboxAwaitingSwapConfirm', () async {
      when(() => account.primaryAddress).thenReturn(_StubSoftwareCreds());

      final cubit = build();
      await settle(cubit);
      final before = cubit.state;
      await cubit.confirmSwap();

      expect(cubit.state, same(before));
      await cubit.close();
    });

    test('non-Bitbox credentials in AwaitingSwapConfirm → Error', () async {
      when(() => account.primaryAddress).thenReturn(_StubSoftwareCreds());
      when(() => sellService.createUnsignedTransactions(any())).thenAnswer(
        (_) async => const RealUnitUnsignedTransactionsRequestDto(
          swap: '0xswap',
          deposit: '0xdeposit',
        ),
      );

      final cubit = build();
      await settle(cubit);
      await cubit.proceedToSwap();
      await cubit.confirmSwap();

      final state = cubit.state as SellBitboxError;
      expect(state.message, contains('BitBox wallet not connected'));
      await cubit.close();
    });
  });

  group('confirmDeposit', () {
    test('no-op outside SellBitboxAwaitingDepositConfirm', () async {
      when(() => account.primaryAddress).thenReturn(_StubSoftwareCreds());

      final cubit = build();
      await settle(cubit);
      final before = cubit.state;
      await cubit.confirmDeposit();

      expect(cubit.state, same(before));
      await cubit.close();
    });
  });

  group('retryDeposit', () {
    test('no-op outside SellBitboxDepositRetry', () async {
      when(() => account.primaryAddress).thenReturn(_StubSoftwareCreds());

      final cubit = build();
      await settle(cubit);
      final before = cubit.state;
      await cubit.retryDeposit();

      expect(cubit.state, same(before));
      await cubit.close();
    });
  });

  // ---------------------------------------------------------------------------
  // Coverage-completion cases for the branches the happy-path file does not
  // exercise: the defensive catch in _checkEthBalance, retryAfterConnection,
  // the eth-polling Timer body, and the BitboxNotConnectedException +
  // generic-catch branches inside confirmSwap / confirmDeposit / retryDeposit.
  // ---------------------------------------------------------------------------

  group('_checkEthBalance defensive catch', () {
    test('synchronous throw from wallet.currentAccount → SellBitboxError', () async {
      // Replace the chained wallet getter with one that throws — mirrors a
      // boot-time wallet-state corruption (e.g. AppStore not yet initialised
      // when the sheet opens) that would otherwise crash the screen.
      final boom = Exception('wallet boom');
      when(() => wallet.currentAccount).thenThrow(boom);

      final cubit = build();
      final state = await cubit.stream.firstWhere((s) => s is SellBitboxError);

      expect((state as SellBitboxError).message, contains('wallet boom'));
      await cubit.close();
    });
  });

  group('retryAfterConnection', () {
    test('re-runs _checkEthBalance and recovers from BitboxRequired', () async {
      // Start with a disconnected BitBox so the first check lands in
      // SellBitboxBitboxRequired (the "connect your device" screen).
      final creds = FakeBitboxCredentials(behavior: FakeBitboxBehavior.disconnect)
        ..bitboxManager = null;
      when(() => account.primaryAddress).thenReturn(creds);

      final cubit = build();
      expect(await settle(cubit), isA<SellBitboxBitboxRequired>());

      // Simulate the user plugging the device back in. The same instance is
      // now `success` (so `isConnected == true`) AND the payment info has
      // enough ETH, so retryAfterConnection should land in EthReady.
      creds.behavior = FakeBitboxBehavior.success;
      // Attach the listener BEFORE the call: _checkEthBalance emits
      // CheckingEth → EthReady synchronously (no await before the second
      // emit), so a stream listener attached after the call would miss it.
      final readyFuture = cubit.stream.firstWhere((s) => s is SellBitboxEthReady);
      await cubit.retryAfterConnection();
      expect(await readyFuture, isA<SellBitboxEthReady>());
      await cubit.close();
    });
  });

  group('_startEthPolling Timer', () {
    test(
      'polls every 5s; emits SellBitboxEthReady once the balance crosses the gas threshold',
      () {
        fakeAsync((async) {
          // Software credentials skip the BitBox-disconnect branch.
          when(() => account.primaryAddress).thenReturn(_StubSoftwareCreds());
          when(() => faucet.requestFaucet()).thenAnswer(
            (_) async => const FaucetResponseDto(txId: '0xf', amount: 0.01),
          );

          // First poll returns 0 (insufficient), second poll returns enough
          // ETH. Pins the loop semantics: keep polling, don't error.
          var call = 0;
          when(() => blockchain.getEthBalance(any())).thenAnswer((_) async {
            call++;
            return call == 1 ? 0.0 : 0.005;
          });

          final cubit = build(info: _info(ethBalance: 0, requiredGasEth: 0.001));
          // Drive the start() microtask + the awaited faucet request to
          // completion so the periodic Timer is installed.
          async.flushMicrotasks();
          async.elapse(Duration.zero);

          expect(cubit.state, isA<SellBitboxWaitingForEth>());

          // 1st tick @ 5s — balance still 0, stays in WaitingForEth.
          async.elapse(const Duration(seconds: 5));
          async.flushMicrotasks();
          expect(cubit.state, isA<SellBitboxWaitingForEth>());

          // 2nd tick @ 10s — balance crosses the threshold, the cubit emits
          // SellBitboxEthReady and cancels its own timer.
          async.elapse(const Duration(seconds: 5));
          async.flushMicrotasks();
          expect(cubit.state, isA<SellBitboxEthReady>());

          // Further elapses must NOT poll again — the timer cancelled itself.
          final pollsAtReady = call;
          async.elapse(const Duration(seconds: 30));
          async.flushMicrotasks();
          expect(call, pollsAtReady);

          // Drain remaining timers (the cubit owns none anymore) and close.
          cubit.close();
          async.flushTimers();
        });
      },
    );

    test('a transient blockchain error during polling does not crash the cubit', () {
      fakeAsync((async) {
        when(() => account.primaryAddress).thenReturn(_StubSoftwareCreds());
        when(() => faucet.requestFaucet()).thenAnswer(
          (_) async => const FaucetResponseDto(txId: '0xf', amount: 0.01),
        );
        var call = 0;
        when(() => blockchain.getEthBalance(any())).thenAnswer((_) async {
          call++;
          if (call == 1) throw Exception('rpc 503');
          return 0.01; // > requiredGasEth
        });

        final cubit = build(info: _info(ethBalance: 0, requiredGasEth: 0.001));
        async.flushMicrotasks();
        async.elapse(Duration.zero);
        expect(cubit.state, isA<SellBitboxWaitingForEth>());

        // 1st tick → throws → silently swallowed → still waiting.
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();
        expect(cubit.state, isA<SellBitboxWaitingForEth>());

        // 2nd tick → ok → ready.
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();
        expect(cubit.state, isA<SellBitboxEthReady>());

        cubit.close();
        async.flushTimers();
      });
    });

    test('retryAfterConnection while a poll-Timer is alive cancels the prior one', () {
      fakeAsync((async) {
        // Start disconnected so the first _checkEthBalance lands in
        // BitboxRequired without ever installing a Timer.
        final creds = FakeBitboxCredentials(behavior: FakeBitboxBehavior.disconnect)
          ..bitboxManager = null;
        when(() => account.primaryAddress).thenReturn(creds);
        when(() => faucet.requestFaucet()).thenAnswer(
          (_) async => const FaucetResponseDto(txId: '0xf', amount: 0.01),
        );
        when(() => blockchain.getEthBalance(any())).thenAnswer((_) async => 0.0);

        final cubit = build(info: _info(ethBalance: 0, requiredGasEth: 0.001));
        async.flushMicrotasks();
        expect(cubit.state, isA<SellBitboxBitboxRequired>());

        // Reconnect → retry → the credential reports connected but the
        // payment-info still says ethBalance == 0, so the faucet branch fires
        // and installs the first Timer.
        creds.behavior = FakeBitboxBehavior.success;
        cubit.retryAfterConnection();
        async.flushMicrotasks();
        expect(cubit.state, isA<SellBitboxWaitingForEth>());

        // Calling retryAfterConnection again while the Timer is alive must
        // cancel the prior timer before installing a fresh one — otherwise
        // the test would see TWO getEthBalance calls per 5-second tick.
        cubit.retryAfterConnection();
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();
        verify(() => blockchain.getEthBalance(any())).called(1);

        cubit.close();
        async.flushTimers();
      });
    });
  });

  group('confirmSwap with BitBox credentials', () {
    test(
      'BitboxNotConnectedException from the device → SellBitboxBitboxRequired',
      () async {
        // Start with a connected fake so we make it past _checkEthBalance and
        // proceedToSwap; flip to disconnect right before confirmSwap so
        // signToSignature throws BitboxNotConnectedException.
        final creds = FakeBitboxCredentials();
        when(() => account.primaryAddress).thenReturn(creds);
        when(() => sellService.createUnsignedTransactions(any())).thenAnswer(
          (_) async => const RealUnitUnsignedTransactionsRequestDto(
            swap: '0xdeadbeef',
            deposit: '0xcafebabe',
          ),
        );

        final cubit = build();
        await cubit.stream.firstWhere((s) => s is SellBitboxEthReady);
        await cubit.proceedToSwap();
        expect(cubit.state, isA<SellBitboxAwaitingSwapConfirm>());

        creds.behavior = FakeBitboxBehavior.disconnect;
        await cubit.confirmSwap();

        expect(cubit.state, isA<SellBitboxBitboxRequired>());
        await cubit.close();
      },
    );

    test('generic sign failure (FormatException) → SellBitboxError', () async {
      final creds = FakeBitboxCredentials();
      when(() => account.primaryAddress).thenReturn(creds);
      when(() => sellService.createUnsignedTransactions(any())).thenAnswer(
        (_) async => const RealUnitUnsignedTransactionsRequestDto(
          swap: '0xdeadbeef',
          deposit: '0xcafebabe',
        ),
      );

      final cubit = build();
      await cubit.stream.firstWhere((s) => s is SellBitboxEthReady);
      await cubit.proceedToSwap();

      creds.behavior = FakeBitboxBehavior.malformed;
      await cubit.confirmSwap();

      final state = cubit.state as SellBitboxError;
      expect(state.message, contains('Malformed'));
      await cubit.close();
    });
  });

  group('confirmDeposit with BitBox credentials', () {
    test('non-Bitbox credentials in AwaitingDepositConfirm → SellBitboxError', () async {
      // Drive the flow up to AwaitingDepositConfirm with a real BitBox-style
      // fake; then swap the credentials to a non-BitBox stub and call
      // confirmDeposit to hit the type-guard's error branch.
      final creds = FakeBitboxCredentials();
      when(() => account.primaryAddress).thenReturn(creds);
      when(() => sellService.createUnsignedTransactions(any())).thenAnswer(
        (_) async => const RealUnitUnsignedTransactionsRequestDto(
          swap: '0xdeadbeef',
          deposit: '0xcafebabe',
        ),
      );

      final cubit = build();
      await cubit.stream.firstWhere((s) => s is SellBitboxEthReady);
      await cubit.proceedToSwap();
      await cubit.confirmSwap();
      expect(cubit.state, isA<SellBitboxAwaitingDepositConfirm>());

      when(() => account.primaryAddress).thenReturn(_StubSoftwareCreds());
      await cubit.confirmDeposit();

      final state = cubit.state as SellBitboxError;
      expect(state.message, contains('BitBox wallet not connected'));
      await cubit.close();
    });

    test(
      'BitboxNotConnectedException while signing the deposit → SellBitboxBitboxRequired',
      () async {
        final creds = FakeBitboxCredentials();
        when(() => account.primaryAddress).thenReturn(creds);
        when(() => sellService.createUnsignedTransactions(any())).thenAnswer(
          (_) async => const RealUnitUnsignedTransactionsRequestDto(
            swap: '0xdeadbeef',
            deposit: '0xcafebabe',
          ),
        );

        final cubit = build();
        await cubit.stream.firstWhere((s) => s is SellBitboxEthReady);
        await cubit.proceedToSwap();
        await cubit.confirmSwap();
        expect(cubit.state, isA<SellBitboxAwaitingDepositConfirm>());

        creds.behavior = FakeBitboxBehavior.disconnect;
        await cubit.confirmDeposit();

        expect(cubit.state, isA<SellBitboxBitboxRequired>());
        await cubit.close();
      },
    );

    test('generic sign failure during deposit → SellBitboxError', () async {
      final creds = FakeBitboxCredentials();
      when(() => account.primaryAddress).thenReturn(creds);
      when(() => sellService.createUnsignedTransactions(any())).thenAnswer(
        (_) async => const RealUnitUnsignedTransactionsRequestDto(
          swap: '0xdeadbeef',
          deposit: '0xcafebabe',
        ),
      );

      final cubit = build();
      await cubit.stream.firstWhere((s) => s is SellBitboxEthReady);
      await cubit.proceedToSwap();
      await cubit.confirmSwap();
      expect(cubit.state, isA<SellBitboxAwaitingDepositConfirm>());

      creds.behavior = FakeBitboxBehavior.malformed;
      await cubit.confirmDeposit();

      final state = cubit.state as SellBitboxError;
      expect(state.message, contains('Malformed'));
      await cubit.close();
    });
  });

  // Installs the common credential/unsigned-tx stubs and drives the cubit to
  // the deposit step. Per-test broadcast/confirm stubs work installed before
  // or after — mocktail resolves stubs per method, not by setup order.
  Future<SellBitboxCubit> driveToDepositConfirm() async {
    when(() => account.primaryAddress).thenReturn(FakeBitboxCredentials());
    when(() => sellService.createUnsignedTransactions(any())).thenAnswer(
      (_) async => const RealUnitUnsignedTransactionsRequestDto(
        swap: '0xdeadbeef',
        deposit: '0xcafebabe',
      ),
    );
    final cubit = build();
    await cubit.stream.firstWhere((s) => s is SellBitboxEthReady);
    await cubit.proceedToSwap();
    await cubit.confirmSwap();
    await cubit.confirmDeposit();
    return cubit;
  }

  group('retryDeposit idempotency', () {
    test(
      'a retry after broadcast-succeeded/confirm-failed confirms only and '
      'must NOT re-broadcast the on-chain deposit tx',
      () async {
        // Both broadcasts (swap + deposit) succeed …
        when(
          () => sellService.broadcastTransaction(any(), any()),
        ).thenAnswer((_) async => '0xtxhash');
        // … but the payment confirmation fails once, then succeeds.
        var confirms = 0;
        when(() => sellService.confirmPaymentWithTxHash(any(), any())).thenAnswer((_) async {
          confirms++;
          if (confirms == 1) throw Exception('confirm backend down');
        });

        final cubit = await driveToDepositConfirm();

        // The deposit IS on-chain; the retry state must carry its txHash.
        final retry = cubit.state;
        expect(retry, isA<SellBitboxDepositRetry>());
        expect((retry as SellBitboxDepositRetry).broadcastTxHash, '0xtxhash');
        verify(() => sellService.broadcastTransaction(any(), any())).called(2);
        verify(() => sellService.confirmPaymentWithTxHash(any(), any())).called(1);

        await cubit.retryDeposit();

        // Success via confirm-only — not a single additional broadcast (the
        // old behaviour re-broadcast the already-sent tx, looping forever).
        expect(cubit.state, isA<SellBitboxSuccess>());
        verifyNever(() => sellService.broadcastTransaction(any(), any()));
        verify(() => sellService.confirmPaymentWithTxHash(any(), any())).called(1);
      },
    );

    test('a retry after a FAILED broadcast may safely broadcast again', () async {
      // Swap broadcast succeeds, the first deposit broadcast fails, the
      // re-broadcast on retry succeeds.
      var broadcasts = 0;
      when(() => sellService.broadcastTransaction(any(), any())).thenAnswer((_) async {
        broadcasts++;
        if (broadcasts == 2) throw Exception('mempool hiccup');
        return '0xok';
      });
      when(() => sellService.confirmPaymentWithTxHash(any(), any())).thenAnswer((_) async {});

      final cubit = await driveToDepositConfirm();

      // Deposit broadcast failed → nothing on-chain → no txHash carried.
      final retry = cubit.state;
      expect(retry, isA<SellBitboxDepositRetry>());
      expect((retry as SellBitboxDepositRetry).broadcastTxHash, isNull);

      await cubit.retryDeposit();

      expect(cubit.state, isA<SellBitboxSuccess>());
      // The retry actually re-broadcast (swap + failed deposit + re-broadcast)
      // and confirmed with the fresh hash — success is not reachable otherwise.
      verify(() => sellService.broadcastTransaction(any(), any())).called(3);
      verify(() => sellService.confirmPaymentWithTxHash(any(), '0xok')).called(1);
    });

    test('a 409 already-confirmed on retry resolves to success, not another retry loop', () async {
      when(
        () => sellService.broadcastTransaction(any(), any()),
      ).thenAnswer((_) async => '0xtxhash');
      // The first confirm reached the server but its response was lost; the
      // second gets the server's 409 "already confirmed".
      var confirms = 0;
      when(() => sellService.confirmPaymentWithTxHash(any(), any())).thenAnswer((_) async {
        confirms++;
        if (confirms == 1) throw Exception('response lost');
        throw const AlreadyConfirmedException(
          statusCode: 409,
          code: 'CONFLICT',
          message: 'Transaction request is already confirmed',
        );
      });

      final cubit = await driveToDepositConfirm();
      expect(cubit.state, isA<SellBitboxDepositRetry>());
      verify(() => sellService.broadcastTransaction(any(), any())).called(2);

      await cubit.retryDeposit();

      // The sell already completed server-side — the 409 is success, not an error.
      expect(cubit.state, isA<SellBitboxSuccess>());
      verifyNever(() => sellService.broadcastTransaction(any(), any()));
    });
  });

  group('retryDeposit after close', () {
    test('throws StateError from the first emit (no silent state corruption)', () async {
      var broadcasts = 0;
      when(() => sellService.broadcastTransaction(any(), any())).thenAnswer((_) async {
        broadcasts++;
        if (broadcasts == 2) throw Exception('boom');
        return '0xok';
      });
      when(() => sellService.confirmPaymentWithTxHash(any(), any())).thenAnswer((_) async {});

      final cubit = await driveToDepositConfirm();
      expect(cubit.state, isA<SellBitboxDepositRetry>());

      await cubit.close();
      await expectLater(cubit.retryDeposit(), throwsStateError);
    });
  });
}
