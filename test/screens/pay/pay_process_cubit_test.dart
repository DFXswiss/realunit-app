import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart';
import 'package:realunit_wallet/packages/config/api_config.dart';
import 'package:realunit_wallet/packages/config/network_mode.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_blockchain_api_service.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_faucet_service.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/bitbox_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/models/faucet/faucet_response_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/pay/dto/lnurlp_payment_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/pay/dto/real_unit_ocp_pay_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/pay/dto/real_unit_ocp_pay_status_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/pay/dto/real_unit_ocp_pay_submit_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/pay/dto/real_unit_ocp_pay_unsigned_transaction_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/pay/dto/real_unit_swap_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/pay/dto/real_unit_swap_payment_info_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/pay/dto/real_unit_swap_unsigned_transaction_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/pay/swap_payment_info.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/dto/broadcast_transaction_request_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_pay_service.dart';
import 'package:realunit_wallet/packages/service/wallet_service.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';
import 'package:realunit_wallet/packages/wallet/wallet_account.dart';
import 'package:realunit_wallet/screens/pay/cubits/pay_process/pay_process_cubit.dart';

import '../../helper/fake_bitbox_credentials.dart';

class _MockPayService extends Mock implements RealUnitPayService {}

class _MockFaucet extends Mock implements DfxFaucetService {}

class _MockBlockchain extends Mock implements DfxBlockchainApiService {}

class _MockWalletService extends Mock implements WalletService {}

class _MockAppStore extends Mock implements AppStore {}

class _MockWallet extends Mock implements AWallet {}

class _MockAccount extends Mock implements AWalletAccount {}

/// Credentials whose `signToSignature` throws [UnsupportedError] — the debug
/// wallet's behaviour, used to exercise the in-sign defensive guard.
class _UnsupportedCreds extends Fake implements CredentialsWithKnownAddress {
  @override
  Future<MsgSignature> signToSignature(Uint8List payload, {int? chainId, bool isEIP1559 = false}) =>
      throw UnsupportedError('Debug wallet cannot sign');
}

SwapPaymentInfo _swap({
  double ethBalance = 1.0,
  double requiredGasEth = 0.001,
  bool isValid = true,
}) {
  return SwapPaymentInfo.fromDto(
    RealUnitSwapPaymentInfoDto(
      id: 99,
      uid: 'u',
      routeId: 7,
      timestamp: DateTime.parse('2026-06-03T00:00:00.000Z'),
      amount: 10,
      estimatedAmount: 960,
      targetAsset: 'ZCHF',
      minVolume: 1,
      maxVolume: 1000,
      minVolumeTarget: 95,
      maxVolumeTarget: 95000,
      ethBalance: ethBalance,
      requiredGasEth: requiredGasEth,
      isValid: isValid,
    ),
  );
}

LnurlpPaymentDto _details({
  required DateTime expiration,
  String quoteId = 'quote_fresh',
  double zchf = 42.7,
}) {
  // rawAmount mirrors production fromJson (always set when amount is present)
  // so the settlement guard can prove exact plain-decimal coverage fail-closed
  // instead of treating a missing raw string as "cannot prove coverage".
  return LnurlpPaymentDto(
    requestedAmount: const LnurlpRequestedAmountDto(asset: 'CHF', amount: 42.5),
    quote: LnurlpQuoteDto(id: quoteId, expiration: expiration),
    transferAmounts: [
      LnurlpTransferAmountDto(
        method: 'Ethereum',
        assets: [
          LnurlpTransferAssetDto(
            asset: 'ZCHF',
            amount: zchf,
            rawAmount: zchf.toString(),
          ),
        ],
      ),
    ],
  );
}

// A real EIP-1559 (type 2) unsigned tx RLP-encoding an ERC20 transfer(address,uint256) call to
// `recipient` for `amountWei`, `to` = tokenAddress, on `chainId` — matches the DTO's own security
// metadata so PayProcessCubit._validatePayUnsignedTx accepts it. Independently verified
// byte-for-byte against a reference RLP encoder/decoder.
const _unsignedPay = RealUnitOcpPayUnsignedTransactionDto(
  unsignedTx:
      '0x02f87183aa36a7018459682f008504a817c800830186a094111111111111111111111111111111111111ac0180b844a9059cbb000000000000000000000000222222222222222222222222222222222222bc020000000000000000000000000000000000000000000000004563918244f40000c0',
  tokenAddress: '0x111111111111111111111111111111111111ac01',
  recipient: '0x222222222222222222222222222222222222bc02',
  amountWei: '5000000000000000000',
  chainId: 11155111,
);

// tx.to (0x333...dead) does not match tokenAddress (0x111...ac01) — tokenAddress mismatch.
const _unsignedPayWrongToken = RealUnitOcpPayUnsignedTransactionDto(
  unsignedTx:
      '0x02f87183aa36a7018459682f008504a817c800830186a094333333333333333333333333333333333333dead80b844a9059cbb000000000000000000000000222222222222222222222222222222222222bc020000000000000000000000000000000000000000000000004563918244f40000c0',
  tokenAddress: '0x111111111111111111111111111111111111ac01',
  recipient: '0x222222222222222222222222222222222222bc02',
  amountWei: '5000000000000000000',
  chainId: 11155111,
);

// calldata recipient (0x444...dead) does not match recipient (0x222...bc02) — recipient mismatch.
const _unsignedPayWrongRecipient = RealUnitOcpPayUnsignedTransactionDto(
  unsignedTx:
      '0x02f87183aa36a7018459682f008504a817c800830186a094111111111111111111111111111111111111ac0180b844a9059cbb000000000000000000000000444444444444444444444444444444444444dead0000000000000000000000000000000000000000000000004563918244f40000c0',
  tokenAddress: '0x111111111111111111111111111111111111ac01',
  recipient: '0x222222222222222222222222222222222222bc02',
  amountWei: '5000000000000000000',
  chainId: 11155111,
);

// calldata amount is amountWei + 1 (5000000000000000001) — amount mismatch.
const _unsignedPayWrongAmount = RealUnitOcpPayUnsignedTransactionDto(
  unsignedTx:
      '0x02f87183aa36a7018459682f008504a817c800830186a094111111111111111111111111111111111111ac0180b844a9059cbb000000000000000000000000222222222222222222222222222222222222bc020000000000000000000000000000000000000000000000004563918244f40001c0',
  tokenAddress: '0x111111111111111111111111111111111111ac01',
  recipient: '0x222222222222222222222222222222222222bc02',
  amountWei: '5000000000000000000',
  chainId: 11155111,
);

