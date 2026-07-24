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

  Future<String> signRegistration() => Eip712Signer.signRegistration(
    credentials: connected(),
    chainId: 1,
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
    test('signs with the chainId-extended EIP-712 domain', () async {
      when(
        () => manager.signETHTypedMessage(any(), any(), any()),
      ).thenAnswer((_) async => Uint8List.fromList([0x01]));

      await signRegistration();

      final jsonMessage =
          verify(() => manager.signETHTypedMessage(any(), any(), captureAny())).captured.single as Uint8List;
      final typedData = jsonDecode(utf8.decode(jsonMessage)) as Map<String, dynamic>;
      expect(typedData['domain']['chainId'], 1);
      expect(
        (typedData['types']['EIP712Domain'] as List).map((e) => e['name']),
        containsAll(['name', 'version', 'chainId']),
      );
    });

    test('throws SigningCancelledException on empty signature', () async {
      when(
        () => manager.signETHTypedMessage(any(), any(), any()),
      ).thenAnswer((_) async => Uint8List(0));
      await expectLater(signRegistration(), throwsA(isA<SigningCancelledException>()));
    });
  });
}
