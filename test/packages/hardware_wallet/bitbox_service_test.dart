import 'package:bitbox_flutter/bitbox_flutter.dart';
import 'package:bitbox_flutter/testing.dart';
import 'package:bitbox_flutter/usb/bitbox_usb_platform_interface.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/packages/hardware_wallet/bitbox.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/bitbox_address_unavailable_exception.dart';

// Service-lifecycle suite. Drives the official bitbox_flutter simulator
// (installed at the BitboxUsbPlatform.instance seam) so the tests exercise
// the same code paths the real plugin runs, with deterministic device-loss
// and reconnect timing controlled from the test.
//
// Observer-driven cases run inside fakeAsync so virtual time is advanced
// via async.elapse(...) instead of wall-clock Future.delayed — eliminates
// the 50ms/150ms flake risk on loaded CI runners and makes tick counting
// fully deterministic. Microtask-driven setup (pairedService) is pumped
// inside the same zone via async.flushMicrotasks() so the periodic timer
// is bound to the fake clock.
//
// Each test installs and restores the platform in setUp/tearDown so suites
// running in parallel don't bleed simulator state into each other.
void main() {
  late BitboxUsbPlatform previousPlatform;
  late SimulatedBitboxPlatform platform;

  // 50ms keeps the observer-tick latency well under each test's virtual
  // budget while still leaving room for the simulator's microtask hops.
  const fastInterval = Duration(milliseconds: 50);
  const observerSettleTime = Duration(milliseconds: 150);

  const knownAddress = '0x000000000000000000000000000000000000dead';

  setUp(() {
    previousPlatform = BitboxUsbPlatform.instance;
    platform = installSimulatedBitboxPlatform();
  });

  tearDown(() {
    BitboxUsbPlatform.instance = previousPlatform;
  });

  // Pair the service inside an existing fakeAsync zone. Must NOT be called
  // outside fakeAsync — the Timer.periodic the service installs has to be
  // bound to the fake clock, otherwise async.elapse won't pump it.
  BitboxService pairedServiceSync(FakeAsync async) {
    final service = BitboxService(connectionStatusInterval: fastInterval);
    late List<BitboxDevice> devices;
    service.getAllUsbDevices().then((d) => devices = d);
    async.flushMicrotasks();
    service.init(devices.single);
    async.flushMicrotasks();
    return service;
  }

  group('$BitboxService', () {
    // Firmware capture. The version rides on the BLE product characteristic,
    // so it is cached once at pairing and read from cache thereafter — the KYC
    // gate must not need a live device.
    test('caches the firmware version at pairing and reports it affected', () {
      fakeAsync((async) {
        platform = installSimulatedBitboxPlatform(firmwareVersion: 'v9.26.4');
        final service = pairedServiceSync(async);

        expect(service.firmwareVersion, 'v9.26.4');
        expect(service.refusesRegistrationSignature, isTrue);
      });
    });

    test('reports fixed firmware as unaffected', () {
      fakeAsync((async) {
        platform = installSimulatedBitboxPlatform(firmwareVersion: 'v9.26.5');
        final service = pairedServiceSync(async);

        expect(service.firmwareVersion, 'v9.26.5');
        expect(service.refusesRegistrationSignature, isFalse);
      });
    });

    test('a transport that reports no version is not gated', () {
      // USB. Every USB operation was verified working on hardware, so a null
      // version must never gate — otherwise every Android user is blocked.
      fakeAsync((async) {
        platform = installSimulatedBitboxPlatform(firmwareVersion: null);
        final service = pairedServiceSync(async);

        expect(service.firmwareVersion, isNull);
        expect(service.refusesRegistrationSignature, isFalse);
      });
    });

    test('a failed version read does not fail pairing', () {
      // Reading the version is best-effort: it is diagnostic for a gate, never
      // a reason to refuse a device the user just paired.
      fakeAsync((async) {
        platform = installSimulatedBitboxPlatform(
          errors: {
            SimulatedBitboxMethod.getFirmwareVersion: Exception('unavailable'),
          },
        );
        final service = pairedServiceSync(async);

        expect(service.firmwareVersion, isNull);
        expect(service.refusesRegistrationSignature, isFalse);
        // Pairing still completed: credentials are live.
        expect(service.getCredentials(knownAddress).isConnected, isTrue);
      });
    });

    test('firmware version is null before pairing', () {
      final service = BitboxService(connectionStatusInterval: fastInterval);

      expect(service.firmwareVersion, isNull);
      expect(service.refusesRegistrationSignature, isFalse);
    });

    test('getCredentials before init returns disconnected credentials', () {
      final service = BitboxService(connectionStatusInterval: fastInterval);
      final credentials = service.getCredentials(knownAddress);
      expect(credentials.isConnected, isFalse);
    });

    test('init() promotes credentials handed out before connect (P461 #1)', () {
      // Regression guard: pre-fix, BitboxService only attached the manager to
      // credentials returned *after* _isConnected was set, so a wallet built
      // from persistence before pairing stayed permanently disconnected and
      // every sign threw BitboxNotConnectedException.
      fakeAsync((async) {
        final service = BitboxService(connectionStatusInterval: fastInterval);

        final credentials = service.getCredentials(knownAddress);
        expect(credentials.isConnected, isFalse);

        late List<BitboxDevice> devices;
        service.getAllUsbDevices().then((d) => devices = d);
        async.flushMicrotasks();
        service.init(devices.single);
        async.flushMicrotasks();

        expect(
          credentials.isConnected,
          isTrue,
          reason: 'init() must re-attach the manager to pre-existing credentials',
        );
      });
    });

    test('observer clears credentials and closes transport when device vanishes', () {
      // Bug-class: observer used to null the _credentials reference and skip
      // closing the transport, which on Android left the USB FD claimed and
      // blocked the next connect(). The fix clears the credentials in place
      // (preserving the reference for reconnect) and calls disconnect().
      fakeAsync((async) {
        final service = pairedServiceSync(async);
        final credentials = service.getCredentials(knownAddress);
        expect(credentials.isConnected, isTrue);

        platform.when(
          SimulatedBitboxMethod.getDevices,
          (_) async => const <BitboxDevice>[],
        );

        service.startConnectionStatusObserver();
        async.elapse(observerSettleTime);

        expect(
          credentials.isConnected,
          isFalse,
          reason: 'observer must clear the credentials on device-loss',
        );
        expect(
          platform.count(SimulatedBitboxMethod.close),
          greaterThanOrEqualTo(1),
          reason: 'observer must release the USB transport on device-loss',
        );
      });
    });

    test('observer preserves the credentials reference so reconnect can heal them', () {
      // Critical to P461 #1: if the observer nulls _credentials, the next
      // init() has nothing to re-attach and the wallet stays broken.
      fakeAsync((async) {
        final service = pairedServiceSync(async);
        final credentials = service.getCredentials(knownAddress);

        platform.when(
          SimulatedBitboxMethod.getDevices,
          (_) async => const <BitboxDevice>[],
        );
        service.startConnectionStatusObserver();
        async.elapse(observerSettleTime);
        expect(credentials.isConnected, isFalse);

        // Device reappears — re-arm the simulator's default device list and
        // re-init on the same credentials reference.
        platform.when(SimulatedBitboxMethod.getDevices, (_) async => platform.devices);
        late List<BitboxDevice> devices;
        service.getAllUsbDevices().then((d) => devices = d);
        async.flushMicrotasks();
        service.init(devices.single);
        async.flushMicrotasks();

        expect(
          credentials.isConnected,
          isTrue,
          reason: 'the same credentials instance must re-attach on reconnect',
        );
      });
    });

    test('observer stops ticking after a single device-loss event', () {
      fakeAsync((async) {
        final service = pairedServiceSync(async);
        platform.when(
          SimulatedBitboxMethod.getDevices,
          (_) async => const <BitboxDevice>[],
        );

        service.startConnectionStatusObserver();
        async.elapse(observerSettleTime);
        final ticksAtLoss = platform.count(SimulatedBitboxMethod.getDevices);

        async.elapse(observerSettleTime * 2);
        expect(
          platform.count(SimulatedBitboxMethod.getDevices),
          ticksAtLoss,
          reason: 'observer must self-cancel after detecting device-loss',
        );
      });
    });

    test('observer swallows transport-close errors instead of crashing', () {
      // Android plugin can throw on close() if the FD is already gone; the
      // observer must catch that so the device-loss recovery still completes.
      fakeAsync((async) {
        final service = pairedServiceSync(async);
        final credentials = service.getCredentials(knownAddress);

        platform.when(
          SimulatedBitboxMethod.getDevices,
          (_) async => const <BitboxDevice>[],
        );
        platform.throwOn(SimulatedBitboxMethod.close, Exception('USB busy'));

        service.startConnectionStatusObserver();
        async.elapse(observerSettleTime);

        expect(
          credentials.isConnected,
          isFalse,
          reason: 'clearBitbox must still run even when close() throws',
        );
      });
    });

    test('stopConnectionStatusObserver cancels the active periodic', () {
      fakeAsync((async) {
        final service = pairedServiceSync(async);
        service.startConnectionStatusObserver();
        service.stopConnectionStatusObserver();

        final ticksAfterStop = platform.count(SimulatedBitboxMethod.getDevices);
        async.elapse(observerSettleTime * 2);

        expect(
          platform.count(SimulatedBitboxMethod.getDevices),
          ticksAfterStop,
          reason: 'no further device probing after explicit stop',
        );
      });
    });

    test('startConnectionStatusObserver replaces any prior periodic', () {
      // Defensive: callers may re-arm the observer; the implementation cancels
      // the previous timer before installing the new one. Without that, two
      // periodics would race and double-tick. Asserted by counting probes
      // across two full intervals: with one active timer that's exactly 2
      // ticks; with both timers alive concurrently it would be 4.
      fakeAsync((async) {
        final service = pairedServiceSync(async);
        final ticksBeforeStart = platform.count(SimulatedBitboxMethod.getDevices);

        service.startConnectionStatusObserver();
        service.startConnectionStatusObserver();

        async.elapse(fastInterval * 2);
        final probesAcrossTwoIntervals =
            platform.count(SimulatedBitboxMethod.getDevices) - ticksBeforeStart;
        expect(
          probesAcrossTwoIntervals,
          lessThanOrEqualTo(2),
          reason: 'both periodics alive would double-tick: expected <= 2 probes / 2 intervals',
        );

        service.stopConnectionStatusObserver();
        final ticksAfterStop = platform.count(SimulatedBitboxMethod.getDevices);
        async.elapse(observerSettleTime);

        expect(
          platform.count(SimulatedBitboxMethod.getDevices),
          ticksAfterStop,
          reason: 'both periodics must be cancelled — neither may tick after stop',
        );
      });
    });

    test('observer survives a thrown getAllUsbDevices and keeps probing on the next tick', () {
      // Drives the production fix: a transient plugin error in the device
      // probe used to become an uncaught async exception inside the periodic
      // callback. The recovery loop now logs and waits for the next tick;
      // only an explicit empty device list triggers the device-loss path.
      fakeAsync((async) {
        final service = pairedServiceSync(async);
        final credentials = service.getCredentials(knownAddress);
        expect(credentials.isConnected, isTrue);

        platform.throwOn(SimulatedBitboxMethod.getDevices, Exception('transient BLE'));

        service.startConnectionStatusObserver();
        async.elapse(observerSettleTime);

        expect(
          credentials.isConnected,
          isTrue,
          reason: 'a throw must not trigger the device-loss path',
        );
        expect(
          platform.count(SimulatedBitboxMethod.close),
          0,
          reason: 'no transport close on a transient probe failure',
        );
        final ticksUnderError = platform.count(SimulatedBitboxMethod.getDevices);
        expect(
          ticksUnderError,
          greaterThanOrEqualTo(1),
          reason: 'the observer must have at least attempted one probe',
        );

        // Recovery: probe stops throwing. The next tick must fire — proving
        // the observer survived the prior exception instead of dying silent.
        platform.clearError(SimulatedBitboxMethod.getDevices);
        async.elapse(observerSettleTime);

        expect(
          platform.count(SimulatedBitboxMethod.getDevices),
          greaterThan(ticksUnderError),
          reason: 'observer must keep probing after a transient error',
        );
        expect(
          credentials.isConnected,
          isTrue,
          reason: 'devices are present again — connection must stay alive',
        );

        service.stopConnectionStatusObserver();
      });
    });

    test('init() failure leaves credentials un-attached', () {
      // Coverage gap: if initBitBox() returns false the service throws
      // 'Failed to init' and must NOT promote _isConnected. Subsequent
      // getCredentials() calls must still hand out disconnected instances.
      fakeAsync((async) {
        platform.when(SimulatedBitboxMethod.initBitBox, (_) async => false);

        final service = BitboxService(connectionStatusInterval: fastInterval);
        final preInit = service.getCredentials(knownAddress);
        expect(preInit.isConnected, isFalse);

        late List<BitboxDevice> devices;
        service.getAllUsbDevices().then((d) => devices = d);
        async.flushMicrotasks();

        Object? caught;
        service.init(devices.single).catchError((Object e) {
          caught = e;
          return false;
        });
        async.flushMicrotasks();

        expect(caught, isA<Exception>(), reason: 'init() must throw when initBitBox returns false');
        expect(
          preInit.isConnected,
          isFalse,
          reason: 'failed init must not promote pre-existing credentials',
        );

        final postInit = service.getCredentials(knownAddress);
        expect(
          postInit.isConnected,
          isFalse,
          reason: 'failed init must leave _isConnected false for future hand-outs',
        );
      });
    });

    // The three thin pass-through wrappers below — startScan, getChannelHash,
    // confirmPairing — used to be coverage-blind because no test ever drove
    // them via the simulator. They are the BitBox pairing handshake the UI
    // walks the user through, so a typo or method-name flip would only
    // surface at pairing time on real hardware. Pin them through the same
    // simulator the other lifecycle tests use.
    test('startScan forwards to BitboxManager.startScan via the simulator', () {
      // startScan is the first call in the BitBox pairing UI — it triggers
      // the BLE/USB device probe on Android. With no devices wired into the
      // call yet, we just need to prove the wrapper round-trips through the
      // platform interface and returns the simulator's configured result.
      fakeAsync((async) {
        platform.when(
          SimulatedBitboxMethod.startScan,
          (_) async => true,
        );

        final service = BitboxService(connectionStatusInterval: fastInterval);
        bool? result;
        service.startScan().then((value) => result = value);
        async.flushMicrotasks();

        expect(result, isTrue);
        expect(platform.count(SimulatedBitboxMethod.startScan), 1);
      });
    });

    test('getChannelHash returns the hash the device emits during pairing', () {
      // Channel hash is the short fingerprint the user compares on-screen
      // vs. on-device during the U2F-style pairing dance. Production code
      // is a single line, but a typo on the SDK method name would break the
      // pairing flow entirely.
      fakeAsync((async) {
        final service = pairedServiceSync(async);
        platform.when(
          SimulatedBitboxMethod.getChannelHash,
          (_) async => 'abcd-1234-deadbeef',
        );

        String? hash;
        service.getChannelHash().then((value) => hash = value);
        async.flushMicrotasks();

        expect(hash, 'abcd-1234-deadbeef');
        expect(platform.count(SimulatedBitboxMethod.getChannelHash), 1);
      });
    });

    test('getDeviceStatus returns the firmware status the device reports', () {
      // Thin pass-through to the plugin's cached-status read. The cubit branches
      // on this string after pairing to detect an unseeded device, so a
      // method-name flip would silently break that gate on real hardware.
      fakeAsync((async) {
        final service = pairedServiceSync(async);
        platform.when(
          SimulatedBitboxMethod.getDeviceStatus,
          (_) async => 'uninitialized',
        );

        String? status;
        service.getDeviceStatus().then((value) => status = value);
        async.flushMicrotasks();

        expect(status, 'uninitialized');
        expect(platform.count(SimulatedBitboxMethod.getDeviceStatus), 1);
      });
    });

    test('confirmPairing returns normally on a verified channel', () {
      // Happy path: user pressed the on-device button.
      fakeAsync((async) {
        final service = pairedServiceSync(async);
        platform.when(
          SimulatedBitboxMethod.channelHashVerify,
          (_) async => true,
        );

        Object? caught;
        service.confirmPairing().catchError((Object e) {
          caught = e;
        });
        async.flushMicrotasks();

        expect(caught, isNull);
        expect(platform.count(SimulatedBitboxMethod.channelHashVerify), 1);
      });
    });

    test('confirmPairing throws when the device rejects the channel hash', () {
      // Pairing rejection path: production guards the failure with an
      // explicit `throw Exception('Failed to verify')` so the UI can surface
      // a retry prompt instead of silently proceeding. Without this pin the
      // throw branch is dead code from coverage's POV.
      fakeAsync((async) {
        final service = pairedServiceSync(async);
        platform.when(
          SimulatedBitboxMethod.channelHashVerify,
          (_) async => false,
        );

        Object? caught;
        service.confirmPairing().catchError((Object e) {
          caught = e;
          return null;
        });
        async.flushMicrotasks();

        expect(
          caught,
          isA<Exception>(),
          reason: 'a rejected pairing must throw, not return silently',
        );
      });
    });

    test(
      'getCredentials called twice with the same address while connected returns equally-connected instances',
      () {
        // Defensive pin: post-#472 the service caches BitboxCredentials in a
        // map keyed by lowercased address, and the disconnect observer iterates
        // every entry to call clearBitbox(). So callers must always see the
        // same canonical instance for a given address — a refactor that hands
        // out a fresh instance per call would let the observer clear an
        // orphaned reference instead of the one the caller is still holding.
        fakeAsync((async) {
          final service = pairedServiceSync(async);

          final first = service.getCredentials(knownAddress);
          final second = service.getCredentials(knownAddress);

          expect(first.isConnected, isTrue);
          expect(second.isConnected, isTrue);
          expect(
            second,
            same(first),
            reason: 'getCredentials must return the cached instance for a given address',
          );
        });
      },
    );

    // The empty-address self-heal boundary. The SDK coerces a native `null`
    // into `""` at its transport layer (`return result ?? ''`), so a device
    // that stalls right after channel-hash verify resolves getETHAddress with
    // an empty string instead of throwing. getEthAddress retries that transient
    // empty read across `attempts`; only a persistent empty throws. Both the
    // create and heal flows route through this method, so an empty read can
    // never be persisted.
    group('getEthAddress', () {
      const validAddress = '0x1111111111111111111111111111111111111111';
      const retryDelay = Duration(milliseconds: 200);

      test('returns the address when the first read is non-empty', () {
        fakeAsync((async) {
          final service = pairedServiceSync(async);
          platform.when(SimulatedBitboxMethod.getETHAddress, (_) async => validAddress);

          String? result;
          service.getEthAddress(retryDelay: retryDelay).then((value) => result = value);
          async.flushMicrotasks();

          expect(result, validAddress);
          expect(
            platform.count(SimulatedBitboxMethod.getETHAddress),
            1,
            reason: 'a non-empty first read must short-circuit the retry loop',
          );
        });
      });

      test('retries an empty read and succeeds once the device returns a valid address', () {
        fakeAsync((async) {
          final service = pairedServiceSync(async);
          // First read stalls (empty), second read recovers — the exact BLE
          // stall the boundary exists to absorb.
          var call = 0;
          platform.when(
            SimulatedBitboxMethod.getETHAddress,
            (_) async => call++ == 0 ? '' : validAddress,
          );

          String? result;
          service.getEthAddress(retryDelay: retryDelay).then((value) => result = value);
          // The first (empty) read resolves on microtasks; the retry waits the
          // backoff before the second read.
          async.flushMicrotasks();
          expect(result, isNull, reason: 'must wait the retry delay before the second read');

          async.elapse(retryDelay);

          expect(result, validAddress);
          expect(
            platform.count(SimulatedBitboxMethod.getETHAddress),
            2,
            reason: 'exactly one retry was needed to recover',
          );
        });
      });

      test('throws BitboxAddressUnavailableException when every read is empty', () {
        fakeAsync((async) {
          final service = pairedServiceSync(async);
          platform.when(SimulatedBitboxMethod.getETHAddress, (_) async => '');

          Object? caught;
          service
              .getEthAddress(attempts: 3, retryDelay: retryDelay)
              .catchError((Object e) {
            caught = e;
            return '';
          });
          // Drive past both inter-attempt delays so all three reads run.
          async.flushMicrotasks();
          async.elapse(retryDelay * 3);

          expect(
            caught,
            isA<BitboxAddressUnavailableException>(),
            reason: 'a persistent empty read must throw, never return ""',
          );
          expect(
            platform.count(SimulatedBitboxMethod.getETHAddress),
            3,
            reason: 'all configured attempts must be exhausted before throwing',
          );
        });
      });
    });
  });
}
