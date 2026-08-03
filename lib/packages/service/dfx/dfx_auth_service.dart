import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;
import 'package:realunit_wallet/packages/config/api_config.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/address_already_linked_exception.dart';
import 'package:realunit_wallet/packages/service/wallet_service.dart';
import 'package:realunit_wallet/packages/wallet/exceptions/signing_cancelled_exception.dart';
import 'package:realunit_wallet/packages/wallet/wallet_account.dart';

/// Fire-and-forget pre-warm of the auth signature, shared by every onboarding
/// flow (create / restore / BitBox-pair). The lazy path in
/// [DFXAuthService.getSignature] is still the safety net — this just primes
/// the cache so the first authenticated call doesn't have to round-trip
/// through the hardware wallet again. Failures surface at SEVERE so support
/// has a debug-log breadcrumb when a fresh BitBox confirmation pops up
/// unexpectedly on the next call.
Future<void> warmAuthSignature(
  DFXAuthService authService,
  AWalletAccount account, {
  required String loggerName,
}) async {
  try {
    await authService.ensureSignatureFor(account);
  } catch (e) {
    developer.log(
      'initial signature capture failed — next authenticated call '
      'will trigger a fresh signature request: $e',
      name: loggerName,
      level: 1000, // SEVERE
    );
  }
}

abstract class DFXAuthService {
  static const walletName = 'RealUnit';
  static const _signMessageTimeout = Duration(minutes: 3);
  static const _httpTimeout = Duration(seconds: 20);

  /// Auth sign-in message body (without environment scoping), derived
  /// locally from the address. Mirrors the server's
  /// `Config.auth.signMessageGeneral` template (DFXswiss/api): the backend
  /// re-derives this string from the address on every verify (stateless, no
  /// nonce) and accepts it, so there is no need to first round-trip through
  /// `GET /v1/auth/signMessage`. Dropping that call also removes a
  /// network-timeout failure mode from the onboarding/pairing flow.
  ///
  /// Non-PRD environments prefix the full message with `[<env>]_` via
  /// [buildSignMessage] so a signature from one environment cannot
  /// authenticate on another (api `signMessagePrefix`); PRD keeps this
  /// historical body byte-for-byte.
  static const _signMessagePrefix =
      'By_signing_this_message,_you_confirm_that_you_are_the_sole_owner_'
      'of_the_provided_Blockchain_address._Your_ID:_';

  final String authPath = '/v1/auth';
  final AppStore appStore;
  final WalletService walletService;

  DFXAuthService(this.appStore, this.walletService);

  String get host => appStore.apiConfig.apiHost;

  AWalletAccount get wallet => appStore.wallet.currentAccount;

  String get walletAddress => wallet.primaryAddress.address.hexEip55;

  String getSignMessage() => buildSignMessage(walletAddress);

  /// Mirrors the server template INCLUDING its environment scoping (DFXswiss/api
  /// config.ts `signMessagePrefix`): non-PRD environments prefix the message
  /// with `[<env>]_` so a signature from one environment cannot authenticate on
  /// another; PRD keeps the historical text byte-for-byte. The app only ever
  /// talks to dev (testnet) or prd (mainnet), so the dev prefix is the single
  /// non-PRD case here.
  String buildSignMessage(String address) =>
      '${appStore.apiConfig.networkMode.isTestnet ? '[dev]_' : ''}$_signMessagePrefix$address';

