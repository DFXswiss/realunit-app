import 'dart:convert';
import 'dart:typed_data';

import 'package:bitbox_flutter/bitbox_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/hardware_wallet/bitbox_credentials.dart';
import 'package:realunit_wallet/packages/wallet/eip712_signer.dart';
import 'package:realunit_wallet/packages/wallet/exceptions/signing_cancelled_exception.dart';

class _MockBitboxManager extends Mock implements BitboxManager {}

void main() {
  late _MockBitboxManager manager;

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    manager = _MockBitboxManager();
  });

  BitboxCredentials connected() =>
      BitboxCredentials('0x000000000000000000000000000000000000dead')..setBitbox(manager);

  Future<String> signRegistration({int chainId = 1}) => Eip712Signer.signRegistration(
    credentials: connected(),
    chainId: chainId,
    email: 'jk@dfx.swiss',
    name: 'Joshua',
    type: 'human',
    phoneNumber: '+41000000000',
    birthday: '1990-01-01',
    nationality: 'CH',
    addressStreet: 'Bahnhofstrasse 1',
    addressPostalCode: '8001',
    addressCity: 'Zurich',
    addressCountry: 'CH',
    swissTaxResidence: true,
    registrationDate: '2026-05-14',
  );

  group('$Eip712Signer with BitboxCredentials', () {
    test('signs RealUnitUser registration via signTypedDataV4', () async {
      when(
        () => manager.signETHTypedMessage(any(), any(), any()),
      ).thenAnswer((_) async => Uint8List.fromList([0xCA, 0xFE, 0xBA, 0xBE]));
      expect(await signRegistration(), '0xcafebabe');
    });

    // The BitBox02 firmware rejects typed data whose EIP712Domain has no
    // chainId ("typed data has no chain ID" on the device) — hardware-wallet
    // registrations must sign the chainId-extended domain. The software-wallet
    // path keeps the legacy domain (pinned by the golden signature in
    // eip712_signer_test.dart).
    // Signs with a non-default chainId so a hardcoded value cannot pass, and asserts the
    // EIP712Domain member list exactly: the domain typehash covers the names, their types
    // and their order, so any of those drifting changes the digest and the API recovers a
    // foreign address. Mirrors the chainId-wiring pin in
    // test/integration/eip7702_delegation_bitbox_test.dart.
    for (final chainId in const [1, 11155111]) {
      test('signs with the chainId-extended EIP-712 domain (chainId $chainId)', () async {
        when(
          () => manager.signETHTypedMessage(any(), any(), any()),
        ).thenAnswer((_) async => Uint8List.fromList([0x01]));

        await signRegistration(chainId: chainId);

        // called(1): a second sign would mean a second on-device confirmation prompt.
        final captured = (verify(
          () => manager.signETHTypedMessage(captureAny(), any(), captureAny()),
        )..called(1)).captured;
        final typedData = jsonDecode(utf8.decode(captured[1] as Uint8List)) as Map<String, dynamic>;

        expect(captured[0], chainId);
        expect(typedData['domain']['chainId'], chainId);
        expect(typedData['types']['EIP712Domain'], [
          {'name': 'name', 'type': 'string'},
          {'name': 'version', 'type': 'string'},
          {'name': 'chainId', 'type': 'uint256'},
        ]);
      });
    }

    test('throws SigningCancelledException on empty signature', () async {
      when(
        () => manager.signETHTypedMessage(any(), any(), any()),
      ).thenAnswer((_) async => Uint8List(0));
      await expectLater(signRegistration(), throwsA(isA<SigningCancelledException>()));
    });
  });
}
