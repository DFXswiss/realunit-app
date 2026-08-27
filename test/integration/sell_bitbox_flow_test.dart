// Cross-layer integration tests for the BitBox sell flow.
//
// These tests stitch together three layers that the BitBox sell ceremony
// touches end-to-end, all of which have had production regressions in the
// past two months (PR #322, #338, #341, #514):
//
//   SellBitboxCubit
//     → FakeBitboxCredentials.signToSignature (BitBox boundary, no real
//       BLE/USB stack — controllable success/cancel/disconnect/malformed)
//     → RealUnitSellPaymentInfoService (real production class)
//     → MockClient (last-mile HTTP boundary stand-in)
//
// We deliberately wire up the real RealUnitSellPaymentInfoService instead of
// stubbing it — the goal is to pin the failure-handling contract between the
// cubit and the service (state transitions on swap-OK + deposit-fail, etc.)
// AND the wire-format the service produces on success. A regression in the
// service that broke either contract has shipped to production twice; both
// would be caught by these tests.
//
// They run headless (no device, no simulator), so they live under
// `test/integration/` and run as part of `flutter test`.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/config/api_config.dart';
import 'package:realunit_wallet/packages/config/network_mode.dart';
import 'package:realunit_wallet/packages/repository/cache_repository.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_blockchain_api_service.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_faucet_service.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/dto/eip7702/eip7702_data_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/dto/real_unit_sell_payment_info_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/sell_payment_info.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_sell_payment_info_service.dart';
import 'package:realunit_wallet/packages/service/session_cache.dart';
import 'package:realunit_wallet/packages/service/wallet_service.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';
import 'package:realunit_wallet/packages/wallet/wallet_account.dart';
import 'package:realunit_wallet/screens/sell_bitbox/cubit/sell_bitbox_cubit.dart';
import 'package:realunit_wallet/styles/currency.dart';

import '../helper/fake_bitbox_credentials.dart';

class _MockFaucet extends Mock implements DfxFaucetService {}

class _MockBlockchain extends Mock implements DfxBlockchainApiService {}

class _MockAppStore extends Mock implements AppStore {}

class _MockWallet extends Mock implements AWallet {}

class _MockWalletAccount extends Mock implements AWalletAccount {}

class _MockWalletService extends Mock implements WalletService {}

class _MockCacheRepository extends Mock implements CacheRepository {}

// The eip7702 sub-object is required by SellPaymentInfo but is not exercised
// by the BitBox sell path (BitBox uses the txHash branch, software wallets
// use the eip7702 branch — `confirmPaymentWithTxHash` takes only the hash).
// We still need a syntactically valid envelope so SellPaymentInfo.fromJson
// stays happy.
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

// Arbitrary EIP-1559 raw bytes. The deterministic test private key inside
// FakeBitboxCredentials signs them, so we don't need a real RLP-encoded tx —
// the cubit just hex-decodes, calls signToSignature, repacks (r, s, v).
const _rawSwap = '0xdeadbeef';
const _rawDeposit = '0xcafebabe';

