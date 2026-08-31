// Cross-layer integration test for the BitBox reconnect-recovery story.
//
// Three seams come together when a device drops in the middle of a checkout
// and the user re-plugs to retry:
//
//   1. FakeBitboxCredentials — flips behaviour mid-flight so a single
//      credentials instance can simulate success → disconnect → success on
//      a retry, the same arc the real BitBox plugin exposes via mid-sign
//      BLE link drops.
//
//   2. BitboxService observer — periodically probes the simulator-backed
//      platform interface for present devices and clears every active
//      `BitboxCredentials` in place when the device list goes empty. The
//      observer must NOT null the credentials reference (a follow-up
//      `init()` re-attaches the manager via `setBitbox`).
//
//   3. SellBitboxCubit.retryAfterConnection — the cubit-side recovery hook
//      the screen calls after the BitBox-required gate flips back to
//      connected. The cubit re-checks `credentials.isConnected` and emits
//      `SellBitboxEthReady` (or the faucet/error branch) accordingly.
//
// Tests run inside `fakeAsync` so the observer's periodic timer and the
// cubit's start()-scheduled `_checkEthBalance` microtask are both bound to
// the same virtual clock — no wallclock-sleeps, deterministic tick counting.

import 'dart:typed_data';

import 'package:bitbox_flutter/bitbox_flutter.dart';
import 'package:bitbox_flutter/testing.dart';
import 'package:bitbox_flutter/usb/bitbox_usb_platform_interface.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/config/api_config.dart';
import 'package:realunit_wallet/packages/config/network_mode.dart';
import 'package:realunit_wallet/packages/hardware_wallet/bitbox.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_blockchain_api_service.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_faucet_service.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/dto/eip7702/eip7702_data_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/dto/real_unit_sell_payment_info_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/sell_payment_info.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_sell_payment_info_service.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';
import 'package:realunit_wallet/packages/wallet/wallet_account.dart';
import 'package:realunit_wallet/screens/sell_bitbox/cubit/sell_bitbox_cubit.dart';
import 'package:realunit_wallet/styles/currency.dart';

import '../helper/fake_bitbox_credentials.dart';

class _MockFaucet extends Mock implements DfxFaucetService {}

class _MockBlockchain extends Mock implements DfxBlockchainApiService {}

class _MockSellService extends Mock implements RealUnitSellPaymentInfoService {}

class _MockAppStore extends Mock implements AppStore {}

class _MockWallet extends Mock implements AWallet {}

class _MockWalletAccount extends Mock implements AWalletAccount {}

