import 'dart:convert';

import 'package:realunit_wallet/packages/config/api_config.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web3dart/web3dart.dart';

const _addressKey = 'debugAuthAddress';
const _signatureKey = 'debugAuthSignature';

class DebugAuthService {
  final AppStore _appStore;
  final SharedPreferences _prefs;
  String? _fetchedSignMessage;
  String? _fetchedSignMessageAddress;

  DebugAuthService(this._appStore, this._prefs);

  String? get savedAddress => _prefs.getString(_addressKey);

  String? get savedSignature => _prefs.getString(_signatureKey);

  Future<String> fetchSignMessage(String address) async {
    final uri = buildUri(
      _appStore.apiConfig.apiHost,
      '/v1/auth/signMessage',
      {'address': address},
    );
    final response = await _appStore.httpClient.get(
      uri,
      headers: {'accept': 'application/json'},
    );

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      final message = body['message'] as String;
      _fetchedSignMessage = message;
      _fetchedSignMessageAddress = address;
      return message;
    }
    throw Exception('Failed to fetch sign message (${response.statusCode})');
  }

  Future<void> authenticate(String address, String signature) async {
    final signedMessage = _fetchedSignMessageAddress == address ? _fetchedSignMessage : null;
    if (signedMessage == null) {
      throw StateError('No fetched sign message for address $address');
    }

    final uri = buildUri(_appStore.apiConfig.apiHost, '/v1/auth');
    final response = await _appStore.httpClient.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'wallet': 'RealUnit',
        'address': address,
        'signature': signature,
      }),
    );

    if (response.statusCode == 201) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final checksumAddress = EthereumAddress.fromHex(address).hexEip55;
      _appStore.sessionCache.setAuthToken(body['accessToken'] as String, checksumAddress);
      await _appStore.sessionCache.saveSignature(
        checksumAddress,
        signature,
        signedMessage,
      );
      await _prefs.setString(_addressKey, address);
      await _prefs.setString(_signatureKey, signature);
    } else {
      throw Exception('Auth failed (${response.statusCode}): ${response.body}');
    }
  }
}