  /// Authenticates [account]'s address against `POST /v1/auth` while sending
  /// [linkBearerToken] (the JWT of the CURRENTLY signed-in wallet) as
  /// Authorization header. The API's OptionalJwtAuthGuard then creates the new
  /// address under the SAME UserData as the token owner (DFXswiss/api
  /// auth.controller → authenticate(dto, ip, jwt?.account, jwt?.user)), which is
  /// what makes the one-tap ADD_WALLET registration state reachable for the new
  /// address. Returns the access token issued FOR THE NEW ADDRESS. The returned
  /// token is intentionally NOT written to the session cache — the caller owns
  /// the decision when the app switches identity.
  /// Throws [AddressAlreadyLinkedException] on 409 (address belongs to another
  /// account), [SigningCancelledException] on empty/cancelled signature.
  Future<String> authenticateLinkedAccount(
    AWalletAccount account,
    String linkBearerToken,
  ) async {
    final address = account.primaryAddress.address.hexEip55;

    await appStore.sessionCache.loadSignature();
    final cachedSignature = appStore.sessionCache.signature;
    final signatureAddress = appStore.sessionCache.signatureAddress;
    late final String signature;
    if (cachedSignature != null && signatureAddress == address) {
      signature = cachedSignature;
    } else {
      signature = await account
          .signMessage(buildSignMessage(address))
          .timeout(_signMessageTimeout);
      if (signature.isEmpty || signature == '0x') {
        throw const SigningCancelledException();
      }
      await appStore.sessionCache.saveSignature(address, signature);
    }

    final requestBody = jsonEncode({
      'wallet': walletName,
      'address': address,
      'signature': signature,
    });

    final uri = buildUri(host, authPath);
    final response = await appStore.httpClient
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $linkBearerToken',
          },
          body: requestBody,
        )
        .timeout(_httpTimeout);

    if (response.statusCode == 201) {
      final responseBody = jsonDecode(response.body) as Map<String, dynamic>;
      return responseBody['accessToken'] as String;
    } else if (response.statusCode == 409) {
      throw const AddressAlreadyLinkedException();
    } else {
      throw Exception(
        'Failed to link address. Status: ${response.statusCode} ${response.body}',
      );
    }
  }

  /// Create-and-persist the auth signature for [account] without going through
  /// `appStore.wallet`. Used during the BitBox pairing flow so the signature is
  /// captured while the hardware wallet is guaranteed connected — every
  /// subsequent buy / KYC / user-data call can then run off the cached
  /// signature without needing the BitBox.
  ///
  /// No-op if a signature for this address is already in the cache.
  Future<void> ensureSignatureFor(AWalletAccount account) async {
    final address = account.primaryAddress.address.hexEip55;
    await appStore.sessionCache.loadSignature();
    if (appStore.sessionCache.signature != null &&
        appStore.sessionCache.signatureAddress == address) {
      return;
    }

    final message = buildSignMessage(address);
    final signature = await account.signMessage(message).timeout(_signMessageTimeout);
    if (signature.isEmpty || signature == '0x') {
      throw const SigningCancelledException();
    }
    await appStore.sessionCache.saveSignature(address, signature);
  }

  // Exceptions this method can throw on the BitBox path:
  //   * `BitboxNotConnectedException` — `BitboxCredentials.signPersonalMessage`
  //     aborts up front when the device is disconnected (BLE link dropped).
  //   * `SigningCancelledException` — the user cancels on the device, so the
  //     BitBox swift wrapper returns empty bytes / `'0x'`, normalised here.
  //   * `TimeoutException` — the user never confirms within `_signMessageTimeout`.
  Future<String> getSignature(String message) async {
    final cached = appStore.sessionCache.signature;
    final cachedAddress = appStore.sessionCache.signatureAddress;
    if (cached != null && cachedAddress == walletAddress) {
      return cached;
    }

    // Cache miss — we actually need the private key. Decrypt the mnemonic on
    // demand if the currently loaded wallet is a view-only software wallet.
    // try/finally so a throw from sign / saveSignature can't leave the mnemonic
    // resident for the 60 s idle window — matches the pattern in
    // RealUnitSellPaymentInfoService.confirmPayment and
    // RealUnitRegistrationService.completeRegistration / registerWallet.
    await walletService.ensureCurrentWalletUnlocked();
    try {
      final signature = await wallet.signMessage(message).timeout(_signMessageTimeout);
      if (signature.isEmpty || signature == '0x') {
        throw const SigningCancelledException();
      }
      await appStore.sessionCache.saveSignature(walletAddress, signature);
      return signature;
    } finally {
      await walletService.lockCurrentWallet();
    }
  }

  Future<Map<String, dynamic>> getAuthResponse([bool sendWalletName = true]) async {
    final signature = await getSignature(getSignMessage());

    final requestBody = jsonEncode(
      sendWalletName
          ? {
              'wallet': walletName,
              'address': walletAddress,
              'signature': signature,
            }
          : {
              'address': walletAddress,
              'signature': signature,
            },
    );

    final uri = buildUri(host, authPath);
    final response = await appStore.httpClient
        .post(uri, headers: {'Content-Type': 'application/json'}, body: requestBody)
        .timeout(_httpTimeout);

    if (response.statusCode == 201) {
      final responseBody = jsonDecode(response.body);
      return responseBody as Map<String, dynamic>;
    } else if (response.statusCode == 403) {
      final responseBody = jsonDecode(response.body);
      final message = responseBody['message'] ?? 'Service unavailable in your country';
      throw Exception(message);
    } else {
      throw Exception('Failed to sign up. Status: ${response.statusCode} ${response.body}');
    }
  }

  // The BitBox-credentials skip introduced in PR #304 is no longer needed:
  // bitbox_flutter v0.0.2 fixed the BLE force-unwrap and dedup hang, the
  // empty-signature guard in `getSignature` covers the cancel/disconnect
  // case gracefully, and the SDK no longer panics on NACK.
  Future<String?> getAuthToken() async {
    if (appStore.sessionCache.authToken == null) {
      await appStore.sessionCache.loadSignature();
      final response = await getAuthResponse();
      appStore.sessionCache.setAuthToken(response['accessToken'] as String);
    }
    return appStore.sessionCache.authToken;
  }

  void invalidateAuthToken() => appStore.sessionCache.clearAuthToken();

  Future<String?> refreshAuthToken() async {
    invalidateAuthToken();
    return getAuthToken();
  }

  /// When [bearerTokenOverride] is non-null it is used verbatim and the
  /// 401-refresh path is skipped (a refresh would mint a token for the
  /// CURRENT wallet — wrong context for an override call). `null` keeps
  /// today's session-token + one-shot 401-refresh behaviour.
  Future<http.Response> authenticatedGet(
    Uri uri, {
    Map<String, String> headers = const {},
    String? bearerTokenOverride,
  }) {
    return _authenticated(
      (token) => appStore.httpClient.get(
        uri,
        headers: {
          ...headers,
          'Authorization': 'Bearer $token',
        },
      ),
      bearerTokenOverride: bearerTokenOverride,
    );
  }

  /// When [bearerTokenOverride] is non-null it is used verbatim and the
  /// 401-refresh path is skipped (a refresh would mint a token for the
  /// CURRENT wallet — wrong context for an override call). `null` keeps
  /// today's session-token + one-shot 401-refresh behaviour.
  Future<http.Response> authenticatedPut(
    Uri uri, {
    Map<String, String> headers = const {},
    Object? body,
    Encoding? encoding,
    String? bearerTokenOverride,
  }) {
    return _authenticated(
      (token) => appStore.httpClient.put(
        uri,
        headers: {
          ...headers,
          'Authorization': 'Bearer $token',
        },
        body: body,
        encoding: encoding,
      ),
      bearerTokenOverride: bearerTokenOverride,
    );
  }

  /// When [bearerTokenOverride] is non-null it is used verbatim and the
  /// 401-refresh path is skipped (a refresh would mint a token for the
  /// CURRENT wallet — wrong context for an override call). `null` keeps
  /// today's session-token + one-shot 401-refresh behaviour.
  Future<http.Response> authenticatedPost(
    Uri uri, {
    Map<String, String> headers = const {},
    Object? body,
    Encoding? encoding,
    String? bearerTokenOverride,
  }) {
    return _authenticated(
      (token) => appStore.httpClient.post(
        uri,
        headers: {
          ...headers,
          'Authorization': 'Bearer $token',
        },
        body: body,
        encoding: encoding,
      ),
      bearerTokenOverride: bearerTokenOverride,
    );
  }

  /// Runs [request] with a Bearer token and retries once on a 401 with a
  /// refreshed token. The caller is responsible for passing the token into
  /// the request headers (so each verb can keep its own `body`/`encoding`
  /// arguments without us re-serialising them here).
  ///
  /// When [bearerTokenOverride] is non-null that exact token is used and the
  /// 401-refresh is skipped — a refresh would mint a token for the CURRENT
  /// wallet, which is the wrong identity for an override-scoped call. The
  /// 401 response is returned to the caller unchanged.
  Future<http.Response> _authenticated(
    Future<http.Response> Function(String? token) request, {
    String? bearerTokenOverride,
  }) async {
    if (bearerTokenOverride != null) {
      return request(bearerTokenOverride);
    }

    var authToken = await getAuthToken();
    var response = await request(authToken);

    if (response.statusCode == 401) {
      authToken = await refreshAuthToken();
      response = await request(authToken);
    }

    return response;
  }
}
