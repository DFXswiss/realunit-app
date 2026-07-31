import 'dart:async';
import 'dart:developer' as developer;

import 'package:bitbox_flutter/bitbox_flutter.dart';
import 'package:realunit_wallet/packages/hardware_wallet/bitbox_credentials.dart';
import 'package:realunit_wallet/packages/hardware_wallet/bitbox_firmware.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/bitbox_address_unavailable_exception.dart';

class BitboxService {
  // ETH's canonical BIP-44 derivation path. Centralised here so the create
  // and heal flows share one literal — a drift between them would quote two
  // different addresses for the same device.
  static const _ethDerivationPath = "m/44'/60'/0'/0/0";

  // Observer poll period is widened in production and tightened in tests so
  // device-loss-recovery behaviour can be exercised in real time without
  // five-second sleeps.
  BitboxService({Duration connectionStatusInterval = const Duration(seconds: 5)})
    : _connectionStatusInterval = connectionStatusInterval;

  final BitboxManager bitboxManager = BitboxManager();
  final Duration _connectionStatusInterval;
  bool _isConnected = false;
  // Keyed by the lowercased address so multi-wallet (future) reconnect
  // re-attaches every active set of credentials, not just the most recently
  // handed out. Lowercase invariant: callers may hand in EIP-55-mixed or raw
  // hex — we normalise via [_key] on every read/write so a checksum-flip
  // can't fork the map.
  final Map<String, BitboxCredentials> _credentialsByAddress = {};
  Timer? _connectionStatusObserver;
  Future<void>? _pendingDisconnect;
  String? _firmwareVersion;

  /// The paired device's main firmware version, e.g. `"v9.26.4"`, captured at
  /// pairing. Null before pairing, and on the USB transport, which cannot
  /// report one — see [BitboxFirmware.refusesChainIdLessTypedData] for why the
  /// two are not equivalent.
  String? get firmwareVersion => _firmwareVersion;

  /// Whether the paired device will refuse the registration signature.
  ///
  /// Read from the cached version rather than the device, so the KYC flow can
  /// gate without holding a live connection.
  bool get refusesRegistrationSignature =>
      BitboxFirmware.refusesChainIdLessTypedData(_firmwareVersion);

  /// Normalises an address into the form used as the map key. Lowercase is
  /// the cheapest robust choice — EIP-55 checksum differs in casing only, so
  /// `0xAbC` and `0xabc` collapse to the same entry.
  String _key(String address) => address.toLowerCase();

  Future<List<BitboxDevice>> getAllUsbDevices() => bitboxManager.devices;

  Future<bool> startScan() => bitboxManager.startScan();

  BitboxCredentials getCredentials(String address) {
    final credentials = _credentialsByAddress.putIfAbsent(
      _key(address),
      () => BitboxCredentials(address),
    );
    if (_isConnected) {
      credentials.setBitbox(bitboxManager);
    }
    return credentials;
  }

  Future<bool> init(BitboxDevice device) async {
    // The disconnect observer fires .disconnect() asynchronously when the
    // device drops. If the user re-plugs immediately we'd race two ops on the
    // same SDK manager and the result is undefined. Wait for any in-flight
    // disconnect to finish first.
    await _pendingDisconnect;
    await bitboxManager.connect(device);
    final didInit = await bitboxManager.initBitBox();
    if (!didInit) throw Exception('Failed to init');
    _isConnected = true;
    // Captured once per pairing. On Bluetooth the version rides on the product
    // characteristic, which the peripheral publishes on connect, so this costs
    // no device round-trip. Swallow failures: a version we could not read must
    // never be the reason pairing fails — the firmware gate downstream decides
    // what an unknown version means.
    try {
      _firmwareVersion = await bitboxManager.getFirmwareVersion();
    } on Exception catch (e) {
      developer.log('BitboxService: firmware version unavailable: $e');
      _firmwareVersion = null;
    }
    // Re-attach the manager to every active credentials instance so existing
    // wallets heal automatically on reconnect. The previous derivationPath is
    // preserved inside setBitbox().
    for (final credentials in _credentialsByAddress.values) {
      credentials.setBitbox(bitboxManager);
    }
    return didInit;
  }