void main() {
  late _MockFaucet faucet;
  late _MockBlockchain blockchain;
  late _MockAppStore appStore;
  late _MockWallet wallet;
  late _MockWalletAccount account;
  late _MockWalletService walletService;
  late SessionCache session;
  late FakeBitboxCredentials creds;

  setUp(() {
    faucet = _MockFaucet();
    blockchain = _MockBlockchain();
    appStore = _MockAppStore();
    wallet = _MockWallet();
    account = _MockWalletAccount();
    walletService = _MockWalletService();
    session = SessionCache(_MockCacheRepository());
    // Pre-seed an auth token so the service skips its sign-message round-trip.
    session.setAuthToken('jwt-test');

    creds = FakeBitboxCredentials(signDelay: Duration.zero);

    when(() => appStore.wallet).thenReturn(wallet);
    when(
      () => appStore.apiConfig,
    ).thenReturn(const ApiConfig(networkMode: NetworkMode.mainnet));
    when(() => appStore.sessionCache).thenReturn(session);
    when(() => appStore.primaryAddress).thenReturn(creds.address.hexEip55);
    when(() => wallet.currentAccount).thenReturn(account);
    when(() => account.primaryAddress).thenReturn(creds);
    when(() => walletService.ensureCurrentWalletUnlocked()).thenAnswer((_) async {});
    when(() => walletService.lockCurrentWallet()).thenAnswer((_) async {});
  });

  // Build a real [RealUnitSellPaymentInfoService] backed by [client]. The cubit
  // talks to this service object — there is no service-level stub between the
  // cubit and the HTTP boundary.
  RealUnitSellPaymentInfoService buildSellService(http.Client client) {
    when(() => appStore.httpClient).thenReturn(client);
    return RealUnitSellPaymentInfoService(appStore, walletService);
  }

  SellBitboxCubit buildCubit(RealUnitSellPaymentInfoService sellService) => SellBitboxCubit(
    paymentInfo: _info(),
    faucetService: faucet,
    blockchainService: blockchain,
    sellService: sellService,
    appStore: appStore,
  )..start();

  // Waits for start()'s first non-Checking emit and asserts it is EthReady —
  // the precondition every flow test in this file shares.
  Future<void> settleToEthReady(SellBitboxCubit cubit) async {
    final state = await cubit.stream.firstWhere((s) => s is! SellBitboxCheckingEth);
    expect(
      state,
      isA<SellBitboxEthReady>(),
      reason:
          'fixture has ethBalance > requiredGasEth and a connected FakeBitbox; '
          '_checkEthBalance should land in SellBitboxEthReady',
    );
  }

  group('sell flow cross-layer: cubit → BitBox boundary → service → MockClient', () {
    test(
      'happy: full swap + deposit broadcast with FakeBitboxBehavior.success',
      () async {
        // Script the server: unsigned txs → swap broadcast → deposit broadcast → confirm.
        // The service is real; the MockClient is the last-mile substitute for
        // the network. Asserts go on the side-effects of the real service,
        // not on the stubbed sellService.
        var unsignedCalls = 0;
        var broadcastCalls = 0;
        var confirmCalls = 0;
        final broadcastBodies = <Map<String, dynamic>>[];

        final client = MockClient((request) async {
          if (request.url.path.endsWith('/unsigned-transactions')) {
            unsignedCalls++;
            return http.Response(
              jsonEncode({'swap': _rawSwap, 'deposit': _rawDeposit}),
              200,
            );
          }
          if (request.url.path.endsWith('/broadcast')) {
            broadcastCalls++;
            broadcastBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
            // Deposit broadcast is the third broadcast (swap top-of-confirmDeposit,
            // swap-inside-helper, deposit-inside-helper). Production code makes
            // TWO broadcast calls actually — pin via the captured bodies below.
            return http.Response(jsonEncode({'txHash': '0xtx-$broadcastCalls'}), 200);
          }
          if (request.url.path.endsWith('/confirm')) {
            confirmCalls++;
            return http.Response('{}', 200);
          }
          fail('unexpected request: ${request.url}');
        });

        final cubit = buildCubit(buildSellService(client));
        await settleToEthReady(cubit);

        await cubit.proceedToSwap();
        expect(cubit.state, isA<SellBitboxAwaitingSwapConfirm>());

        await cubit.confirmSwap();
        expect(cubit.state, isA<SellBitboxAwaitingDepositConfirm>());

        await cubit.confirmDeposit();
        expect(cubit.state, isA<SellBitboxSuccess>());

        // Two BitBox sign calls: swap + deposit. A regression that
        // double-signed (e.g. retried inside the cubit on a transient
        // exception) would surface here, not in production.
        expect(creds.signCallCount, 2);

        // Wire shape: one unsigned-txs, two broadcasts (swap + deposit),
        // one confirm — the cubit MUST broadcast the swap first then the
        // deposit, otherwise the backend rejects the second-leg.
        expect(unsignedCalls, 1);
        expect(broadcastCalls, 2);
        expect(confirmCalls, 1);
        expect(broadcastBodies[0]['unsignedTx'], _rawSwap);
        expect(broadcastBodies[1]['unsignedTx'], _rawDeposit);
        // Signatures must be hex strings of the right shape — the cubit
        // pads the (r, s) BigInts to 32 bytes each.
        expect((broadcastBodies[0]['r'] as String).length, 66);
        expect((broadcastBodies[0]['s'] as String).length, 66);

        await cubit.close();
      },
    );

    test(
      'cancel: FakeBitboxBehavior.cancel mid-swap → cubit settles in SellBitboxError',
      () async {
        // FakeBitboxCredentials.signToSignature throws SigningCancelledException
        // on cancel. The cubit's catch (e) clause swallows that into a
        // SellBitboxError carrying the exception's toString. This pins the
        // path that a cancelled-on-device sign does NOT silently succeed
        // (regression class: empty signature accepted as valid).
        final client = MockClient((request) async {
          if (request.url.path.endsWith('/unsigned-transactions')) {
            return http.Response(
              jsonEncode({'swap': _rawSwap, 'deposit': _rawDeposit}),
              200,
            );
          }
          fail(
            'cancel path must not reach broadcast/confirm — '
            'unexpected request: ${request.url}',
          );
        });

        final cubit = buildCubit(buildSellService(client));
        await settleToEthReady(cubit);
        await cubit.proceedToSwap();

        creds.behavior = FakeBitboxBehavior.cancel;
        await cubit.confirmSwap();

        final state = cubit.state as SellBitboxError;
        expect(state.message, contains('SigningCancelledException'));
        // Cancel must NOT consume more than the one attempted sign — a
        // regression that auto-retried on cancel would surface as 2 here.
        expect(creds.signCallCount, 1);

        await cubit.close();
      },
    );

    test(
      'disconnect: FakeBitboxBehavior.disconnect → BitboxNotConnectedException → SellBitboxBitboxRequired',
      () async {
        final client = MockClient((request) async {
          if (request.url.path.endsWith('/unsigned-transactions')) {
            return http.Response(
              jsonEncode({'swap': _rawSwap, 'deposit': _rawDeposit}),
              200,
            );
          }
          fail(
            'disconnect path must not reach broadcast/confirm — '
            'unexpected request: ${request.url}',
          );
        });

        final cubit = buildCubit(buildSellService(client));
        await settleToEthReady(cubit);
        await cubit.proceedToSwap();

        creds.behavior = FakeBitboxBehavior.disconnect;
        await cubit.confirmSwap();

        // The cubit must catch BitboxNotConnectedException EXPLICITLY (typed
        // catch) and emit SellBitboxBitboxRequired so the UI can re-pair —
        // a generic catch (e) would land in SellBitboxError and the user
        // would see a raw "BitBox is not connected" string instead of the
        // re-pair screen.
        expect(cubit.state, isA<SellBitboxBitboxRequired>());

        await cubit.close();
      },
    );

    test(
      'malformed-sig: FakeBitboxBehavior.malformed → typed error in cubit (SellBitboxError)',
      () async {
        // FakeBitboxCredentials.signToSignature throws FormatException on
        // malformed mode (mimicking a frame-desync regression upstream).
        // The cubit's generic catch (e) maps it to SellBitboxError —
        // critically NOT to SellBitboxBitboxRequired (would mask a sig bug
        // as a UX disconnect prompt) and NOT silently to a "successful" sign
        // (would broadcast garbage and the backend would reject).
        final client = MockClient((request) async {
          if (request.url.path.endsWith('/unsigned-transactions')) {
            return http.Response(
              jsonEncode({'swap': _rawSwap, 'deposit': _rawDeposit}),
              200,
            );
          }
          fail(
            'malformed path must not reach broadcast/confirm — '
            'unexpected request: ${request.url}',
          );
        });

        final cubit = buildCubit(buildSellService(client));
        await settleToEthReady(cubit);
        await cubit.proceedToSwap();

        creds.behavior = FakeBitboxBehavior.malformed;
        await cubit.confirmSwap();

        final state = cubit.state as SellBitboxError;
        expect(state.message, contains('Malformed'));
        // It must NOT have been re-classified as a BitBox disconnect.
        expect(cubit.state, isNot(isA<SellBitboxBitboxRequired>()));

        await cubit.close();
      },
    );

    test(
      'deposit-retry: swap OK + deposit broadcast 5xx → SellBitboxDepositRetry preserves both signed envelopes',
      () async {
        // This pins the bug class behind PR #338: a transient RPC failure on
        // the deposit broadcast must NOT lose the already-signed swap+deposit.
        // Losing them would force the user to re-confirm on the device twice
        // (worst case: a partial swap with no follow-up deposit). The retry
        // state must carry both signed envelopes verbatim.
        var broadcastCalls = 0;
        final client = MockClient((request) async {
          if (request.url.path.endsWith('/unsigned-transactions')) {
            return http.Response(
              jsonEncode({'swap': _rawSwap, 'deposit': _rawDeposit}),
              200,
            );
          }
          if (request.url.path.endsWith('/broadcast')) {
            broadcastCalls++;
            // First broadcast (swap top-of-confirmDeposit) returns OK;
            // second broadcast (deposit inside helper) explodes with 502.
            if (broadcastCalls == 2) {
              return http.Response(
                jsonEncode({'statusCode': 502, 'code': 'BAD_GATEWAY', 'message': 'rpc 502'}),
                502,
              );
            }
            return http.Response(jsonEncode({'txHash': '0xswaphash'}), 200);
          }
          fail('confirm must not be reached on deposit-fail: ${request.url}');
        });

        final cubit = buildCubit(buildSellService(client));
        await settleToEthReady(cubit);
        await cubit.proceedToSwap();
        await cubit.confirmSwap();
        await cubit.confirmDeposit();

        // The cubit must NOT have advanced to SellBitboxSuccess on a
        // mid-flight broadcast failure — losing the signed envelopes would
        // be a silent funds-at-risk regression.
        final state = cubit.state as SellBitboxDepositRetry;
        expect(state.signedSwapTransaction.unsignedTx, _rawSwap);
        expect(state.signedDepositTransaction.unsignedTx, _rawDeposit);
        expect(state.errorMessage, contains('rpc 502'));
        // The signatures must have survived intact — same shape as in the
        // happy path. A regression that dropped them to '0x' would mean the
        // user has to re-sign on the device.
        expect(state.signedSwapTransaction.r.length, 66);
        expect(state.signedDepositTransaction.r.length, 66);
        // Two BitBox sign calls only — the retry must not have triggered an
        // extra sign yet (that happens on retryDeposit).
        expect(creds.signCallCount, 2);

        await cubit.close();
      },
    );

    // Pins the low-ETH path this file's other happy path skips: ethBalance
    // below requiredGasEth → DFX API faucet → balance poll → full sell.
    // The faucet HTTP response is held behind a Completer so the test can
    // prove the cubit awaits requestFaucet() before installing the 5s poll.
    test(
      'happy: faucet hop then full swap + deposit when ethBalance < requiredGasEth',
      () {
        fakeAsync((async) {
          void drain() {
            for (var i = 0; i < 40; i++) {
              async.flushMicrotasks();
              async.elapse(Duration.zero);
            }
          }

          var faucetCalls = 0;
          String? faucetPath;
          var faucetCompleted = false;
          final faucetResponse = Completer<http.Response>();
          var balancesCalls = 0;
          Map<String, dynamic>? balancesBody;
          var unsignedCalls = 0;
          var broadcastCalls = 0;
          var confirmCalls = 0;
          final broadcastBodies = <Map<String, dynamic>>[];

          final client = MockClient((request) async {
            final path = request.url.path;
            if (request.method == 'POST' && path == '/v1/faucet') {
              faucetCalls++;
              faucetPath = path;
              return faucetResponse.future;
            }
            if (request.method == 'POST' && path == '/v1/blockchain/balances') {
              if (!faucetCompleted) {
                fail('balances before faucet completed');
              }
              balancesCalls++;
              balancesBody = jsonDecode(request.body) as Map<String, dynamic>;
              return http.Response(
                jsonEncode({
                  'balances': [
                    {'balance': 0.001},
                  ],
                }),
                200,
              );
            }
            if (path.endsWith('/unsigned-transactions')) {
              if (!faucetCompleted) {
                fail('unsigned-transactions before faucet completed');
              }
              unsignedCalls++;
              return http.Response(
                jsonEncode({'swap': _rawSwap, 'deposit': _rawDeposit}),
                200,
              );
            }
            if (path.endsWith('/broadcast')) {
              if (!faucetCompleted) {
                fail('broadcast before faucet completed');
              }
              broadcastCalls++;
              broadcastBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
              return http.Response(jsonEncode({'txHash': '0xtx-$broadcastCalls'}), 200);
            }
            if (path.endsWith('/confirm')) {
              if (!faucetCompleted) {
                fail('confirm before faucet completed');
              }
              confirmCalls++;
              return http.Response('{}', 200);
            }
            fail('unexpected request: ${request.url}');
          });

          when(() => appStore.httpClient).thenReturn(client);
          final sellService = RealUnitSellPaymentInfoService(appStore, walletService);
          final realFaucet = DfxFaucetService(appStore, walletService);
          final realBlockchain = DfxBlockchainApiService(appStore, walletService);

          final cubit = SellBitboxCubit(
            paymentInfo: _info(ethBalance: 0),
            faucetService: realFaucet,
            blockchainService: realBlockchain,
            sellService: sellService,
            appStore: appStore,
          )..start();

          // Faucet handler entered; cubit still awaiting; poll timer not installed.
          drain();
          expect(faucetCalls, 1);
          expect(faucetPath, '/v1/faucet');
          expect(cubit.state, isA<SellBitboxRequestingFaucet>());

          // Elapsing 5s while faucet is still open must NOT hit balances —
          // that would mean the poll timer was started before requestFaucet returned.
          async.elapse(const Duration(seconds: 5));
          drain();
          expect(balancesCalls, 0);

          faucetCompleted = true;
          faucetResponse.complete(
            http.Response(
              jsonEncode({'txId': '0xfaucet', 'amount': 0.01}),
              200,
            ),
          );
          drain();
          expect(cubit.state, isA<SellBitboxWaitingForEth>());

          async.elapse(const Duration(seconds: 5));
          drain();

          expect(cubit.state, isA<SellBitboxEthReady>());
          expect(balancesCalls, greaterThanOrEqualTo(1));
          expect(balancesBody!['address'], appStore.primaryAddress);
          expect(balancesBody!['blockchain'], 'Ethereum');
          expect(balancesBody!['assetIds'], contains(111));

          cubit.proceedToSwap();
          drain();
          cubit.confirmSwap();
          drain();
          cubit.confirmDeposit();
          drain();

          expect(cubit.state, isA<SellBitboxSuccess>());
          expect(creds.signCallCount, 2);
          expect(unsignedCalls, 1);
          expect(broadcastCalls, 2);
          expect(confirmCalls, 1);
          expect(broadcastBodies[0]['unsignedTx'], _rawSwap);
          expect(broadcastBodies[1]['unsignedTx'], _rawDeposit);

          cubit.close();
          async.flushTimers();
        });
      },
    );
  });
}
