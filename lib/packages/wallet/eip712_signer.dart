import 'dart:convert';

import 'package:eth_sig_util_plus/eth_sig_util_plus.dart';
import 'package:realunit_wallet/packages/hardware_wallet/bitbox_credentials.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/dto/eip7702/eip7702_data_dto.dart';
import 'package:realunit_wallet/packages/wallet/exceptions/signing_cancelled_exception.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart';

class Eip712Signer {
  static Future<String> signRegistration({
    required CredentialsWithKnownAddress credentials,
    required int chainId,
    required String email,
    required String name,
    required String type,
    required String phoneNumber,
    required String birthday,
    required String nationality,
    required String addressStreet,
    required String addressPostalCode,
    required String addressCity,
    required String addressCountry,
    required bool swissTaxResidence,
    required String registrationDate,
  }) {
    // The BitBox02 firmware refuses to sign typed data whose EIP712Domain has
    // no chainId ("typed data has no chain ID" shown on the device), so
    // hardware wallets sign with the chainId-extended domain. Software wallets
    // keep the legacy chainId-less domain until Aktionariat has confirmed its
    // signature re-verification accepts the extended variant — the API
    // accepts both (pair PR DFXswiss/api#4354).
    final includeChainIdInDomain = credentials is BitboxCredentials;

    final Map<String, dynamic> typedDataMap = {
      'types': {
        'EIP712Domain': [
          {'name': 'name', 'type': 'string'},
          {'name': 'version', 'type': 'string'},
          if (includeChainIdInDomain) {'name': 'chainId', 'type': 'uint256'},
        ],
        'RealUnitUser': [
          {'name': 'email', 'type': 'string'},
          {'name': 'name', 'type': 'string'},
          {'name': 'type', 'type': 'string'},
          {'name': 'phoneNumber', 'type': 'string'},
          {'name': 'birthday', 'type': 'string'},
          {'name': 'nationality', 'type': 'string'},
          {'name': 'addressStreet', 'type': 'string'},
          {'name': 'addressPostalCode', 'type': 'string'},
          {'name': 'addressCity', 'type': 'string'},
          {'name': 'addressCountry', 'type': 'string'},
          {'name': 'swissTaxResidence', 'type': 'bool'},
          {'name': 'registrationDate', 'type': 'string'},
          {'name': 'walletAddress', 'type': 'address'},
        ],
      },
      'primaryType': 'RealUnitUser',
      'domain': {
        'name': 'RealUnitUser',
        'version': '1',
        if (includeChainIdInDomain) 'chainId': chainId,
      },
      'message': {
        'email': email,
        'name': name,
        'type': type,
        'phoneNumber': phoneNumber,
        'birthday': birthday,
        'nationality': nationality,
        'addressStreet': addressStreet,
        'addressPostalCode': addressPostalCode,
        'addressCity': addressCity,
        'addressCountry': addressCountry,
        'swissTaxResidence': swissTaxResidence,
        'registrationDate': registrationDate,
        'walletAddress': credentials.address.hexEip55,
      },
    };

    return _signTypedData(credentials, chainId, jsonEncode(typedDataMap));
  }

  static Future<String> signDelegation({
    required CredentialsWithKnownAddress credentials,
    required Eip7702Data eip7702Data,
  }) {
    final Map<String, dynamic> typedDataMap = {
      'types': {
        'EIP712Domain': [
          {'name': 'name', 'type': 'string'},
          {'name': 'version', 'type': 'string'},
          {'name': 'chainId', 'type': 'uint256'},
          {'name': 'verifyingContract', 'type': 'address'},
        ],
        'Delegation': eip7702Data.types.delegation
            .map((field) => {'name': field.name, 'type': field.type})
            .toList(),
        'Caveat': eip7702Data.types.caveat
            .map((field) => {'name': field.name, 'type': field.type})
            .toList(),
      },
      'primaryType': 'Delegation',
      'domain': {
        'name': eip7702Data.domain.name,
        'version': eip7702Data.domain.version,
        'chainId': eip7702Data.domain.chainId,
        'verifyingContract': eip7702Data.domain.verifyingContract,
      },
      'message': {
        'delegate': eip7702Data.message.delegate,
        'delegator': eip7702Data.message.delegator,
        'authority': eip7702Data.message.authority,
        'caveats': eip7702Data.message.caveats,
        'salt': eip7702Data.message.salt,
      },
    };

    return _signTypedData(credentials, eip7702Data.domain.chainId, jsonEncode(typedDataMap));
  }

  static Future<String> _signTypedData(
    CredentialsWithKnownAddress credentials,
    int chainId,
    String jsonData,
  ) async {
    final signature = await switch (credentials) {
      BitboxCredentials() => credentials.signTypedDataV4(chainId, jsonData),
      EthPrivateKey() => Future.value(
        EthSigUtil.signTypedData(
          privateKey: bytesToHex(credentials.privateKey, include0x: true),
          jsonData: jsonData,
          version: TypedDataVersion.V4,
        ),
      ),
      _ => throw UnsupportedError('Unsupported credentials type: ${credentials.runtimeType}'),
    };
    // The BitBox swift wrapper returns empty bytes ('0x') when the user
    // cancels on the device or the BLE link drops mid-sign; without this
    // guard the empty sig would be sent to the backend and the abort would
    // be misread as a successful sign.
    if (signature.isEmpty || signature == '0x') {
      throw const SigningCancelledException();
    }
    return signature;
  }
}