  void startConnectionStatusObserver() {
    _connectionStatusObserver?.cancel();
    _connectionStatusObserver = Timer.periodic(_connectionStatusInterval, (_) async {
      final List<BitboxDevice> devices;
      try {
        devices = await getAllUsbDevices();
      } catch (e) {
        // Transient BLE/USB hiccups inside the periodic callback used to
        // surface as uncaught async errors and kill the recovery loop. Log
        // and wait for the next tick — only an explicit empty device list
        // is allowed to trigger the device-loss path below.
        developer.log('device probe failed in observer tick: $e', name: '$BitboxService');
        return;
      }
      if (devices.isEmpty) {
        // Two ticks can fire back-to-back if the body's awaits straddle the
        // next interval — bail if the previous tick already entered the
        // device-loss path. _isConnected acts as the single-writer flag
        // because we set it to false before any further work.
        if (!_isConnected) return;
        _isConnected = false;
        for (final credentials in _credentialsByAddress.values) {
          credentials.clearBitbox();
        }
        stopConnectionStatusObserver();
        // Close the underlying transport. Required on Android so the USB
        // file-descriptor is released — otherwise the next connect() can
        // fail because the OS still considers the device claimed. Safe on
        // iOS where the BLE link is already gone at this point.
        _pendingDisconnect = _disconnectAndForget();
        await _pendingDisconnect;
        _pendingDisconnect = null;
      }
    });
  }

  Future<void> _disconnectAndForget() async {
    try {
      await bitboxManager.disconnect();
    } on Exception catch (e) {
      developer.log('disconnect after device-loss failed: $e', name: '$BitboxService');
    }
  }

  void stopConnectionStatusObserver() {
    _connectionStatusObserver?.cancel();
    _connectionStatusObserver = null;
  }

  /// Get channel hash - this is shown on the BitBox device
  Future<String> getChannelHash() async {
    final hash = await bitboxManager.getChannelHash();
    return hash;
  }

  /// Confirm pairing after user verified on BitBox device
  Future<void> confirmPairing() async {
    final didVerify = await bitboxManager.channelHashVerify();
    if (!didVerify) throw Exception('Failed to verify');
  }

  /// The paired device's firmware status (`uninitialized` / `seeded` /
  /// `initialized`). Read after pairing to tell a device with no wallet set up
  /// (`uninitialized` — cannot derive an address) apart from a ready device.
  /// Delegates to the plugin's cached-status read, so there is no device
  /// round-trip and it cannot block.
  Future<String> getDeviceStatus() => bitboxManager.getDeviceStatus();

  /// Derives the wallet's ETH address from the device, retrying transient empty
  /// reads before giving up.
  ///
  /// The SDK coerces a native `null` into `""` at the transport boundary
  /// (`bitbox_usb_method_channel.dart`'s `return result ?? ''`), so a device
  /// that isn't fully ready (e.g. a BLE stall right after channel-hash verify)
  /// resolves `getETHAddress` with an empty string instead of throwing. This is
  /// the single boundary through which create + heal fetch the address, so an
  /// empty read can never be persisted: a transient stall self-recovers across
  /// [attempts], and a persistent one throws [BitboxAddressUnavailableException]
  /// instead of handing back `""`.
  Future<String> getEthAddress({
    int attempts = 3,
    Duration retryDelay = const Duration(milliseconds: 200),
  }) async {
    for (var attempt = 0; attempt < attempts; attempt++) {
      final address = await bitboxManager.getETHAddress(1, _ethDerivationPath);
      if (address.isNotEmpty) return address;
      if (attempt < attempts - 1) await Future<void>.delayed(retryDelay);
    }
    throw const BitboxAddressUnavailableException();
  }
}
