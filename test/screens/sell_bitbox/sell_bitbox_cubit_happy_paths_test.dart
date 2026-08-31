import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/config/api_config.dart';
import 'package:realunit_wallet/packages/config/network_mode.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_blockchain_api_service.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_faucet_service.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/dto/broadcast_transaction_request_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/dto/eip7702/eip7702_data_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/dto/real_unit_sell_payment_info_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/dto/real_unit_unsigned_transactions_request_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/sell_payment_info.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_sell_payment_info_service.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';
import 'package:realunit_wallet/packages/wallet/wallet_account.dart';
import 'package:realunit_wallet/screens/sell_bitbox/cubit/sell_bitbox_cubit.dart';
import 'package:realunit_wallet/styles/currency.dart';

import '../../helper/fake_bitbox_credentials.dart';

class _MockFaucet extends Mock implements DfxFaucetService {}

class _MockBlockchain extends Mock implements DfxBlockchainApiService {}

class _MockSellService extends Mock implements RealUnitSellPaymentInfoService {}

class _MockAppStore extends Mock implements AppStore {}

class _MockWallet extends Mock implements AWallet {}

class _MockWalletAccount extends Mock implements AWalletAccount {}

SellPaymentInfo _info({double ethBalance = 1.0}) => SellPaymentInfo(
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
      requiredGasEth: 0.001,
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
  late FakeBitboxCredentials creds;

  setUpAll(() {
    registerFallbackValue(
      const BroadcastTransactionRequestDto(unsignedTx: '', r: '', s: '', v: 0),
    );
    registerFallbackValue(_info());
  });

  setUp(() {
    faucet = _MockFaucet();
    blockchain = _MockBlockchain();
    sellService = _MockSellService();
    appStore = _MockAppStore();
    wallet = _MockWallet();
    account = _MockWalletAccount();
    // success mode → real signature derived from the test private key.
    creds = FakeBitboxCredentials();

    when(() => appStore.wallet).thenReturn(wallet);
    when(() => appStore.apiConfig)
        .thenReturn(const ApiConfig(networkMode: NetworkMode.mainnet));
    when(() => appStore.primaryAddress).thenReturn('0xwallet');
    when(() => wallet.currentAccount).thenReturn(account);
    when(() => account.primaryAddress).thenReturn(creds);
  });

  SellBitboxCubit build() => SellBitboxCubit(
        paymentInfo: _info(),
        faucetService: faucet,
        blockchainService: blockchain,
        sellService: sellService,
        appStore: appStore,
      )..start();

  Future<SellBitboxState> settleToEthReady(SellBitboxCubit cubit) =>
      cubit.stream.firstWhere((s) => s is SellBitboxEthReady);

  // The raw transaction bytes are arbitrary hex — the test private key inside
  // FakeBitboxCredentials produces a deterministic signature over them, so we
  // only need to assert that the cubit reached the post-sign state.
  const rawSwap = '0xdeadbeef';
  const rawDeposit = '0xcafebabe';

  group('confirmSwap (BitBox sign success)', () {
    test(
      'signs the swap tx and emits AwaitingDepositConfirm with the signature',
      () async {
        when(() => sellService.createUnsignedTransactions(any())).thenAnswer(
          (_) async => const RealUnitUnsignedTransactionsRequestDto(
            swap: rawSwap,
            deposit: rawDeposit,
          ),
        );

        final cubit = build();
        await settleToEthReady(cubit);
        await cubit.proceedToSwap();
        expect(cubit.state, isA<SellBitboxAwaitingSwapConfirm>());

        await cubit.confirmSwap();

        final state = cubit.state as SellBitboxAwaitingDepositConfirm;
        // The signed envelope carries the raw swap tx byte-for-byte and a
        // non-zero (r, s) pair from the deterministic test key.
        expect(state.signedSwapTransaction.unsignedTx, rawSwap);
        expect(state.signedSwapTransaction.r, startsWith('0x'));
        expect(state.signedSwapTransaction.s, startsWith('0x'));
        expect(state.signedSwapTransaction.r.length, 66); // 0x + 64 hex chars
        expect(state.signedSwapTransaction.s.length, 66);
        expect(state.rawDepositTransaction, rawDeposit);
        expect(creds.signCallCount, 1);

        await cubit.close();
      },
    );

    test('strips an optional 0x prefix before hex-decoding the raw tx', () async {
      when(() => sellService.createUnsignedTransactions(any())).thenAnswer(
        (_) async => const RealUnitUnsignedTransactionsRequestDto(
          // Mix one prefixed with 0x and one without — both must sign.
          swap: '0xdeadbeef',
          deposit: 'cafebabe',
        ),
      );

      final cubit = build();
      await settleToEthReady(cubit);
      await cubit.proceedToSwap();
      await cubit.confirmSwap();

      // No FormatException from hex.decode — the cubit handled both shapes.
      expect(cubit.state, isA<SellBitboxAwaitingDepositConfirm>());
      await cubit.close();
    });
  });

  group('confirmDeposit (broadcast + confirm happy path)', () {
    test(
      'signs deposit, broadcasts swap then deposit, confirms with the deposit txHash',
      () async {
        when(() => sellService.createUnsignedTransactions(any())).thenAnswer(
          (_) async => const RealUnitUnsignedTransactionsRequestDto(
            swap: rawSwap,
            deposit: rawDeposit,
          ),
        );

        final broadcastCalls = <BroadcastTransactionRequestDto>[];
        when(() => sellService.broadcastTransaction(any(), any())).thenAnswer(
          (invocation) async {
            broadcastCalls
                .add(invocation.positionalArguments[1] as BroadcastTransactionRequestDto);
            return '0xdeposittxhash';
          },
        );
        when(() => sellService.confirmPaymentWithTxHash(any(), any()))
            .thenAnswer((_) async {});

        final cubit = build();
        await settleToEthReady(cubit);
        await cubit.proceedToSwap();
        await cubit.confirmSwap();
        await cubit.confirmDeposit();

        expect(cubit.state, isA<SellBitboxSuccess>());

        // broadcastTransaction is called THREE times: once at the top of
        // confirmDeposit with the already-signed swap, then once for the
        // signed deposit inside _broadcastDepositAndConfirm, plus the swap
        // call inside that helper. Pin the count + the order of the
        // unsignedTx fields.
        expect(broadcastCalls, hasLength(2));
        expect(broadcastCalls[0].unsignedTx, rawSwap);
        expect(broadcastCalls[1].unsignedTx, rawDeposit);

        verify(() => sellService.confirmPaymentWithTxHash(any(), '0xdeposittxhash'))
            .called(1);
        // Two sign calls: swap (confirmSwap) + deposit (confirmDeposit).
        expect(creds.signCallCount, 2);

        await cubit.close();
      },
    );

    test('broadcast failure during deposit → SellBitboxDepositRetry with both signed txs',
        () async {
      when(() => sellService.createUnsignedTransactions(any())).thenAnswer(
        (_) async => const RealUnitUnsignedTransactionsRequestDto(
          swap: rawSwap,
          deposit: rawDeposit,
        ),
      );

      var broadcastCalls = 0;
      when(() => sellService.broadcastTransaction(any(), any())).thenAnswer(
        (_) async {
          broadcastCalls++;
          // The first broadcast (swap) succeeds; the deposit broadcast fails.
          if (broadcastCalls == 2) throw Exception('rpc 502');
          return '0xokhash';
        },
      );
      when(() => sellService.confirmPaymentWithTxHash(any(), any()))
          .thenAnswer((_) async {});

      final cubit = build();
      await settleToEthReady(cubit);
      await cubit.proceedToSwap();
      await cubit.confirmSwap();
      await cubit.confirmDeposit();

      final state = cubit.state as SellBitboxDepositRetry;
      expect(state.signedSwapTransaction.unsignedTx, rawSwap);
      expect(state.signedDepositTransaction.unsignedTx, rawDeposit);
      expect(state.errorMessage, contains('rpc 502'));

      await cubit.close();
    });
  });

  group('retryDeposit (after DepositRetry)', () {
    test('re-runs the deposit broadcast and emits Success on the retry', () async {
      when(() => sellService.createUnsignedTransactions(any())).thenAnswer(
        (_) async => const RealUnitUnsignedTransactionsRequestDto(
          swap: rawSwap,
          deposit: rawDeposit,
        ),
      );

      var broadcastCalls = 0;
      when(() => sellService.broadcastTransaction(any(), any())).thenAnswer(
        (_) async {
          broadcastCalls++;
          // First (swap, call 1) and third (deposit retry, call 3) succeed;
          // second (deposit first attempt) fails.
          if (broadcastCalls == 2) throw Exception('transient rpc');
          return '0xokhash';
        },
      );
      when(() => sellService.confirmPaymentWithTxHash(any(), any()))
          .thenAnswer((_) async {});

      final cubit = build();
      await settleToEthReady(cubit);
      await cubit.proceedToSwap();
      await cubit.confirmSwap();
      await cubit.confirmDeposit();
      expect(cubit.state, isA<SellBitboxDepositRetry>());

      await cubit.retryDeposit();

      expect(cubit.state, isA<SellBitboxSuccess>());
      // 3 broadcasts total: swap, failed deposit attempt, successful retry.
      expect(broadcastCalls, 3);

      await cubit.close();
    });

    test('retry that throws again → stays in DepositRetry with the new error',
        () async {
      when(() => sellService.createUnsignedTransactions(any())).thenAnswer(
        (_) async => const RealUnitUnsignedTransactionsRequestDto(
          swap: rawSwap,
          deposit: rawDeposit,
        ),
      );

      var broadcastCalls = 0;
      when(() => sellService.broadcastTransaction(any(), any())).thenAnswer(
        (_) async {
          broadcastCalls++;
          if (broadcastCalls == 1) return '0xokhash'; // swap
          throw Exception('still 502');
        },
      );
      when(() => sellService.confirmPaymentWithTxHash(any(), any()))
          .thenAnswer((_) async {});

      final cubit = build();
      await settleToEthReady(cubit);
      await cubit.proceedToSwap();
      await cubit.confirmSwap();
      await cubit.confirmDeposit();
      await cubit.retryDeposit();

      final state = cubit.state as SellBitboxDepositRetry;
      expect(state.errorMessage, contains('still 502'));

      await cubit.close();
    });
  });
}
