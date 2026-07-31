/// Firmware-compatibility policy for the one BitBox operation this app cannot
/// perform on the firmware we have measured.
///
/// The registration envelope's EIP-712 domain carries only `name` and
/// `version` — no `chainId` (see `Eip712Signer.signRegistration`). A
/// chainId-less domain makes the device raise a "Typed data has no chain ID"
/// warning screen, and confirming it answers with a NACK instead of a
/// signature when the device is reached over Bluetooth.
///
/// Measured on hardware 2026-07-30 (BitBox02 Nova `bb02p-multi`, main firmware
/// v9.26.4), two independent runs of every BitBox operation the app performs:
///
/// | operation                        | Bluetooth | USB |
/// |----------------------------------|-----------|-----|
/// | chainId-less typed data          | 4 of 4 NACK | signs |
/// | chainId-bearing typed data       | signs     | signs |
/// | personal message (login)         | signs     | signs |
/// | EIP-1559 transaction             | signs*    | signs |
/// | address / status / enumerate     | ok        | ok   |
///
/// (*) One transaction NACK was seen across three attempts, preceded by a
/// 539 ms host poll interval — past the device's 500 ms watchdog. That is a
/// host-scheduling hiccup rather than this bug, so it is deliberately NOT
/// gated: it usually succeeds and a version gate would not address the cause.
///
/// Upstream: BitBoxSwiss/bitbox02-firmware#2019.
abstract final class BitboxFirmware {
  /// Versions **measured** to refuse the registration envelope.
  ///
  /// This is an allowlist of known-bad builds, deliberately not a "below
  /// version X" range. We do not know which release carries the fix — the
  /// upstream issue is still open, and BitBox's own draft changelog attributes
  /// it to "slow securechip operations", a description our measurements
  /// contradict (a chainId-bearing envelope signs after 12 s, while the
  /// chainId-less one fails after 2.5 s). Guessing a fix version would either
  /// let a still-broken build through or block a working one.
  ///
  /// Older firmware is likewise absent because we never tested it. Add an
  /// entry only when a build has actually been observed to fail.
  static const affectedVersions = <(int, int, int)>{
    (9, 26, 4),
  };

  /// Whether a device reporting [version] is a build we have measured to
  /// refuse the registration signature.
  ///
  /// [version] is what the plugin reports, e.g. `"v9.26.4"`.
  ///
  /// Everything we have not measured is treated as working: null (only the USB
  /// transport reports null, and every USB operation was verified working), an
  /// unparseable string, and any version not in [affectedVersions]. The gate
  /// exists to explain one known failure, not to speculate about builds we
  /// have never seen.
  static bool refusesChainIdLessTypedData(String? version) {
    if (version == null) return false;

    final parsed = parseVersion(version);
    if (parsed == null) return false;

    return affectedVersions.contains(parsed);
  }

  /// Parses `"v9.26.4"` or `"9.26.4"` into its numeric parts, tolerating a
  /// trailing pre-release suffix such as `"v9.26.5-rc1"`. Null when the string
  /// is not a recognisable three-part version.
  static (int, int, int)? parseVersion(String version) {
    final match = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)').firstMatch(version.trim());
    if (match == null) return null;

    final major = int.tryParse(match.group(1)!);
    final minor = int.tryParse(match.group(2)!);
    final patch = int.tryParse(match.group(3)!);
    if (major == null || minor == null || patch == null) return null;

    return (major, minor, patch);
  }
}
