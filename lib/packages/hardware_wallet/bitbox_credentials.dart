import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:bitbox_flutter/bitbox_manager.dart';
import 'package:convert/convert.dart' as convert;
import 'package:flutter/foundation.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/bitbox_exception.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart';

class BitboxCredentials extends CredentialsWithKnownAddress {
  // Single device, single noise cipher — concurrent signs would advance the
  // nonce out of order and break decryption permanently.
  static Future<void> _signQueue = Future.value();

  static const _defaultDerivationPath = "m/44'/60'/0'/0/0";

  /// Upper bound on how long a single sign may hold the [_signQueue] slot.
  ///
  /// If a native sign hangs (e.g. an Android USB read with no transport
  /// timeout) the queue must not stay poisoned forever — every subsequent
  /// sign chains off it and would deadlock. This guard is deliberately well
  /// above the caller-side [DFXAuthService] sign timeout (3 minutes) so a
  /// legitimately slow on-device confirmation is never cut short; it only
  /// trips on a genuine hang.
  static const signQueueTimeout = Duration(minutes: 5);

  final String _address;

  BitboxManager? bitboxManager;
  String? derivationPath;

  BitboxCredentials(this._address);

  /// Re-seeds the static sign queue with a freshly-completed future.
  ///
  /// Production code never needs this — the queue self-heals via
  /// [signQueueTimeout]. It exists so a `fakeAsync` test starts each case
  /// with a queue head completed inside the test's own zone; a future
  /// completed in a previous test's zone would not deliver its `.then`
  /// continuations under `fakeAsync` and would wedge the chain.
  @visibleForTesting
  static void resetSignQueue() {
    _signQueue = Future.value();
  }

  static Future<T> _synchronizeSign<T>(Future<T> Function() sign) {
    final previous = _signQueue;
    final completer = Completer<void>();
    _signQueue = completer.future;

    return previous.then((_) async {
      try {
        return await sign();
      } finally {
        completer.complete();
      }
    });
  }

  /// Runs [sign] under the queue slot but bounds it with [signQueueTimeout].
  ///
  /// A hung native sign would otherwise leave [_signQueue] permanently
  /// pending and deadlock every later sign. On timeout the device is treated
  /// as lost: [clearBitbox] nulls out [bitboxManager] so subsequent signs hit
  /// the `manager == null` guard and fail fast with
  /// [BitboxNotConnectedException] instead of racing the still-in-flight
  /// native op on the shared noise cipher. The caller re-pairs to get a fresh
  /// noise channel.
  Future<T> _synchronizeBoundedSign<T>(Future<T> Function() sign) {
    return _synchronizeSign(() async {
      try {
        return await sign().timeout(signQueueTimeout);
      } on TimeoutException {
        clearBitbox();
        throw const BitboxNotConnectedException();
      }
    });
  }

  @override
  EthereumAddress get address => EthereumAddress.fromHex(_address);

  /// Attaches (or re-attaches) a manager. Preserves an existing
  /// [derivationPath] across reconnects — multi-account / non-default-index
  /// wallets would silently revert to the default path otherwise.
  void setBitbox(BitboxManager connection, [String? derivationPath_]) {
    bitboxManager = connection;
    derivationPath = derivationPath_ ?? derivationPath ?? _defaultDerivationPath;
  }

  void clearBitbox() {
    bitboxManager = null;
    // Keep [derivationPath] so a re-attach via setBitbox() with no path argument
    // restores the same one the caller originally chose.
  }

  // The two synchronous Credentials entry points — signToEcSignature and
  // signPersonalMessageToUint8List — are inherited from the web3dart
  // `CredentialsWithKnownAddress` interface but never invoked on a Bitbox:
  // every BitBox sign path goes through the asynchronous variants
  // (signToSignature / signPersonalMessage) because the underlying native
  // call requires an awaitable BLE/USB round-trip. The sync overrides exist
  // only to satisfy the interface and surface as `UnimplementedError` if a
  // future refactor wires a sync caller onto BitBox credentials by accident.
  // Covered by a `throwsA(isA<UnimplementedError>())` test rather than hidden
  // behind `coverage:ignore` — same convention as `_DebugCredentials` in
  // `wallet.dart`, whose sync entry points are also unit-tested.
  @override
  MsgSignature signToEcSignature(Uint8List payload, {int? chainId, bool isEIP1559 = false}) =>
      throw UnimplementedError('EvmLedgerCredentials.signToEcSignature');

