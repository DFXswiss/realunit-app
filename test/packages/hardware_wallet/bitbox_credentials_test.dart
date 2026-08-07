import 'dart:async';
import 'dart:typed_data';

import 'package:bitbox_flutter/bitbox_flutter.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/hardware_wallet/bitbox_credentials.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/bitbox_exception.dart';

class _MockBitboxManager extends Mock implements BitboxManager {}

class _FakeBitboxDevice extends Fake implements BitboxDevice {}

class _ParseError implements Exception {}

void main() {
  late _MockBitboxManager manager;

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    // The sign queue is a process-wide static; reset it so a hung-sign test
    // cannot leak a pending (or wrong-zone) queue head into the next test.
    BitboxCredentials.resetSignQueue();
    manager = _MockBitboxManager();
    // _runOrThrowDisconnect probes manager.devices to distinguish a real
    // disconnect from a sign-internal failure. Tests below that expect the
    // *original* error to surface must report the device as still connected.
    when(() => manager.devices).thenAnswer((_) async => <BitboxDevice>[
          _FakeBitboxDevice(),
        ]);
  });

  BitboxCredentials connected() =>
      BitboxCredentials('0x000000000000000000000000000000000000dead')..setBitbox(manager);

  group('$BitboxCredentials', () {
    test('isConnected is false until setBitbox is called', () {
      final c = BitboxCredentials('0x000000000000000000000000000000000000dead');
      expect(c.isConnected, isFalse);
    });

    test('setBitbox and clearBitbox toggle isConnected', () {
      final c = BitboxCredentials('0x000000000000000000000000000000000000dead');
      c.setBitbox(manager);
      expect(c.isConnected, isTrue);
      c.clearBitbox();
      expect(c.isConnected, isFalse);
    });

    // The two synchronous web3dart entry points are never used on a BitBox
    // (every sign path is awaitable). They exist only to satisfy the interface
    // and must fail loud if a future refactor wires a sync caller onto BitBox
    // credentials by accident — the same guard `_DebugCredentials` carries in
    // wallet.dart.
    test('signToEcSignature throws UnimplementedError (sync path is never used)', () {
      final c = BitboxCredentials('0x000000000000000000000000000000000000dead');
      expect(
        () => c.signToEcSignature(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('signPersonalMessageToUint8List throws UnimplementedError (sync path is never used)', () {
      final c = BitboxCredentials('0x000000000000000000000000000000000000dead');
      expect(
        () => c.signPersonalMessageToUint8List(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('signToSignature throws BitboxNotConnectedException when bitboxManager is null', () {
      final c = BitboxCredentials('0x000000000000000000000000000000000000dead');
      expect(
        () => c.signToSignature(Uint8List.fromList(List.filled(32, 0))),
        throwsA(isA<BitboxNotConnectedException>()),
      );
    });

    test('signToSignature strips the EIP-1559 type-prefix byte before sending', () async {
      final fakeSig = Uint8List.fromList(
        List<int>.filled(32, 0xAA) + List<int>.filled(32, 0xBB) + [0x01],
      );
      when(
        () => manager.signETHRLPTransaction(any(), any(), any(), any()),
      ).thenAnswer((_) async => fakeSig);

      final payload = Uint8List.fromList([0x02, 0xCA, 0xFE, 0xBA, 0xBE]);
      final sig = await connected().signToSignature(payload, chainId: 1, isEIP1559: true);

      expect(sig.v, 1, reason: 'EIP-1559 keeps the raw parity v as-is');
      final captured = verify(
        () => manager.signETHRLPTransaction(
          captureAny(),
          captureAny(),
          captureAny(),
          captureAny(),
        ),
      ).captured;
      expect(captured[2], 'cafebabe', reason: 'leading 0x02 must be stripped before hex-encoding');
    });

    test('signToSignature returns raw v for legacy (non-EIP-155) signatures', () async {
      // chainId=null, BitBox returns v in {27, 28}.
      final fakeSig = Uint8List.fromList(
        List<int>.filled(32, 0x11) + List<int>.filled(32, 0x22) + [27],
      );
      when(
        () => manager.signETHRLPTransaction(any(), any(), any(), any()),
      ).thenAnswer((_) async => fakeSig);

      final sig = await connected().signToSignature(Uint8List.fromList([0xDE, 0xAD]));
      expect(sig.v, 27);
    });

    test('signToSignature derives chainIdV for parity 0 (EIP-155)', () async {
      // chainId=1, EIP-155 v = chainId*2 + 35 = 37 (parity 0).
      final fakeSig = Uint8List.fromList(
        List<int>.filled(32, 0x11) + List<int>.filled(32, 0x22) + [37],
      );
      when(
        () => manager.signETHRLPTransaction(any(), any(), any(), any()),
      ).thenAnswer((_) async => fakeSig);

      final sig = await connected().signToSignature(Uint8List.fromList([0xDE, 0xAD]), chainId: 1);
      expect(sig.v, 37);
    });

    test('signToSignature derives chainIdV for parity 1 (EIP-155)', () async {
      final fakeSig = Uint8List.fromList(
        List<int>.filled(32, 0x11) + List<int>.filled(32, 0x22) + [38],
      );
      when(
        () => manager.signETHRLPTransaction(any(), any(), any(), any()),
      ).thenAnswer((_) async => fakeSig);

      final sig = await connected().signToSignature(Uint8List.fromList([0xDE, 0xAD]), chainId: 1);
      expect(sig.v, 38);
    });

    // The EIP-155 parity check truncates chainIds wider than 32 bits before
    // matching the low byte of v. chainId 2^32 + 1 is 33 bits, so the
    // truncation loop runs once (`>> 8` → 2^24, which is ≤ 32 bits and stops
    // it). The device returns v = 35, which matches (2^24 * 2 + 35) & 0xff ==
    // 35, so parity resolves to 0 and the final v is computed from the FULL,
    // untruncated chainId.
    test('signToSignature truncates a >2^32 chainId for the EIP-155 parity check', () async {
      const chainId = 0x100000001; // 2^32 + 1, 33 bits — forces one loop iteration
      final fakeSig = Uint8List.fromList(
        List<int>.filled(32, 0x11) + List<int>.filled(32, 0x22) + [35],
      );
      when(
        () => manager.signETHRLPTransaction(any(), any(), any(), any()),
      ).thenAnswer((_) async => fakeSig);

      final sig = await connected().signToSignature(
        Uint8List.fromList([0xDE, 0xAD]),
        chainId: chainId,
      );

      // parity 0 → v = chainId * 2 + 35, derived from the untruncated chainId.
      expect(sig.v, chainId * 2 + 35);
    });

    test('signPersonalMessage throws BitboxNotConnectedException when not connected', () {
      final c = BitboxCredentials('0x000000000000000000000000000000000000dead');
      expect(
        () => c.signPersonalMessage(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<BitboxNotConnectedException>()),
      );
    });

    test('signPersonalMessage passes chainId and derivation path to the manager', () async {
      when(
        () => manager.signETHMessage(any(), any(), any()),
      ).thenAnswer((_) async => Uint8List.fromList(List.filled(65, 0x01)));

      final sig = await connected().signPersonalMessage(Uint8List.fromList([1, 2, 3]), chainId: 1);

      expect(sig.length, 65);
      final captured = verify(
        () => manager.signETHMessage(
          captureAny(),
          captureAny(),
          captureAny(),
        ),
      ).captured;
      expect(captured[0], 1);
      expect(captured[1], "m/44'/60'/0'/0/0");
    });

    test('signTypedDataV4 throws BitboxNotConnectedException when not connected', () {
      final c = BitboxCredentials('0x000000000000000000000000000000000000dead');
      expect(
        () => c.signTypedDataV4(1, '{"primaryType":"Foo"}'),
        throwsA(isA<BitboxNotConnectedException>()),
      );
    });

    test('signTypedDataV4 hex-encodes signature bytes with 0x prefix', () async {
      when(
        () => manager.signETHTypedMessage(any(), any(), any()),
      ).thenAnswer((_) async => Uint8List.fromList([0xCA, 0xFE, 0xBA, 0xBE]));

      final sig = await connected().signTypedDataV4(1, '{"primaryType":"Foo"}');
      expect(sig, '0xcafebabe');
    });

    test('serializes parallel signs through the static queue', () async {
      var inFlight = 0;
      var maxParallel = 0;
      when(() => manager.signETHTypedMessage(any(), any(), any())).thenAnswer((_) async {
        inFlight++;
        if (inFlight > maxParallel) maxParallel = inFlight;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        inFlight--;
        return Uint8List.fromList([0x01]);
      });

      final c = connected();
      await Future.wait([
        c.signTypedDataV4(1, '{"primaryType":"A"}'),
        c.signTypedDataV4(1, '{"primaryType":"B"}'),
        c.signTypedDataV4(1, '{"primaryType":"C"}'),
      ]);

      expect(maxParallel, 1);
    });

    test('queue continues after a sign throws (slot released in finally)', () async {
      // `_runOrThrowDisconnect` probes `manager.devices` on a thrown sign to
      // decide whether to relabel the error as BitboxNotConnectedException.
      // Stub it to a non-empty list so the original "first sign explodes"
      // survives — this test exercises the queue, not the disconnect path.
      when(() => manager.devices).thenAnswer((_) async => [_FakeBitboxDevice()]);

      var call = 0;
      when(() => manager.signETHTypedMessage(any(), any(), any())).thenAnswer((_) async {
        call++;
        if (call == 1) throw Exception('first sign explodes');
        return Uint8List.fromList([0x42]);
      });

      final c = connected();
      await expectLater(
        c.signTypedDataV4(1, '{"primaryType":"A"}'),
        throwsException,
      );
      final sig = await c
          .signTypedDataV4(1, '{"primaryType":"B"}')
          .timeout(const Duration(seconds: 1));
      expect(sig, '0x42');
    });

    // Post-#461 mid-flow recovery: _runOrThrowDisconnect must convert a
    // mid-sign plugin error into BitboxNotConnectedException only when the
    // device probe confirms the device is gone.
    test(
      'signToSignature surfaces BitboxNotConnectedException when device is gone mid-sign',
      () async {
        when(
          () => manager.signETHRLPTransaction(any(), any(), any(), any()),
        ).thenThrow(Exception('plugin: USB write failed mid-sign'));
        when(() => manager.devices).thenAnswer((_) async => <BitboxDevice>[]);

        final c = connected();
        await expectLater(
          c.signToSignature(Uint8List.fromList([0xDE, 0xAD]), chainId: 1),
          throwsA(isA<BitboxNotConnectedException>()),
        );
        expect(c.isConnected, isFalse, reason: 'clearBitbox must have run on lost device');
      },
    );

    // Post-#461 mid-flow recovery: a still-reachable device means the
    // original error wins; we must not mask real plugin/parse failures.
    test(
      'signToSignature rethrows the original error when device is still present mid-sign',
      () async {
        when(
          () => manager.signETHRLPTransaction(any(), any(), any(), any()),
        ).thenThrow(_ParseError());
        when(() => manager.devices).thenAnswer((_) async => [_FakeBitboxDevice()]);

        final c = connected();
        await expectLater(
          c.signToSignature(Uint8List.fromList([0xDE, 0xAD]), chainId: 1),
          throwsA(isA<_ParseError>()),
        );
        expect(c.isConnected, isTrue, reason: 'clearBitbox must NOT run when device is still there');
      },
    );

    // Post-#461 mid-flow recovery: if the probe itself blows up, _deviceLost
    // returns true (defensive fallback) and the disconnect path wins.
    test(
      'signToSignature treats device as lost when the device probe itself throws',
      () async {
        when(
          () => manager.signETHRLPTransaction(any(), any(), any(), any()),
        ).thenThrow(Exception('plugin: USB write failed mid-sign'));
        when(() => manager.devices).thenThrow(Exception('USB descriptor closed'));

        final c = connected();
        await expectLater(
          c.signToSignature(Uint8List.fromList([0xDE, 0xAD]), chainId: 1),
          throwsA(isA<BitboxNotConnectedException>()),
        );
        expect(c.isConnected, isFalse, reason: 'failed probe must be treated as lost device');
      },
    );

    // Cross-method guard: every sign method must route through
    // _runOrThrowDisconnect. Drive the disconnect path through
    // signTypedDataV4 so a future refactor that drops the wrap from one
    // method gets caught here.
    test(
      'signTypedDataV4 also routes through _runOrThrowDisconnect on device loss',
      () async {
        when(
          () => manager.signETHTypedMessage(any(), any(), any()),
        ).thenThrow(Exception('plugin: BLE drop mid-sign'));
        when(() => manager.devices).thenAnswer((_) async => <BitboxDevice>[]);

        final c = connected();
        await expectLater(
          c.signTypedDataV4(1, '{"primaryType":"Foo"}'),
          throwsA(isA<BitboxNotConnectedException>()),
        );
        expect(c.isConnected, isFalse, reason: 'clearBitbox must have run on lost device');
      },
    );

    // A hung native sign must not poison the static queue forever. After
    // `signQueueTimeout` the queue slot frees and the hung sign surfaces as
    // BitboxNotConnectedException to its caller.
    test('a never-completing sign resolves within signQueueTimeout', () {
      fakeAsync((async) {
        // Seed the queue head inside this zone (see resetSignQueue doc).
        BitboxCredentials.resetSignQueue();
        async.flushMicrotasks();

        // Native sign that never returns — simulates an Android USB hang.
        when(() => manager.signETHTypedMessage(any(), any(), any()))
            .thenAnswer((_) => Completer<Uint8List>().future);

        final c = connected();
        Object? thrown;
        c.signTypedDataV4(1, '{"primaryType":"A"}').catchError((Object e) {
          thrown = e;
          return '';
        });

        // Just before the bound: still pending.
        async.elapse(BitboxCredentials.signQueueTimeout - const Duration(seconds: 1));
        expect(thrown, isNull);

        // Past the bound: the hung sign surfaces as a typed exception.
        async.elapse(const Duration(seconds: 2));
        expect(thrown, isA<BitboxNotConnectedException>());
      });
    });

    // The whole point of the bug fix: one hung sign must not deadlock every
    // later sign chained off the static queue.
    test('a sign issued after a hung sign is not deadlocked', () {
      fakeAsync((async) {
        BitboxCredentials.resetSignQueue();
        async.flushMicrotasks();

        var call = 0;
        when(() => manager.signETHTypedMessage(any(), any(), any())).thenAnswer((_) async {
          call++;
          if (call == 1) return Completer<Uint8List>().future; // first sign hangs
          return Uint8List.fromList([0x42]);
        });

        final c = connected();
        Object? firstThrown;
        c.signTypedDataV4(1, '{"primaryType":"A"}').catchError((Object e) {
          firstThrown = e;
          return '';
        });

        String? secondResult;
        Object? secondThrown;
        c.signTypedDataV4(1, '{"primaryType":"B"}').then((v) {
          secondResult = v;
        }).catchError((Object e) {
          secondThrown = e;
        });

        // Drain past the queue guard so the hung slot frees.
        async.elapse(BitboxCredentials.signQueueTimeout + const Duration(seconds: 1));
        async.flushMicrotasks();

        expect(firstThrown, isA<BitboxNotConnectedException>());
        // The second sign must NOT hang — but since the device was cleared by
        // the timed-out first sign, it fails fast rather than racing the
        // device.
        expect(secondResult, isNull);
        expect(secondThrown, isA<BitboxNotConnectedException>());
      });
    });

    // Requirement 3: a timed-out sign clears the device so a subsequent sign
    // cannot talk to a device whose native op may still be in flight — it hits
    // the `manager == null` guard and fails fast without touching the device.
    test('device is cleared after a hung sign so the next sign fails fast', () {
      fakeAsync((async) {
        BitboxCredentials.resetSignQueue();
        async.flushMicrotasks();

        // First sign hangs forever; later signs would otherwise hit the mock.
        when(() => manager.signETHTypedMessage(any(), any(), any()))
            .thenAnswer((_) => Completer<Uint8List>().future);

        final c = connected();
        expect(c.isConnected, isTrue);

        c.signTypedDataV4(1, '{"primaryType":"A"}').catchError((Object _) => '');
        async.elapse(BitboxCredentials.signQueueTimeout + const Duration(seconds: 1));
        async.flushMicrotasks();

        expect(c.isConnected, isFalse, reason: 'clearBitbox must run on a timed-out sign');

        // The next sign hits the manager == null guard: it fails fast with a
        // typed exception and never invokes the device sign mock again.
        Object? nextThrown;
        c.signTypedDataV4(1, '{"primaryType":"B"}').catchError((Object e) {
          nextThrown = e;
          return '';
        });
        async.flushMicrotasks();

        expect(nextThrown, isA<BitboxNotConnectedException>());
        verify(() => manager.signETHTypedMessage(any(), any(), any())).called(1);
      });
    });

    // Requirement 5: the normal path must stay serialised and in order.
    test('normal serialised signing completes in order', () async {
      final order = <String>[];
      when(() => manager.signETHTypedMessage(any(), any(), any())).thenAnswer((invocation) async {
        final data = invocation.positionalArguments[2] as Uint8List;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        order.add(String.fromCharCodes(data));
        return Uint8List.fromList([0x01]);
      });

      final c = connected();
      await Future.wait([
        c.signTypedDataV4(1, 'A'),
        c.signTypedDataV4(1, 'B'),
        c.signTypedDataV4(1, 'C'),
      ]);

      expect(order, ['A', 'B', 'C']);
    });

    test('sign on cleared credentials throws BitboxNotConnectedException, not NoSuchMethod',
        () async {
      // Snapshot semantics (3.2) — the manager may be nulled by the observer
      // between the connection check and the sign call. The snapshot-on-entry
      // pattern means the null check fires and the bang-operator path is
      // never reached.
      final c = BitboxCredentials('0x000000000000000000000000000000000000dead')
        ..setBitbox(manager);
      c.clearBitbox();

      await expectLater(
        c.signTypedDataV4(1, '{"primaryType":"A"}'),
        throwsA(isA<BitboxNotConnectedException>()),
      );
    });
  });
}