// tx.chainId is 999 — chainId mismatch (DTO still claims 11155111).
const _unsignedPayWrongChainId = RealUnitOcpPayUnsignedTransactionDto(
  unsignedTx:
      '0x02f8708203e7018459682f008504a817c800830186a094111111111111111111111111111111111111ac0180b844a9059cbb000000000000000000000000222222222222222222222222222222222222bc020000000000000000000000000000000000000000000000004563918244f40000c0',
  tokenAddress: '0x111111111111111111111111111111111111ac01',
  recipient: '0x222222222222222222222222222222222222bc02',
  amountWei: '5000000000000000000',
  chainId: 11155111,
);

// Same to/recipient/amount/chainId as _unsignedPay (all still valid), but gasLimit is raised to
// 300000 — exceeds the 200_000 local gasLimit cap alone (maxFeePerGas unchanged @ 20 gwei, so
// total fee stays 0.006 ETH, well under the total-fee cap) — isolates the gasLimit check.
const _unsignedPayGasLimitExceedsCap = RealUnitOcpPayUnsignedTransactionDto(
  unsignedTx:
      '0x02f87183aa36a7018459682f008504a817c800830493e094111111111111111111111111111111111111ac0180b844a9059cbb000000000000000000000000222222222222222222222222222222222222bc020000000000000000000000000000000000000000000000004563918244f40000c0',
  tokenAddress: '0x111111111111111111111111111111111111ac01',
  recipient: '0x222222222222222222222222222222222222bc02',
  amountWei: '5000000000000000000',
  chainId: 11155111,
);

// Same to/recipient/amount/chainId as _unsignedPay, gasLimit unchanged at 100000 (under the
// 200_000 cap), but maxFeePerGas is raised to 600 gwei — total fee becomes 0.06 ETH, over the
// 0.05 ETH total-fee cap alone — isolates the total-fee check.
const _unsignedPayMaxFeeExceedsCap = RealUnitOcpPayUnsignedTransactionDto(
  unsignedTx:
      '0x02f87183aa36a7018459682f00858bb2c97000830186a094111111111111111111111111111111111111ac0180b844a9059cbb000000000000000000000000222222222222222222222222222222222222bc020000000000000000000000000000000000000000000000004563918244f40000c0',
  tokenAddress: '0x111111111111111111111111111111111111ac01',
  recipient: '0x222222222222222222222222222222222222bc02',
  amountWei: '5000000000000000000',
  chainId: 11155111,
);

// Same to/recipient/amount/chainId as _unsignedPay, but the native ETH `value` field is 1 wei
// instead of 0 — an ERC20 transfer must carry zero value. Verified byte-for-byte against a
// reference RLP encoder/decoder (only the single value byte 0x80→0x01 differs from _unsignedPay).
const _unsignedPayNonZeroValue = RealUnitOcpPayUnsignedTransactionDto(
  unsignedTx:
      '0x02f87183aa36a7018459682f008504a817c800830186a094111111111111111111111111111111111111ac0101b844a9059cbb000000000000000000000000222222222222222222222222222222222222bc020000000000000000000000000000000000000000000000004563918244f40000c0',
  tokenAddress: '0x111111111111111111111111111111111111ac01',
  recipient: '0x222222222222222222222222222222222222bc02',
  amountWei: '5000000000000000000',
  chainId: 11155111,
);

// Same unsignedTx/tokenAddress/recipient/chainId as _unsignedPay (all still valid and
// self-consistent), but the DTO's amountWei is not a parseable integer.
const _unsignedPayInvalidAmountWei = RealUnitOcpPayUnsignedTransactionDto(
  unsignedTx:
      '0x02f87183aa36a7018459682f008504a817c800830186a094111111111111111111111111111111111111ac0180b844a9059cbb000000000000000000000000222222222222222222222222222222222222bc020000000000000000000000000000000000000000000000004563918244f40000c0',
  tokenAddress: '0x111111111111111111111111111111111111ac01',
  recipient: '0x222222222222222222222222222222222222bc02',
  amountWei: 'not-a-number',
  chainId: 11155111,
);

// Same unsignedTx/recipient/amountWei/chainId as _unsignedPay, but the DTO's tokenAddress is
// not a valid 20-byte hex address.
const _unsignedPayInvalidTokenAddress = RealUnitOcpPayUnsignedTransactionDto(
  unsignedTx:
      '0x02f87183aa36a7018459682f008504a817c800830186a094111111111111111111111111111111111111ac0180b844a9059cbb000000000000000000000000222222222222222222222222222222222222bc020000000000000000000000000000000000000000000000004563918244f40000c0',
  tokenAddress: 'not-a-valid-address',
  recipient: '0x222222222222222222222222222222222222bc02',
  amountWei: '5000000000000000000',
  chainId: 11155111,
);

