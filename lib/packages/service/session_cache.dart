import 'package:realunit_wallet/packages/repository/cache_repository.dart';

class SessionCache {
  static const _signatureKey = 'cached_signature';
  static const _signatureAddressKey = 'cached_signature_address';
  static const _signatureMessageKey = 'cached_signature_message';

  final CacheRepository _cacheRepository;

  SessionCache(CacheRepository cacheRepository) : _cacheRepository = cacheRepository;

  String? _authToken;
  String? _authTokenAddress;
  String? _signature;
  String? _signatureAddress;
  String? _signedMessage;

  String? get authToken => _authToken;
  String? get authTokenAddress => _authTokenAddress;
  String? get signature => _signature;
  String? get signatureAddress => _signatureAddress;
  String? get signedMessage => _signedMessage;

  void setAuthToken(String token, String address) {
    _authToken = token;
    _authTokenAddress = address;
  }

  void clearAuthToken() {
    _authToken = null;
    _authTokenAddress = null;
  }

  Future<void> saveSignature(
    String address,
    String signature, [
    String? signedMessage,
  ]) async {
    final message = signedMessage ??
        (_signatureAddress == address && _signature == signature ? _signedMessage : null);
    _signature = signature;
    _signatureAddress = address;
    _signedMessage = message;
    await _cacheRepository.write(_signatureKey, signature);
    await _cacheRepository.write(_signatureAddressKey, address);
    if (message != null) {
      await _cacheRepository.write(_signatureMessageKey, message);
    } else {
      await _cacheRepository.delete(_signatureMessageKey);
    }
  }

  Future<void> loadSignature() async {
    _signature ??= await _cacheRepository.read(_signatureKey);
    _signatureAddress ??= await _cacheRepository.read(_signatureAddressKey);
    _signedMessage ??= await _cacheRepository.read(_signatureMessageKey);
  }

  Future<void> clear() async {
    _signature = null;
    _signatureAddress = null;
    _signedMessage = null;
    clearAuthToken();
    await _cacheRepository.delete(_signatureKey);
    await _cacheRepository.delete(_signatureAddressKey);
    await _cacheRepository.delete(_signatureMessageKey);
  }
}