  @override
  Future<MsgSignature> signToSignature(
    Uint8List payload, {
    int? chainId,
    bool isEIP1559 = false,
  }) {
    return _synchronizeBoundedSign(() async {
      // Snapshot the manager + path up-front so an observer-driven null-out
      // between the connection check and the sign call doesn't NoSuchMethod.
      final manager = bitboxManager;
      final path = derivationPath;
      if (manager == null || path == null) {
        throw const BitboxNotConnectedException();
      }

      if (isEIP1559) payload = payload.sublist(1);
      final sig = await _runOrThrowDisconnect(
        manager,
        () => manager.signETHRLPTransaction(
          chainId ?? 1,
          path,
          bytesToHex(payload),
          isEIP1559,
        ),
      );

      final r = bytesToHex(sig.sublist(0, 32));
      final s = bytesToHex(sig.sublist(32, 32 + 32));
      final v = sig.last.toInt();

      if (isEIP1559) {
        return MsgSignature(BigInt.parse(r, radix: 16), BigInt.parse(s, radix: 16), v);
      }

      var truncChainId = chainId ?? 1;
      // Truncate chainIds wider than 32 bits down to the low byte for the
      // EIP-155 parity check — defensive against future >2^32 chainIds. No
      // chain we currently target (Mainnet=1, Polygon=137, Citrea, …) reaches
      // 2^32, so this loop does not iterate in production today, but it is real
      // testable arithmetic and is exercised by a >2^32-chainId unit test.
      while (truncChainId.bitLength > 32) {
        truncChainId >>= 8;
      }

      final truncTarget = truncChainId * 2 + 35;

      int parity = v;
      if (truncTarget & 0xff == v) {
        parity = 0;
      } else if ((truncTarget + 1) & 0xff == v) {
        parity = 1;
      }

      // https://github.com/ethereumjs/ethereumjs-util/blob/8ffe697fafb33cefc7b7ec01c11e3a7da787fe0e/src/signature.ts#L26
      final chainIdV = chainId != null ? (parity + (chainId * 2 + 35)) : parity;

      return MsgSignature(BigInt.parse(r, radix: 16), BigInt.parse(s, radix: 16), chainIdV);
    });
  }

  @override
  Future<Uint8List> signPersonalMessage(Uint8List payload, {int? chainId}) {
    return _synchronizeBoundedSign(() async {
      final manager = bitboxManager;
      final path = derivationPath;
      if (manager == null || path == null) {
        throw const BitboxNotConnectedException();
      }
      return await _runOrThrowDisconnect(
        manager,
        () => manager.signETHMessage(chainId ?? 1, path, payload),
      );
    });
  }

  // See the block comment on `signToEcSignature` above — same rationale: the
  // synchronous variant is never used on a Bitbox, every sign path goes
  // through the awaitable `signPersonalMessage` because the native call
  // crosses the BLE/USB transport. Covered by a unit test, not ignored.
  @override
  Uint8List signPersonalMessageToUint8List(Uint8List payload, {int? chainId}) =>
      throw UnimplementedError('EvmLedgerCredentials.signPersonalMessageToUint8List');

  Future<String> signTypedDataV4(int chainId, String jsonData) {
    return _synchronizeBoundedSign(() async {
      final manager = bitboxManager;
      final path = derivationPath;
      if (manager == null || path == null) {
        throw const BitboxNotConnectedException();
      }

      final signatureBytes = await _runOrThrowDisconnect(
        manager,
        () => manager.signETHTypedMessage(
          chainId,
          path,
          Uint8List.fromList(utf8.encode(jsonData)),
        ),
      );
      return '0x${convert.hex.encode(signatureBytes)}';
    });
  }

  /// Wraps a sign call so a BLE/USB drop mid-operation surfaces as
  /// [BitboxNotConnectedException]. Narrowed to [Exception] so genuine bugs
  /// in the sign path (encoding error, type cast, assert) keep their type
  /// and stack instead of being silently re-labelled as a disconnect.
  Future<T> _runOrThrowDisconnect<T>(
    BitboxManager manager,
    Future<T> Function() op,
  ) async {
    try {
      return await op();
    } on Exception catch (e, st) {
      if (await _deviceLost(manager)) {
        developer.log(
          'sign failed during disconnect: $e',
          name: '$BitboxCredentials',
          error: e,
          stackTrace: st,
        );
        clearBitbox();
        throw const BitboxNotConnectedException();
      }
      rethrow;
    }
  }

  Future<bool> _deviceLost(BitboxManager manager) async {
    try {
      final devices = await manager.devices;
      return devices.isEmpty;
    } on Exception {
      // Probing the device list itself failed — treat as lost.
      return true;
    }
  }

  bool get isConnected => bitboxManager != null;
}