void main() {
  late _MockPayService payService;
  late _MockFaucet faucet;
  late _MockBlockchain blockchain;
  late _MockWalletService walletService;
  late _MockAppStore appStore;
  late _MockWallet wallet;
  late _MockAccount account;

  setUpAll(() {
    registerFallbackValue(const RealUnitSwapDto.fromTargetAmount(1));
    registerFallbackValue(const RealUnitOcpPayDto(paymentLinkId: 'pl_abc', quoteId: 'q'));
    registerFallbackValue(
      const BroadcastTransactionRequestDto(unsignedTx: '', r: '', s: '', v: 0),
    );
    registerFallbackValue(
      const RealUnitOcpPaySubmitDto(
        unsignedTx: '',
        r: '',
        s: '',
        v: 0,
        paymentLinkId: 'pl_abc',
        quoteId: 'q',
      ),
    );
  });

  setUp(() {
    payService = _MockPayService();
    faucet = _MockFaucet();
    blockchain = _MockBlockchain();
    walletService = _MockWalletService();
    appStore = _MockAppStore();
    wallet = _MockWallet();
    account = _MockAccount();

    // testnet → apiConfig.asset.chainId = 11155111, matching every unsigned-tx fixture in this file
    when(() => appStore.apiConfig).thenReturn(const ApiConfig(networkMode: NetworkMode.testnet));
    when(() => appStore.primaryAddress).thenReturn('0xwallet');
    when(() => appStore.wallet).thenReturn(wallet);
    when(() => wallet.walletType).thenReturn(WalletType.software);
    when(() => wallet.currentAccount).thenReturn(account);
    when(() => account.primaryAddress).thenReturn(FakeBitboxCredentials(signDelay: Duration.zero));
    when(() => walletService.ensureCurrentWalletUnlocked()).thenAnswer((_) async {});
    when(() => walletService.lockCurrentWallet()).thenAnswer((_) async {});
  });

  PayProcessCubit build({double zchfNeeded = 42.7}) => PayProcessCubit(
    payService: payService,
    faucetService: faucet,
    blockchainService: blockchain,
    walletService: walletService,
    appStore: appStore,
    paymentLinkId: 'pl_abc',
    zchfNeeded: zchfNeeded,
  );

  void wireHappyPath() {
    when(() => payService.getSwapPaymentInfo(any())).thenAnswer((_) async => _swap());
    when(() => payService.createSwapUnsignedTransaction(any())).thenAnswer(
      (_) async => const RealUnitSwapUnsignedTransactionDto(swap: '0x02f8aa'),
    );
    when(
      () => payService.broadcastSwapTransaction(any(), any()),
    ).thenAnswer((_) async => '0xswaptx');
    when(() => payService.getPaymentDetails('pl_abc')).thenAnswer(
      (_) async => _details(expiration: DateTime.now().add(const Duration(minutes: 5))),
    );
    when(
      () => payService.createPayUnsignedTransaction(any()),
    ).thenAnswer((_) async => _unsignedPay);
    when(() => payService.submitPay(any())).thenAnswer((_) async => '0xpaytx');
  }

  // The sign step uses `Future.delayed(Duration.zero)` (FakeBitboxCredentials),
  // which is a zero-duration *timer* under fakeAsync — `flushMicrotasks` alone
  // does not fire it. Elapsing zero repeatedly drains the whole await chain
  // (each mock `thenAnswer` future + every zero-delay sign timer) until the
  // cubit settles.
  void drain(FakeAsync async) {
    for (var i = 0; i < 40; i++) {
      async.flushMicrotasks();
      async.elapse(Duration.zero);
    }
  }

  test('debug wallet → signatureUnsupported before any network call', () async {
    when(() => wallet.walletType).thenReturn(WalletType.debug);

    final cubit = build();
    await cubit.start();

    final state = cubit.state as PayProcessFailure;
    expect(state.reason, PayProcessFailureReason.signatureUnsupported);
    verifyNever(() => payService.getSwapPaymentInfo(any()));
    await cubit.close();
  });

  test('invalid swap quote → insufficientZchf', () async {
    when(() => payService.getSwapPaymentInfo(any())).thenAnswer((_) async => _swap(isValid: false));

    final cubit = build();
    await cubit.start();

    final state = cubit.state as PayProcessFailure;
    expect(state.reason, PayProcessFailureReason.insufficientZchf);
    await cubit.close();
  });

  test('swap sizes the target with a slippage buffer over the ZCHF needed', () async {
    wireHappyPath();
    when(() => payService.getPayStatus('pl_abc')).thenAnswer(
      (_) async => const RealUnitOcpPayStatusDto(status: OcpPaymentStatus.completed),
    );
    RealUnitSwapDto? sentDto;
    when(() => payService.getSwapPaymentInfo(any())).thenAnswer((invocation) async {
      sentDto = invocation.positionalArguments.first as RealUnitSwapDto;
      return _swap();
    });

    final cubit = build(zchfNeeded: 100);
    await cubit.start();

    // After start() resolves the chain the pay tx has been submitted.
    expect(cubit.state, isA<PayProcessAwaitingSettlement>());
    // 100 * 1.03 swap headroom buffer (covers ordinary CHF→ZCHF / swap-rate
    // drift between scan and settle).
    expect(sentDto!.targetAmount, closeTo(103, 0.0001));
    expect(sentDto!.amount, isNull);
    await cubit.close();
  });

  test('happy path: swap → refresh quote → pay → polled Completed → success', () async {
    fakeAsync((async) {
      wireHappyPath();
      when(() => payService.getPayStatus('pl_abc')).thenAnswer(
        (_) async => const RealUnitOcpPayStatusDto(status: OcpPaymentStatus.completed),
      );

      final cubit = build();
      cubit.start();
      drain(async);

      // Pay submitted → polling status.
      expect(cubit.state, isA<PayProcessAwaitingSettlement>());

      // First status poll @ 3s returns Completed → success.
      async.elapse(const Duration(seconds: 3));
      drain(async);
      expect(cubit.state, isA<PayProcessSuccess>());

      cubit.close();
      async.flushTimers();
    });
  });

  test('re-fetched quote sends a fresh quoteId into the pay step', () async {
    wireHappyPath();
    when(() => payService.getPaymentDetails('pl_abc')).thenAnswer(
      (_) async =>
          _details(expiration: DateTime.now().add(const Duration(minutes: 5)), quoteId: 'q_fresh2'),
    );
    RealUnitOcpPayDto? payDto;
    when(() => payService.createPayUnsignedTransaction(any())).thenAnswer((invocation) async {
      payDto = invocation.positionalArguments.first as RealUnitOcpPayDto;
      return _unsignedPay;
    });

    final cubit = build();
    final settled = cubit.stream.firstWhere((s) => s is PayProcessAwaitingSettlement);
    await cubit.start();
    await settled;

    expect(payDto!.quoteId, 'q_fresh2');
    await cubit.close();
  });

  test('quote expired between swap and pay → pay-only retry (no re-scan)', () async {
    wireHappyPath();
    when(() => payService.getPaymentDetails('pl_abc')).thenAnswer(
      (_) async => _details(expiration: DateTime.now().subtract(const Duration(minutes: 1))),
    );

    final cubit = build();
    final retry = cubit.stream.firstWhere((s) => s is PayProcessPayRetry);
    await cubit.start();
    final state = await retry as PayProcessPayRetry;

    // Genuine expiry surfaces as a retryable state — NOT a terminal failure —
    // because the swap already ran. The pay leg is never submitted here.
    expect(state.reason, PayRetryReason.quoteExpired);
    verifyNever(() => payService.createPayUnsignedTransaction(any()));
    await cubit.close();
  });

  test('pay submit failure after swap → retry (transient), not terminal', () async {
    wireHappyPath();
    when(() => payService.submitPay(any())).thenThrow(Exception('settlement rejected'));

    final cubit = build();
    final retry = cubit.stream.firstWhere((s) => s is PayProcessPayRetry);
    await cubit.start();
    final state = await retry as PayProcessPayRetry;

    // The swap is done; a failed pay must NOT force a re-swap.
    expect(state.reason, PayRetryReason.transient);
    expect(cubit.state, isNot(isA<PayProcessFailure>()));
    await cubit.close();
  });

  test('unsigned pay tx "to" does not match DTO tokenAddress → unsignedTxMismatch, never signed',
      () async {
    wireHappyPath();
    when(() => payService.createPayUnsignedTransaction(any()))
        .thenAnswer((_) async => _unsignedPayWrongToken);

    final cubit = build();
    final retry = cubit.stream.firstWhere((s) => s is PayProcessPayRetry);
    await cubit.start();
    final state = await retry as PayProcessPayRetry;

    expect(state.reason, PayRetryReason.unsignedTxMismatch);
    verifyNever(() => payService.submitPay(any()));
    await cubit.close();
  });

  test('unsigned pay tx calldata recipient does not match DTO recipient → unsignedTxMismatch, never signed',
      () async {
    wireHappyPath();
    when(() => payService.createPayUnsignedTransaction(any()))
        .thenAnswer((_) async => _unsignedPayWrongRecipient);

    final cubit = build();
    final retry = cubit.stream.firstWhere((s) => s is PayProcessPayRetry);
    await cubit.start();
    final state = await retry as PayProcessPayRetry;

    expect(state.reason, PayRetryReason.unsignedTxMismatch);
    verifyNever(() => payService.submitPay(any()));
    await cubit.close();
  });

  test('unsigned pay tx calldata amount does not match DTO amountWei → unsignedTxMismatch, never signed',
      () async {
    wireHappyPath();
    when(() => payService.createPayUnsignedTransaction(any()))
        .thenAnswer((_) async => _unsignedPayWrongAmount);

    final cubit = build();
    final retry = cubit.stream.firstWhere((s) => s is PayProcessPayRetry);
    await cubit.start();
    final state = await retry as PayProcessPayRetry;

    expect(state.reason, PayRetryReason.unsignedTxMismatch);
    verifyNever(() => payService.submitPay(any()));
    await cubit.close();
  });

  test('unsigned pay tx chainId does not match DTO chainId → unsignedTxMismatch, never signed',
      () async {
    wireHappyPath();
    when(() => payService.createPayUnsignedTransaction(any()))
        .thenAnswer((_) async => _unsignedPayWrongChainId);

    final cubit = build();
    final retry = cubit.stream.firstWhere((s) => s is PayProcessPayRetry);
    await cubit.start();
    final state = await retry as PayProcessPayRetry;

    expect(state.reason, PayRetryReason.unsignedTxMismatch);
    verifyNever(() => payService.submitPay(any()));
    await cubit.close();
  });

  test(
    'unsigned pay tx+DTO self-consistent but chainId mismatches local apiConfig → unsignedTxMismatch, never signed',
    () async {
      // _unsignedPay is self-consistent at chainId 11155111 (DTO + RLP both agree), so the
      // DTO-vs-tx check would pass. Override apiConfig to mainnet (local chainId=1) to prove
      // the independent local-chainId check rejects it.
      wireHappyPath();
      when(() => appStore.apiConfig).thenReturn(const ApiConfig(networkMode: NetworkMode.mainnet));

      final cubit = build();
      final retry = cubit.stream.firstWhere((s) => s is PayProcessPayRetry);
      await cubit.start();
      final state = await retry as PayProcessPayRetry;

      expect(state.reason, PayRetryReason.unsignedTxMismatch);
      verifyNever(() => payService.submitPay(any()));
      await cubit.close();
    },
  );

  test('unsigned pay tx gasLimit exceeds local cap → unsignedTxMismatch, never signed', () async {
    wireHappyPath();
    when(() => payService.createPayUnsignedTransaction(any()))
        .thenAnswer((_) async => _unsignedPayGasLimitExceedsCap);

    final cubit = build();
    final retry = cubit.stream.firstWhere((s) => s is PayProcessPayRetry);
    await cubit.start();
    final state = await retry as PayProcessPayRetry;

    expect(state.reason, PayRetryReason.unsignedTxMismatch);
    verifyNever(() => payService.submitPay(any()));
    await cubit.close();
  });

  test('unsigned pay tx max total fee exceeds local cap → unsignedTxMismatch, never signed',
      () async {
    wireHappyPath();
    when(() => payService.createPayUnsignedTransaction(any()))
        .thenAnswer((_) async => _unsignedPayMaxFeeExceedsCap);

    final cubit = build();
    final retry = cubit.stream.firstWhere((s) => s is PayProcessPayRetry);
    await cubit.start();
    final state = await retry as PayProcessPayRetry;

    expect(state.reason, PayRetryReason.unsignedTxMismatch);
    verifyNever(() => payService.submitPay(any()));
    await cubit.close();
  });

  test('unsigned pay tx sends non-zero native value → unsignedTxMismatch, never signed', () async {
    wireHappyPath();
    when(() => payService.createPayUnsignedTransaction(any()))
        .thenAnswer((_) async => _unsignedPayNonZeroValue);

    final cubit = build();
    final retry = cubit.stream.firstWhere((s) => s is PayProcessPayRetry);
    await cubit.start();
    final state = await retry as PayProcessPayRetry;

    expect(state.reason, PayRetryReason.unsignedTxMismatch);
    verifyNever(() => payService.submitPay(any()));
    await cubit.close();
  });

  test('unsigned pay tx DTO amountWei is not a valid integer → unsignedTxMismatch, never signed',
      () async {
    wireHappyPath();
    when(() => payService.createPayUnsignedTransaction(any()))
        .thenAnswer((_) async => _unsignedPayInvalidAmountWei);

    final cubit = build();
    final retry = cubit.stream.firstWhere((s) => s is PayProcessPayRetry);
    await cubit.start();
    final state = await retry as PayProcessPayRetry;

    expect(state.reason, PayRetryReason.unsignedTxMismatch);
    expect(state.message, contains('amountWei is not a valid integer'));
    verifyNever(() => payService.submitPay(any()));
    await cubit.close();
  });

  test(
    'unsigned pay tx DTO tokenAddress is not a valid 20-byte address → unsignedTxMismatch, never signed',
    () async {
      wireHappyPath();
      when(() => payService.createPayUnsignedTransaction(any()))
          .thenAnswer((_) async => _unsignedPayInvalidTokenAddress);

      final cubit = build();
      final retry = cubit.stream.firstWhere((s) => s is PayProcessPayRetry);
      await cubit.start();
      final state = await retry as PayProcessPayRetry;

      expect(state.reason, PayRetryReason.unsignedTxMismatch);
      expect(state.message, contains('tokenAddress is not a valid 20-byte address'));
      verifyNever(() => payService.submitPay(any()));
      await cubit.close();
    },
  );

  test('terminal non-completed status (Cancelled) → pay-only retry', () async {
    fakeAsync((async) {
      wireHappyPath();
      when(() => payService.getPayStatus('pl_abc')).thenAnswer(
        (_) async => const RealUnitOcpPayStatusDto(status: OcpPaymentStatus.cancelled),
      );

      final cubit = build();
      cubit.start();
      drain(async);
      expect(cubit.state, isA<PayProcessAwaitingSettlement>());

      async.elapse(const Duration(seconds: 3));
      drain(async);
      // A cancelled settlement after the swap leaves the user holding ZCHF — it
      // is recoverable by retrying the pay leg, not a terminal failure.
      final state = cubit.state as PayProcessPayRetry;
      expect(state.reason, PayRetryReason.transient);

      cubit.close();
      async.flushTimers();
    });
  });

  test('status polling ignores a transient error then settles', () async {
    fakeAsync((async) {
      wireHappyPath();
      var call = 0;
      when(() => payService.getPayStatus('pl_abc')).thenAnswer((_) async {
        call++;
        if (call == 1) throw Exception('rpc 503');
        return const RealUnitOcpPayStatusDto(status: OcpPaymentStatus.completed);
      });

      final cubit = build();
      cubit.start();
      drain(async);

      // 1st poll throws → still awaiting.
      async.elapse(const Duration(seconds: 3));
      drain(async);
      expect(cubit.state, isA<PayProcessAwaitingSettlement>());

      // 2nd poll completes → success.
      async.elapse(const Duration(seconds: 3));
      drain(async);
      expect(cubit.state, isA<PayProcessSuccess>());

      cubit.close();
      async.flushTimers();
    });
  });

  test('status polling exceeds max attempts on a persistently non-terminal status → transient retry',
      () {
    fakeAsync((async) {
      wireHappyPath();
      var pollCalls = 0;
      when(() => payService.getPayStatus('pl_abc')).thenAnswer((_) async {
        pollCalls++;
        return const RealUnitOcpPayStatusDto(status: OcpPaymentStatus.pending);
      });

      final cubit = build();
      cubit.start();
      drain(async);
      expect(cubit.state, isA<PayProcessAwaitingSettlement>());

      // 40 polls @ 3s, each still Pending (never terminal) — the 40th hits the max-attempts
      // cap and gives up rather than polling forever. Iterations 1-39 exercise the
      // "still polling" branch; iteration 40 exercises the "give up" branch.
      for (var i = 0; i < 40; i++) {
        async.elapse(const Duration(seconds: 3));
        drain(async);
      }

      final state = cubit.state as PayProcessPayRetry;
      expect(state.reason, PayRetryReason.transient);
      expect(state.message, 'status polling exceeded max attempts');
      expect(pollCalls, 40);

      // Polling has genuinely stopped — elapsing further must not trigger another call.
      async.elapse(const Duration(seconds: 3));
      drain(async);
      expect(pollCalls, 40);

      cubit.close();
      async.flushTimers();
    });
  });

  test('status polling exceeds max attempts on persistent errors → transient retry', () {
    fakeAsync((async) {
      wireHappyPath();
      var pollCalls = 0;
      when(() => payService.getPayStatus('pl_abc')).thenAnswer((_) async {
        pollCalls++;
        throw Exception('rpc 503');
      });

      final cubit = build();
      cubit.start();
      drain(async);
      expect(cubit.state, isA<PayProcessAwaitingSettlement>());

      // 40 polls @ 3s, each throwing — the 40th hits the max-attempts cap via the catch path.
      for (var i = 0; i < 40; i++) {
        async.elapse(const Duration(seconds: 3));
        drain(async);
      }

      final state = cubit.state as PayProcessPayRetry;
      expect(state.reason, PayRetryReason.transient);
      expect(state.message, 'status polling exceeded max attempts');
      expect(pollCalls, 40);

      cubit.close();
      async.flushTimers();
    });
  });

  test('low ETH balance → faucet → eth polling crosses threshold → swap proceeds', () async {
    fakeAsync((async) {
      wireHappyPath();
      when(
        () => payService.getSwapPaymentInfo(any()),
      ).thenAnswer((_) async => _swap(ethBalance: 0, requiredGasEth: 0.001));
      when(
        () => faucet.requestFaucet(),
      ).thenAnswer((_) async => const FaucetResponseDto(txId: '0xf', amount: 0.01));
      var balanceCall = 0;
      when(() => blockchain.getEthBalance(any())).thenAnswer((_) async {
        balanceCall++;
        return balanceCall == 1 ? 0.0 : 0.01;
      });
      when(() => payService.getPayStatus('pl_abc')).thenAnswer(
        (_) async => const RealUnitOcpPayStatusDto(status: OcpPaymentStatus.completed),
      );

      final cubit = build();
      cubit.start();
      drain(async);
      expect(cubit.state, isA<PayProcessWaitingForEth>());

      // 1st eth poll @ 5s — still 0.
      async.elapse(const Duration(seconds: 5));
      drain(async);
      expect(cubit.state, isA<PayProcessWaitingForEth>());

      // 2nd eth poll @ 10s — funded → swap runs through to settlement polling.
      async.elapse(const Duration(seconds: 5));
      drain(async);
      expect(cubit.state, isA<PayProcessAwaitingSettlement>());

      // status poll completes the flow.
      async.elapse(const Duration(seconds: 3));
      drain(async);
      expect(cubit.state, isA<PayProcessSuccess>());

      cubit.close();
      async.flushTimers();
    });
  });

  test('eth polling ignores a transient balance-check error then proceeds once funded', () {
    fakeAsync((async) {
      wireHappyPath();
      when(
        () => payService.getSwapPaymentInfo(any()),
      ).thenAnswer((_) async => _swap(ethBalance: 0, requiredGasEth: 0.001));
      when(
        () => faucet.requestFaucet(),
      ).thenAnswer((_) async => const FaucetResponseDto(txId: '0xf', amount: 0.01));
      var balanceCall = 0;
      when(() => blockchain.getEthBalance(any())).thenAnswer((_) async {
        balanceCall++;
        if (balanceCall == 1) throw Exception('rpc 503');
        return 0.01;
      });
      when(() => payService.getPayStatus('pl_abc')).thenAnswer(
        (_) async => const RealUnitOcpPayStatusDto(status: OcpPaymentStatus.completed),
      );

      final cubit = build();
      cubit.start();
      drain(async);
      expect(cubit.state, isA<PayProcessWaitingForEth>());

      // 1st eth poll @ 5s — balance check throws; must not get stuck, keeps polling.
      async.elapse(const Duration(seconds: 5));
      drain(async);
      expect(cubit.state, isA<PayProcessWaitingForEth>());

      // 2nd eth poll @ 10s — funded → swap proceeds to settlement polling.
      async.elapse(const Duration(seconds: 5));
      drain(async);
      expect(cubit.state, isA<PayProcessAwaitingSettlement>());

      cubit.close();
      async.flushTimers();
    });
  });

  test('eth polling exceeds max attempts while balance stays short → insufficientEth', () {
    fakeAsync((async) {
      wireHappyPath();
      when(
        () => payService.getSwapPaymentInfo(any()),
      ).thenAnswer((_) async => _swap(ethBalance: 0, requiredGasEth: 0.001));
      when(
        () => faucet.requestFaucet(),
      ).thenAnswer((_) async => const FaucetResponseDto(txId: '0xf', amount: 0.01));
      var balanceCalls = 0;
      when(() => blockchain.getEthBalance(any())).thenAnswer((_) async {
        balanceCalls++;
        return 0.0; // never crosses requiredGasEth
      });

      final cubit = build();
      cubit.start();
      drain(async);
      expect(cubit.state, isA<PayProcessWaitingForEth>());

      // 24 polls @ 5s, each still short — the 24th hits the max-attempts cap.
      for (var i = 0; i < 24; i++) {
        async.elapse(const Duration(seconds: 5));
        drain(async);
      }

      final state = cubit.state as PayProcessFailure;
      expect(state.reason, PayProcessFailureReason.insufficientEth);
      expect(cubit.debugSwapInFlight, isFalse);
      expect(state.message, 'eth balance polling exceeded max attempts');
      expect(balanceCalls, 24);

      // Polling has genuinely stopped — elapsing further must not trigger another call.
      async.elapse(const Duration(seconds: 5));
      drain(async);
      expect(balanceCalls, 24);
      // Swap must never have been attempted after the cap.
      verifyNever(() => payService.createSwapUnsignedTransaction(any()));

      cubit.close();
      async.flushTimers();
    });
  });

  test('closing the cubit mid eth-poll-tick still releases the guard via finally', () {
    fakeAsync((async) {
      wireHappyPath();
      when(
        () => payService.getSwapPaymentInfo(any()),
      ).thenAnswer((_) async => _swap(ethBalance: 0, requiredGasEth: 0.001));
      when(
        () => faucet.requestFaucet(),
      ).thenAnswer((_) async => const FaucetResponseDto(txId: '0xf', amount: 0.01));
      final balanceCompleter = Completer<double>();
      when(() => blockchain.getEthBalance(any())).thenAnswer((_) => balanceCompleter.future);

      final cubit = build();
      cubit.start();
      drain(async);
      expect(cubit.state, isA<PayProcessWaitingForEth>());

      // Trigger the first eth-poll tick; it awaits getEthBalance, which never completes yet.
      async.elapse(const Duration(seconds: 5));
      drain(async);
      expect(cubit.debugSwapInFlight, isTrue);

      // Close the cubit while the tick is still in-flight, then let the pending balance future
      // resolve — the tick resumes into `if (isClosed) return;`, which must still release the
      // guard via `finally`.
      cubit.close();
      balanceCompleter.complete(0.0);
      drain(async);

      expect(cubit.debugSwapInFlight, isFalse);
      async.flushTimers();
    });
  });

  test('hung getEthBalance is unwound by per-request timeout and still hits max attempts', () {
    fakeAsync((async) {
      wireHappyPath();
      when(
        () => payService.getSwapPaymentInfo(any()),
      ).thenAnswer((_) async => _swap(ethBalance: 0, requiredGasEth: 0.001));
      when(
        () => faucet.requestFaucet(),
      ).thenAnswer((_) async => const FaucetResponseDto(txId: '0xf', amount: 0.01));
      var balanceCalls = 0;
      when(() => blockchain.getEthBalance(any())).thenAnswer((_) {
        balanceCalls++;
        // Never completes — only `.timeout(_ethPollTimeout)` (10s) unwedges the tick.
        return Completer<double>().future;
      });

      final cubit = build();
      cubit.start();
      drain(async);
      expect(cubit.state, isA<PayProcessWaitingForEth>());

      // Cadence under fakeAsync: tick @5s starts attempt 1; its 10s timeout and
      // the next periodic may interleave such that a free tick is only every
      // ~15s (periodic can fire while still in-flight, then timeout frees).
      // 24 attempts ⇒ up to ~360s virtual time. Step in 5s until failure.
      for (var i = 0; i < 100 && cubit.state is! PayProcessFailure; i++) {
        async.elapse(const Duration(seconds: 5));
        drain(async);
      }

      final state = cubit.state as PayProcessFailure;
      expect(state.reason, PayProcessFailureReason.insufficientEth);
      expect(state.message, 'eth balance polling exceeded max attempts');
      expect(balanceCalls, 24);

      cubit.close();
      async.flushTimers();
    });
  });

  test('faucet request failure → insufficientEth', () async {
    when(
      () => payService.getSwapPaymentInfo(any()),
    ).thenAnswer((_) async => _swap(ethBalance: 0, requiredGasEth: 0.001));
    when(() => faucet.requestFaucet()).thenThrow(Exception('faucet down'));

    final cubit = build();
    final failed = cubit.stream.firstWhere((s) => s is PayProcessFailure);
    await cubit.start();
    final state = await failed as PayProcessFailure;

    expect(state.reason, PayProcessFailureReason.insufficientEth);
    await cubit.close();
  });

  test('UnsupportedError while signing → signatureUnsupported', () async {
    wireHappyPath();
    // Wallet reports software type (passes the start() gate) but the credentials
    // throw UnsupportedError on sign — exercises the in-sign defensive guard.
    when(() => account.primaryAddress).thenReturn(_UnsupportedCreds());

    final cubit = build();
    final failed = cubit.stream.firstWhere((s) => s is PayProcessFailure);
    await cubit.start();
    final state = await failed as PayProcessFailure;

    expect(state.reason, PayProcessFailureReason.signatureUnsupported);
    await cubit.close();
  });

  test('swap quote fetch failure → generic', () async {
    when(() => payService.getSwapPaymentInfo(any())).thenThrow(Exception('api 500'));

    final cubit = build();
    final failed = cubit.stream.firstWhere((s) => s is PayProcessFailure);
    await cubit.start();
    final state = await failed as PayProcessFailure;

    expect(state.reason, PayProcessFailureReason.generic);
    await cubit.close();
  });

  test('BitBox disconnect during the swap sign → bitboxRequired', () async {
    wireHappyPath();
    when(() => account.primaryAddress).thenReturn(
      FakeBitboxCredentials(behavior: FakeBitboxBehavior.disconnect, signDelay: Duration.zero),
    );

    final cubit = build();
    final failed = cubit.stream.firstWhere((s) => s is PayProcessFailure);
    await cubit.start();
    final state = await failed as PayProcessFailure;

    expect(state.reason, PayProcessFailureReason.bitboxRequired);
    await cubit.close();
  });

  test('generic sign failure during the swap → generic', () async {
    wireHappyPath();
    when(() => account.primaryAddress).thenReturn(
      FakeBitboxCredentials(behavior: FakeBitboxBehavior.malformed, signDelay: Duration.zero),
    );

    final cubit = build();
    final failed = cubit.stream.firstWhere((s) => s is PayProcessFailure);
    await cubit.start();
    final state = await failed as PayProcessFailure;

    expect(state.reason, PayProcessFailureReason.generic);
    await cubit.close();
  });

  test('transient quote re-fetch failure after swap → retry (not re-scan)', () async {
    wireHappyPath();
    when(() => payService.getPaymentDetails('pl_abc')).thenThrow(Exception('lnurlp 500'));

    final cubit = build();
    final retry = cubit.stream.firstWhere((s) => s is PayProcessPayRetry);
    await cubit.start();
    final state = await retry as PayProcessPayRetry;

    // A transient fetch error is NOT a genuine expiry — it routes to the
    // pay-only retry, never to a re-scan → re-swap.
    expect(state.reason, PayRetryReason.transient);
    await cubit.close();
  });

  test('BitBox disconnect during the pay sign (after swap) → pay-only retry', () async {
    wireHappyPath();
    // First sign (swap) succeeds; the second sign (pay) reports a dropped BLE
    // link. Because the swap already happened, this is a retryable pay-leg
    // failure rather than a terminal one.
    final creds = _CountingSignCreds(
      throwOnCall: 2,
      error: const BitboxNotConnectedException(),
    );
    when(() => account.primaryAddress).thenReturn(creds);

    final cubit = build();
    final retry = cubit.stream.firstWhere((s) => s is PayProcessPayRetry);
    await cubit.start();
    final state = await retry as PayProcessPayRetry;

    expect(creds.calls, 2);
    expect(state.reason, PayRetryReason.transient);
    await cubit.close();
  });

  test('insufficient ZCHF after swap (fresh amount > acquired) → typed retry', () async {
    wireHappyPath();
    // Swap acquires estimatedAmount=960 ZCHF, but the fresh quote now demands
    // 1000 ZCHF — more than was swapped. Surface the typed, retryable state.
    when(() => payService.getPaymentDetails('pl_abc')).thenAnswer(
      (_) async => _details(
        expiration: DateTime.now().add(const Duration(minutes: 5)),
        zchf: 1000,
      ),
    );

    final cubit = build();
    final retry = cubit.stream.firstWhere((s) => s is PayProcessPayRetry);
    await cubit.start();
    final state = await retry as PayProcessPayRetry;

    expect(state.reason, PayRetryReason.insufficientZchf);
    // The pay leg is never attempted — the swapped ZCHF stays in the wallet.
    verifyNever(() => payService.createPayUnsignedTransaction(any()));
    await cubit.close();
  });

  test('insufficient ZCHF with rawAmount uses exact plain-decimal comparison', () async {
    wireHappyPath();
    // Swap acquires estimatedAmount=960. Fresh quote carries rawAmount '1000'
    // (exact string path) — must hit the plain-decimal branch, not only double `>`.
    when(() => payService.getPaymentDetails('pl_abc')).thenAnswer(
      (_) async => LnurlpPaymentDto(
        requestedAmount: const LnurlpRequestedAmountDto(asset: 'CHF', amount: 42.5),
        quote: LnurlpQuoteDto(
          id: 'quote_fresh',
          expiration: DateTime.now().add(const Duration(minutes: 5)),
        ),
        transferAmounts: [
          const LnurlpTransferAmountDto(
            method: 'Ethereum',
            assets: [
              LnurlpTransferAssetDto(
                asset: 'ZCHF',
                amount: 1000,
                rawAmount: '1000',
              ),
            ],
          ),
        ],
      ),
    );

    final cubit = build();
    final retry = cubit.stream.firstWhere((s) => s is PayProcessPayRetry);
    await cubit.start();
    final state = await retry as PayProcessPayRetry;

    expect(state.reason, PayRetryReason.insufficientZchf);
    verifyNever(() => payService.createPayUnsignedTransaction(any()));
    await cubit.close();
  });

  test('malformed rawAmount fail-closed retries (never treats as OK)', () async {
    wireHappyPath();
    // rawAmount is scientific notation → FormatException on plain-decimal parse →
    // fail closed (cannot prove exact coverage) rather than falling back to a
    // rounding-prone double comparison. Outcome here still retries; amount 1000
    // > acquired 960 would also have been true under the old double path, so
    // this is a regression pin that the path still retries after the fix.
    when(() => payService.getPaymentDetails('pl_abc')).thenAnswer(
      (_) async => LnurlpPaymentDto(
        requestedAmount: const LnurlpRequestedAmountDto(asset: 'CHF', amount: 42.5),
        quote: LnurlpQuoteDto(
          id: 'quote_fresh',
          expiration: DateTime.now().add(const Duration(minutes: 5)),
        ),
        transferAmounts: [
          const LnurlpTransferAmountDto(
            method: 'Ethereum',
            assets: [
              LnurlpTransferAssetDto(
                asset: 'ZCHF',
                amount: 1000,
                rawAmount: '1e3',
              ),
            ],
          ),
        ],
      ),
    );

    final cubit = build();
    final retry = cubit.stream.firstWhere((s) => s is PayProcessPayRetry);
    await cubit.start();
    final state = await retry as PayProcessPayRetry;

    expect(state.reason, PayRetryReason.insufficientZchf);
    verifyNever(() => payService.createPayUnsignedTransaction(any()));
    await cubit.close();
  });

  test('non-plain-decimal fresh amount that would look covered by double comparison still retries '
      '(fail-closed)', () async {
    wireHappyPath();
    // Swap acquires estimatedAmount=960. Fresh settlement amount is 900 (a plain double LESS than
    // 960 — the old double `>` fallback would say "not exceeding", i.e. wrongly "covered"), but
    // rawAmount is scientific notation ('9e2') so no exact plain-decimal comparison is possible.
    // The fix must NOT fall back to the double comparison here — it must fail closed and retry,
    // proving the conservative `true` return, not merely coincide with what double comparison
    // would already have said.
    when(() => payService.getPaymentDetails('pl_abc')).thenAnswer(
      (_) async => LnurlpPaymentDto(
        requestedAmount: const LnurlpRequestedAmountDto(asset: 'CHF', amount: 42.5),
        quote: LnurlpQuoteDto(
          id: 'quote_fresh',
          expiration: DateTime.now().add(const Duration(minutes: 5)),
        ),
        transferAmounts: [
          const LnurlpTransferAmountDto(
            method: 'Ethereum',
            assets: [
              LnurlpTransferAssetDto(
                asset: 'ZCHF',
                amount: 900,
                rawAmount: '9e2',
              ),
            ],
          ),
        ],
      ),
    );

    final cubit = build();
    final retry = cubit.stream.firstWhere((s) => s is PayProcessPayRetry);
    await cubit.start();
    final state = await retry as PayProcessPayRetry;

    expect(state.reason, PayRetryReason.insufficientZchf);
    verifyNever(() => payService.createPayUnsignedTransaction(any()));
    await cubit.close();
  });

  test('missing rawAmount fails closed even when the double amount would look covered', () async {
    wireHappyPath();
    // amount 900 < acquired 960 — double comparison would say "covered". rawAmount is null so
    // exact plain-decimal coverage cannot be proven; fail closed and retry.
    when(() => payService.getPaymentDetails('pl_abc')).thenAnswer(
      (_) async => LnurlpPaymentDto(
        requestedAmount: const LnurlpRequestedAmountDto(asset: 'CHF', amount: 42.5),
        quote: LnurlpQuoteDto(
          id: 'quote_fresh',
          expiration: DateTime.now().add(const Duration(minutes: 5)),
        ),
        transferAmounts: [
          const LnurlpTransferAmountDto(
            method: 'Ethereum',
            assets: [
              LnurlpTransferAssetDto(
                asset: 'ZCHF',
                amount: 900,
              ),
            ],
          ),
        ],
      ),
    );

    final cubit = build();
    final retry = cubit.stream.firstWhere((s) => s is PayProcessPayRetry);
    await cubit.start();
    final state = await retry as PayProcessPayRetry;

    expect(state.reason, PayRetryReason.insufficientZchf);
    verifyNever(() => payService.createPayUnsignedTransaction(any()));
    await cubit.close();
  });

  test('retryPay re-runs the pay leg only — never re-swaps', () async {
    wireHappyPath();
    // First pass: quote re-fetch throws → PayProcessPayRetry.
    var detailsCall = 0;
    when(() => payService.getPaymentDetails('pl_abc')).thenAnswer((_) async {
      detailsCall++;
      if (detailsCall == 1) throw Exception('lnurlp 500');
      return _details(expiration: DateTime.now().add(const Duration(minutes: 5)));
    });
    when(() => payService.getPayStatus('pl_abc')).thenAnswer(
      (_) async => const RealUnitOcpPayStatusDto(status: OcpPaymentStatus.completed),
    );

    final cubit = build();
    final retry = cubit.stream.firstWhere((s) => s is PayProcessPayRetry);
    await cubit.start();
    await retry;
    expect(cubit.state, isA<PayProcessPayRetry>());

    // Retry the pay leg: it must re-fetch the quote + submit WITHOUT re-swapping.
    final settled = cubit.stream.firstWhere((s) => s is PayProcessAwaitingSettlement);
    await cubit.retryPay();
    await settled;

    expect(cubit.state, isA<PayProcessAwaitingSettlement>());
    // The swap legs ran EXACTLY ONCE over the whole flow — the retry reused the
    // already-acquired ZCHF and never re-swapped (the key fund-safety guarantee).
    verify(() => payService.createSwapUnsignedTransaction(any())).called(1);
    verify(() => payService.broadcastSwapTransaction(any(), any())).called(1);
    // The pay leg's submit ran once (only on the successful retry).
    verify(() => payService.submitPay(any())).called(1);
    await cubit.close();
  });

  test('retryPay is a no-op before a swap has completed', () async {
    wireHappyPath();

    final cubit = build();
    // Never started → swap not completed → retry must not touch the network.
    await cubit.retryPay();

    verifyNever(() => payService.getPaymentDetails(any()));
    await cubit.close();
  });

  test('non-signing wallet detected only at the pay sign (after swap) → retry', () async {
    wireHappyPath();
    // Swap sign succeeds; the pay sign hits a non-signing credential
    // (UnsupportedError). Post-swap, this is a retryable pay-leg failure.
    final creds = _CountingSignCreds(
      throwOnCall: 2,
      error: UnsupportedError('cannot sign'),
    );
    when(() => account.primaryAddress).thenReturn(creds);

    final cubit = build();
    final retry = cubit.stream.firstWhere((s) => s is PayProcessPayRetry);
    await cubit.start();
    final state = await retry as PayProcessPayRetry;

    expect(creds.calls, 2);
    expect(state.reason, PayRetryReason.transient);
    await cubit.close();
  });
}

/// Credentials that produce a real signature for every sign except the
/// [throwOnCall]-th, which throws [error]. Lets a test target the swap (call 1)
/// vs. the pay (call 2) sign deterministically.
class _CountingSignCreds extends Fake implements CredentialsWithKnownAddress {
  _CountingSignCreds({required this.throwOnCall, required this.error});

  final int throwOnCall;
  final Object error;
  int calls = 0;

  @override
  EthereumAddress get address =>
      EthereumAddress.fromHex('0x9F5713dEAcb8e9CaB6c2D3FaE1aFc2715F8D2D71');

  @override
  Future<MsgSignature> signToSignature(
    Uint8List payload, {
    int? chainId,
    bool isEIP1559 = false,
  }) async {
    calls++;
    if (calls == throwOnCall) throw error;
    return EthPrivateKey.fromHex(
      'fb1ace12f9801e85f3db1b3935dd47d9f064f98152466f47c701b5e12680e612',
    ).signToSignature(payload, chainId: chainId, isEIP1559: isEIP1559);
  }
}