SellPaymentInfo _info({
  double ethBalance = 1.0,
  double requiredGasEth = 0.001,
}) => SellPaymentInfo(
  id: 42,
  eip7702: Eip7702Data.fromJson(const {
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
  }),
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

void main() {
  late BitboxUsbPlatform previousPlatform;
  late SimulatedBitboxPlatform platform;

  // Tight observer cadence so device-loss surfaces in a few virtual ticks
  // instead of the production 5 s default. fakeAsync makes the wall-clock
  // value irrelevant, but keeping it short still tightens the test runtime.
  const fastInterval = Duration(milliseconds: 50);
  const observerSettleTime = Duration(milliseconds: 150);

  const knownAddress = '0x9F5713dEAcb8e9CaB6c2D3FaE1aFc2715F8D2D71';

  setUp(() {
    previousPlatform = BitboxUsbPlatform.instance;
    platform = installSimulatedBitboxPlatform();
  });

  tearDown(() {
    BitboxUsbPlatform.instance = previousPlatform;
  });

  // Pair the service inside an existing fakeAsync zone — the periodic timer
  // the observer installs must be bound to the fake clock so async.elapse
  // pumps it.
  BitboxService pairedServiceSync(FakeAsync async) {
    final service = BitboxService(connectionStatusInterval: fastInterval);
    late List<BitboxDevice> devices;
    service.getAllUsbDevices().then((d) => devices = d);
    async.flushMicrotasks();
    service.init(devices.single);
    async.flushMicrotasks();
    return service;
  }

  group('BitboxCredentials × FakeBitbox mid-sign disconnect-and-retry', () {
    test(
      'flips success → disconnect → success: credentials.isConnected reflects both phases',
      () async {
        // The fake's `behavior` is mutable, which is the whole point — a
        // single instance can simulate a sign that succeeds, then a BLE drop
        // (real `BitboxCredentials.isConnected` flips to false via
        // observer-clear), then a re-pair that brings sign back online. This
        // pins the contract `FakeBitboxCredentials → BitboxCredentials`
        // exposes to the cubit's mid-flow recovery code.
        final fake = FakeBitboxCredentials(signDelay: Duration.zero);

        // Phase 1: device connected, sign succeeds.
        expect(fake.isConnected, isTrue);
        final firstSig = await fake.signPersonalMessage(_payload());
        expect(firstSig.length, greaterThan(0));
        expect(fake.signCallCount, 1);

        // Phase 2: BLE link drops mid-flow → next sign throws disconnect.
        fake.behavior = FakeBitboxBehavior.disconnect;
        expect(
          fake.isConnected,
          isFalse,
          reason: 'disconnect behaviour must surface as isConnected=false',
        );
        await expectLater(
          fake.signPersonalMessage(_payload()),
          throwsA(isA<Exception>()),
        );
        // The throw still incremented the call count — proves the fake
        // actually ran the sign branch instead of short-circuiting on the
        // connection check (the real BitboxCredentials checks connectivity
        // inside `_synchronizeBoundedSign`, not before the call).
        expect(fake.signCallCount, 2);

        // Phase 3: user re-plugs → behaviour flips back, sign succeeds again.
        fake.behavior = FakeBitboxBehavior.success;
        expect(fake.isConnected, isTrue);
        final retrySig = await fake.signPersonalMessage(_payload());
        expect(retrySig.length, greaterThan(0));
        expect(fake.signCallCount, 3);
      },
    );
  });

  group('BitboxService observer × cubit recovery', () {
    test(
      'observer detects device-loss: credentials cleared in place, reference preserved',
      () {
        // Critical to the cubit recovery loop: SellBitboxCubit holds the
        // `BitboxCredentials` reference inside `appStore.wallet.currentAccount
        // .primaryAddress`. The observer must clear connectivity on the
        // existing reference rather than nulling the slot — otherwise a
        // re-init() has nothing to re-attach and the screen stays stuck on
        // SellBitboxBitboxRequired even after the device is back.
        fakeAsync((async) {
          final service = pairedServiceSync(async);
          final credentials = service.getCredentials(knownAddress);

          // Pair-time invariants.
          expect(credentials.isConnected, isTrue);
          expect(credentials.bitboxManager, isNotNull);

          // Device vanishes.
          platform.when(
            SimulatedBitboxMethod.getDevices,
            (_) async => const <BitboxDevice>[],
          );

          service.startConnectionStatusObserver();
          async.elapse(observerSettleTime);

          // After device-loss: the manager is cleared but the credentials
          // instance is still the same object — getCredentials returns it
          // unchanged so the cubit's `is BitboxCredentials` guard still
          // matches the right slot.
          expect(
            credentials.isConnected,
            isFalse,
            reason: 'observer must mark credentials as disconnected',
          );
          expect(
            credentials.bitboxManager,
            isNull,
            reason: 'observer must clear the manager so the next sign fails fast',
          );
          expect(
            service.getCredentials(knownAddress),
            same(credentials),
            reason:
                'observer must not orphan the credentials — same address must keep returning the same instance',
          );

          service.stopConnectionStatusObserver();
        });
      },
    );

    test(
      're-attach after init: credentials produced before pair are promoted by init() and the cubit recovers',
      () {
        // Full cross-layer arc: persisted credentials (built before pairing),
        // pair-via-init promotes them, the cubit's BitboxRequired gate clears
        // on `retryAfterConnection`. Pins the seam SellBitboxCubit relies on
        // — `credentials.isConnected` flipping must be enough to flip the
        // cubit's state without rebuilding the wallet.
        fakeAsync((async) {
          // Step 1: build credentials BEFORE the service is paired.
          final service = BitboxService(connectionStatusInterval: fastInterval);
          final credentials = service.getCredentials(knownAddress);
          expect(
            credentials.isConnected,
            isFalse,
            reason: 'pre-pair credentials must report disconnected',
          );

          // Wire the cubit. Faucet stubbed so the eth-balance branch the
          // cubit takes on the retry is the cheap one (no auth round-trip).
          final faucet = _MockFaucet();
          final blockchain = _MockBlockchain();
          final sellService = _MockSellService();
          final appStore = _MockAppStore();
          final wallet = _MockWallet();
          final account = _MockWalletAccount();

          when(() => appStore.wallet).thenReturn(wallet);
          when(
            () => appStore.apiConfig,
          ).thenReturn(const ApiConfig(networkMode: NetworkMode.mainnet));
          when(() => appStore.primaryAddress).thenReturn(knownAddress);
          when(() => wallet.currentAccount).thenReturn(account);
          when(() => account.primaryAddress).thenReturn(credentials);

          final cubit = SellBitboxCubit(
            paymentInfo: _info(),
            faucetService: faucet,
            blockchainService: blockchain,
            sellService: sellService,
            appStore: appStore,
          )..start();

          // start() schedules `_checkEthBalance` via scheduleMicrotask.
          async.flushMicrotasks();
          expect(
            cubit.state,
            isA<SellBitboxBitboxRequired>(),
            reason: 'disconnected BitBox must surface the BitboxRequired gate',
          );

          // Step 2: pair the device. init() re-attaches the manager to every
          // pre-existing credentials instance via setBitbox().
          late List<BitboxDevice> devices;
          service.getAllUsbDevices().then((d) => devices = d);
          async.flushMicrotasks();
          service.init(devices.single);
          async.flushMicrotasks();

          expect(
            credentials.isConnected,
            isTrue,
            reason: 'init() must re-attach the manager to credentials created before pairing',
          );

          // Step 3: cubit-side recovery — the screen calls
          // retryAfterConnection() once the gate flips back to connected.
          // With ethBalance >= requiredGasEth the cubit must settle on
          // SellBitboxEthReady, proving the recovery walked the same
          // _checkEthBalance branch as a freshly-mounted screen would.
          cubit.retryAfterConnection();
          async.flushMicrotasks();

          expect(
            cubit.state,
            isA<SellBitboxEthReady>(),
            reason:
                'retryAfterConnection on a re-attached BitBox must clear the gate without rebuilding the cubit',
          );
          // No faucet hop on the recovery path — the payment info already
          // has enough gas, so the cubit takes the EthReady branch directly.
          verifyNever(() => faucet.requestFaucet());

          // The cubit's stream is no longer subscribed to externally; close
          // it inside the same zone to flush the cancellation microtask.
          cubit.close();
          async.flushMicrotasks();
        });
      },
    );
  });
}

/// 32-byte personal-message payload. The real BitBox plugin signs whatever
/// the wallet account hashes for `signMessage`; size doesn't matter for the
/// fake's behaviour switch — only the behaviour mode does.
Uint8List _payload() => Uint8List.fromList(List<int>.filled(32, 0xab));
