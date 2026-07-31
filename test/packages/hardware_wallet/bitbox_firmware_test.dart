import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/packages/hardware_wallet/bitbox_firmware.dart';

void main() {
  group('parseVersion', () {
    test('parses the plugin format with a leading v', () {
      expect(BitboxFirmware.parseVersion('v9.26.4'), (9, 26, 4));
    });

    test('parses a bare version', () {
      expect(BitboxFirmware.parseVersion('9.26.4'), (9, 26, 4));
    });

    test('tolerates surrounding whitespace', () {
      expect(BitboxFirmware.parseVersion('  v9.26.4 '), (9, 26, 4));
    });

    test('tolerates a pre-release suffix', () {
      expect(BitboxFirmware.parseVersion('v9.26.5-rc1'), (9, 26, 5));
    });

    test('parses multi-digit parts', () {
      expect(BitboxFirmware.parseVersion('v10.100.200'), (10, 100, 200));
    });

    test('rejects a two-part version', () {
      expect(BitboxFirmware.parseVersion('v9.26'), isNull);
    });

    test('rejects a non-version string', () {
      expect(BitboxFirmware.parseVersion('bb02p-multi'), isNull);
    });

    test('rejects an empty string', () {
      expect(BitboxFirmware.parseVersion(''), isNull);
    });
  });

  group('refusesChainIdLessTypedData', () {
    test('the measured failing firmware is affected', () {
      expect(BitboxFirmware.refusesChainIdLessTypedData('v9.26.4'), isTrue);
    });

    test('accepts the bare form of the affected version', () {
      expect(BitboxFirmware.refusesChainIdLessTypedData('9.26.4'), isTrue);
    });

    // Everything below is the deliberate policy: only builds we have actually
    // measured are gated. We do not know which release carries the fix, so a
    // "below version X" range would be a guess in code.
    test('a later patch is not gated', () {
      expect(BitboxFirmware.refusesChainIdLessTypedData('v9.26.5'), isFalse);
    });

    test('a later minor is not gated', () {
      expect(BitboxFirmware.refusesChainIdLessTypedData('v9.27.0'), isFalse);
    });

    test('a later major is not gated', () {
      expect(BitboxFirmware.refusesChainIdLessTypedData('v10.0.0'), isFalse);
    });

    test('an untested earlier version is not gated', () {
      // We never measured 9.25.1. It may well be affected, but the gate states
      // what we know, not what we suspect.
      expect(BitboxFirmware.refusesChainIdLessTypedData('v9.25.1'), isFalse);
    });

    test('an untested much earlier version is not gated', () {
      expect(BitboxFirmware.refusesChainIdLessTypedData('v8.99.99'), isFalse);
    });

    test('null is not gated — USB cannot report a version, and every USB '
        'operation was verified working', () {
      expect(BitboxFirmware.refusesChainIdLessTypedData(null), isFalse);
    });

    test('an unparseable version is not gated', () {
      expect(BitboxFirmware.refusesChainIdLessTypedData('garbage'), isFalse);
    });

    test('the affected set contains exactly the measured build', () {
      // Tripwire: adding a version here without hardware evidence should be a
      // conscious act, not a silent widening of the gate.
      expect(BitboxFirmware.affectedVersions, {(9, 26, 4)});
    });
  });
}
