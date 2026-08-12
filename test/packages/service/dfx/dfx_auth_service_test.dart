import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/config/api_config.dart';
import 'package:realunit_wallet/packages/config/network_mode.dart';
import 'package:realunit_wallet/packages/repository/cache_repository.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_auth_service.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/address_already_linked_exception.dart';
import 'package:realunit_wallet/packages/service/session_cache.dart';
import 'package:realunit_wallet/packages/service/wallet_service.dart';
import 'package:realunit_wallet/packages/wallet/exceptions/signing_cancelled_exception.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';
import 'package:realunit_wallet/packages/wallet/wallet_account.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart';

// ---------------------------------------------------------------------------
// Helpers — signature / cache surface (see `getSignature`, `getAuthToken`).
// ---------------------------------------------------------------------------

class _MockAppStore extends Mock implements AppStore {}

class _MockAWallet extends Mock implements AWallet {}

class _MockAWalletAccount extends Mock implements AWalletAccount {}

class _MockSessionCache extends Mock implements SessionCache {}

class _MockWalletService extends Mock implements WalletService {}

class _StubWalletAccount extends AWalletAccount {
  _StubWalletAccount(this._signature, {String? address})
    : _addressOverride = address,
      super(
        0,
        EthPrivateKey.fromHex(
          'fb1ace12f9801e85f3db1b3935dd47d9f064f98152466f47c701b5e12680e612',
        ),
      );

  final String _signature;
  final String? _addressOverride;
  int signCallCount = 0;

  @override
  CredentialsWithKnownAddress get primaryAddress {
    if (_addressOverride != null) {
      return _StubCredentials(_addressOverride);
    }
    return super.primaryAddress;
  }

  @override
  Future<String> signMessage(String message, {int addressIndex = 0}) async {
    signCallCount++;
    return _signature;
  }
}

class _LockedSnapshotWalletAccount extends _StubWalletAccount {
  _LockedSnapshotWalletAccount({required String address})
    : super('unused', address: address);

  @override
  Future<String> signMessage(String message, {int addressIndex = 0}) {
    throw StateError('locked snapshot account');
  }
}

class _StubCredentials extends CredentialsWithKnownAddress {
  _StubCredentials(String hexAddress) : _address = EthereumAddress.fromHex(hexAddress);

  final EthereumAddress _address;

  @override
  EthereumAddress get address => _address;

  @override
  MsgSignature signToEcSignature(
    Uint8List payload, {
    int? chainId,
    bool isEIP1559 = false,
  }) => throw UnimplementedError();

  @override
  Future<MsgSignature> signToSignature(
    Uint8List payload, {
    int? chainId,
    bool isEIP1559 = false,
  }) => throw UnimplementedError();
}

class _HangingWalletAccount extends AWalletAccount {
  _HangingWalletAccount()
    : super(
        0,
        EthPrivateKey.fromHex(
          'fb1ace12f9801e85f3db1b3935dd47d9f064f98152466f47c701b5e12680e612',
        ),
      );

  @override
  Future<String> signMessage(String message, {int addressIndex = 0}) {
    // Returns a future that never completes — caller's `.timeout(...)` must
    // surface a TimeoutException for the test to pass.
    return Completer<String>().future;
  }
}

class _RecordingAuthService implements DFXAuthService {
  _RecordingAuthService({this.throwOnEnsure = false});

  final bool throwOnEnsure;
  int ensureCalls = 0;

  @override
  Future<void> ensureSignatureFor(AWalletAccount account) async {
    ensureCalls++;
    if (throwOnEnsure) {
      throw StateError('simulated BitBox cancel');
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SignatureTestAuthService extends DFXAuthService {
  _SignatureTestAuthService(super.appStore, super.walletService, this._wallet, this._address);

  final AWalletAccount _wallet;
  final String _address;

  @override
  AWalletAccount get wallet => _wallet;

  @override
  String get walletAddress => _address;
}

class _MutableIdentityAuthService extends DFXAuthService {
  _MutableIdentityAuthService(
    super.appStore,
    super.walletService,
    this.currentAccount,
  );

  AWalletAccount currentAccount;

  @override
  AWalletAccount get wallet => currentAccount;

  @override
  String get walletAddress => currentAccount.primaryAddress.address.hexEip55;
}

// ---------------------------------------------------------------------------
// Helpers — authenticated request retry-on-401 surface.
// ---------------------------------------------------------------------------

class _MockApiConfig extends Mock implements ApiConfig {}

class _MockCacheRepository extends Mock implements CacheRepository {}

class _RetryTestAppStore extends AppStore {
  _RetryTestAppStore(this._client)
    : super(_MockApiConfig.new, SessionCache(_MockCacheRepository()));

  final http.Client _client;

  @override
  http.Client get httpClient => _client;
}

class _RetryTestAuthService extends DFXAuthService {
  _RetryTestAuthService(super.appStore, super.walletService);

  int authTokenCalls = 0;
  int refreshAuthTokenCalls = 0;

  @override
  AWalletAccount get wallet => throw UnimplementedError();

  @override
  String get walletAddress => throw UnimplementedError();

  @override
  Future<String?> getAuthToken() async {
    authTokenCalls++;
    return 'expired-token';
  }

  @override
  Future<String?> refreshAuthToken() async {
    refreshAuthTokenCalls++;
    return 'fresh-token';
  }
}

void main() {
  // -------------------------------------------------------------------------
  // getSignature / getAuthToken — signature cache + empty-sig guards.
  // -------------------------------------------------------------------------

  group('$DFXAuthService getSignature / getAuthToken', () {
    late AppStore appStore;
    late SessionCache sessionCache;
    late _StubWalletAccount walletAccount;

    const address = '0x1111111111111111111111111111111111111111';
    const validSig = '0xdeadbeef';

    late _MockWalletService walletService;

    setUp(() {
      appStore = _MockAppStore();
      sessionCache = _MockSessionCache();
      // The account must carry the same address the service reports — the
      // identity guard in _getSignatureFor compares the two since round 3.
      walletAccount = _StubWalletAccount(validSig, address: address);
      walletService = _MockWalletService();

      when(() => appStore.sessionCache).thenReturn(sessionCache);
      when(() => appStore.apiConfig).thenReturn(
        const ApiConfig(networkMode: NetworkMode.mainnet),
      );
      when(() => walletService.ensureCurrentWalletUnlocked()).thenAnswer((_) async {});
      when(() => walletService.lockCurrentWallet()).thenAnswer((_) async {});
      when(() => sessionCache.signature).thenReturn(null);
      when(() => sessionCache.signatureAddress).thenReturn(null);
      when(() => sessionCache.signedMessage).thenReturn(null);
      when(() => sessionCache.authToken).thenReturn(null);
      when(() => sessionCache.authTokenAddress).thenReturn(null);
      when(() => sessionCache.loadSignature()).thenAnswer((_) async {});
      when(() => sessionCache.saveSignature(any(), any(), any())).thenAnswer((_) async {});
    });

    _SignatureTestAuthService buildService() =>
        _SignatureTestAuthService(appStore, walletService, walletAccount, address);

    group('getSignature', () {
      test('returns the cached signature when address matches (no re-sign)', () async {
        when(() => sessionCache.signature).thenReturn(validSig);
        when(() => sessionCache.signatureAddress).thenReturn(address);
        when(() => sessionCache.signedMessage).thenReturn('msg');

        final result = await buildService().getSignature('msg');

        expect(result, validSig);
        expect(walletAccount.signCallCount, 0);
        verifyNever(() => sessionCache.saveSignature(any(), any(), any()));
      });

      test('signs and caches when no cached signature exists', () async {
        final result = await buildService().getSignature('msg');

        expect(result, validSig);
        expect(walletAccount.signCallCount, 1);
        verify(() => sessionCache.saveSignature(address, validSig, 'msg')).called(1);
      });

      test('signs again when the cached signature belongs to a different address', () async {
        when(() => sessionCache.signature).thenReturn(validSig);
        when(() => sessionCache.signatureAddress).thenReturn(
          '0x2222222222222222222222222222222222222222',
        );

        final result = await buildService().getSignature('msg');

        expect(result, validSig);
        expect(walletAccount.signCallCount, 1);
      });

      test('testnet legacy cache without the exact message scope re-signs', () async {
        when(() => appStore.apiConfig).thenReturn(
          const ApiConfig(networkMode: NetworkMode.testnet),
        );
        when(() => sessionCache.signature).thenReturn(validSig);
        when(() => sessionCache.signatureAddress).thenReturn(address);
        when(() => sessionCache.signedMessage).thenReturn(null);
        final service = buildService();
        final message = service.buildSignMessage(address);

        final result = await service.getSignature(message);

        expect(result, validSig);
        expect(walletAccount.signCallCount, 1);
        verify(() => sessionCache.saveSignature(address, validSig, message)).called(1);
      });

      test('testnet cache with a different scoped message re-signs', () async {
        when(() => appStore.apiConfig).thenReturn(
          const ApiConfig(networkMode: NetworkMode.testnet),
        );
        when(() => sessionCache.signature).thenReturn(validSig);
        when(() => sessionCache.signatureAddress).thenReturn(address);
        when(() => sessionCache.signedMessage).thenReturn('mainnet-message');
        final service = buildService();
        final message = service.buildSignMessage(address);

        await service.getSignature(message);

        expect(walletAccount.signCallCount, 1);
        verify(() => sessionCache.saveSignature(address, validSig, message)).called(1);
      });

      test(
        'identity change mid-unlock retries with a fresh snapshot and signs with the new account',
        () async {
          final accountA = _LockedSnapshotWalletAccount(
            address: '0x1111111111111111111111111111111111111111',
          );
          final accountB = _StubWalletAccount(
            '0xsignature-b',
            address: '0x2222222222222222222222222222222222222222',
          );
          late _MutableIdentityAuthService service;
          var unlockCalls = 0;
          when(() => walletService.ensureCurrentWalletUnlocked()).thenAnswer((_) async {
            unlockCalls++;
            if (unlockCalls == 1) service.currentAccount = accountB;
          });
          service = _MutableIdentityAuthService(
            appStore,
            walletService,
            accountA,
          );

          final signature = await service.getSignature('msg');

          expect(signature, '0xsignature-b');
          expect(accountB.signCallCount, 1);
          expect(unlockCalls, 2);
          verify(() => walletService.lockCurrentWallet()).called(2);
        },
      );

      test('permanent flapping identity fails loudly after three attempts', () async {
        final accountA = _StubWalletAccount(
          '0xsignature-a',
          address: '0x1111111111111111111111111111111111111111',
        );
        final accountB = _StubWalletAccount(
          '0xsignature-b',
          address: '0x2222222222222222222222222222222222222222',
        );
        late _MutableIdentityAuthService service;
        var unlockCalls = 0;
        when(() => walletService.ensureCurrentWalletUnlocked()).thenAnswer((_) async {
          unlockCalls++;
          service.currentAccount = identical(service.currentAccount, accountA)
              ? accountB
              : accountA;
        });
        service = _MutableIdentityAuthService(
          appStore,
          walletService,
          accountA,
        );

        await expectLater(
          service.getSignature('msg'),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'toString()',
              contains('wallet identity changed during authentication'),
            ),
          ),
        );

        expect(unlockCalls, 3);
        expect(accountA.signCallCount, 0);
        expect(accountB.signCallCount, 0);
        verify(() => walletService.lockCurrentWallet()).called(3);
      });

      for (final emptySignature in const ['', '0x']) {
        test(
          'throws SigningCancelledException when the wallet returns "$emptySignature"',
          () async {
            walletAccount = _StubWalletAccount(emptySignature, address: address);

            expect(
              () => buildService().getSignature('msg'),
              throwsA(isA<SigningCancelledException>()),
            );
          },
        );
      }
    });

    group('getAuthToken', () {
      test('returns the cached auth token without re-signing', () async {
        final walletAddress = walletAccount.primaryAddress.address.hexEip55;
        when(() => sessionCache.authToken).thenReturn('cached.jwt.token');
        when(() => sessionCache.authTokenAddress).thenReturn(walletAddress);

        final token = await _SignatureTestAuthService(
          appStore,
          walletService,
          walletAccount,
          walletAddress,
        ).getAuthToken();

        expect(token, 'cached.jwt.token');
        expect(walletAccount.signCallCount, 0);
      });
    });

    // TODO(#314 Phase 0): cover the 3 min `_signMessageTimeout` via the
    // `fake_async` package. Not yet a dev_dependency in this repo — adding it
    // would require a follow-up. Captured here as an explicit gap.
  });

  // -------------------------------------------------------------------------
  // authenticatedGet/Put/Post — one-time refresh-on-401 retry.
  // -------------------------------------------------------------------------

  group('$DFXAuthService authenticated requests', () {
    test('authenticatedGet retries once with a refreshed token on 401', () async {
      final seenAuthHeaders = <String?>[];
      final seenMethods = <String>[];
      final client = MockClient((request) async {
        seenAuthHeaders.add(request.headers['Authorization']);
        seenMethods.add(request.method);

        if (seenAuthHeaders.length == 1) {
          return http.Response('{"message":"Unauthorized"}', 401);
        }
        return http.Response('{"ok":true}', 200);
      });
      final service = _RetryTestAuthService(_RetryTestAppStore(client), _MockWalletService());

      final response = await service.authenticatedGet(
        Uri.parse('https://api.example.test/v1/resource'),
        headers: {'Accept': 'application/json'},
      );

      expect(response.statusCode, 200);
      expect(seenMethods, ['GET', 'GET']);
      expect(seenAuthHeaders, ['Bearer expired-token', 'Bearer fresh-token']);
      expect(service.authTokenCalls, 1);
      expect(service.refreshAuthTokenCalls, 1);
    });

    test(
      'authenticatedPost retries once with a refreshed token on 401 and resends the body',
      () async {
        final seenAuthHeaders = <String?>[];
        final seenBodies = <String>[];
        final client = MockClient((request) async {
          seenAuthHeaders.add(request.headers['Authorization']);
          seenBodies.add(request.body);

          if (seenAuthHeaders.length == 1) {
            return http.Response('{"message":"Unauthorized"}', 401);
          }
          return http.Response('{"ok":true}', 201);
        });
        final service = _RetryTestAuthService(_RetryTestAppStore(client), _MockWalletService());

        final response = await service.authenticatedPost(
          Uri.parse('https://api.example.test/v1/resource'),
          headers: {'Content-Type': 'application/json'},
          body: '{"value":1}',
        );

        expect(response.statusCode, 201);
        expect(seenAuthHeaders, ['Bearer expired-token', 'Bearer fresh-token']);
        // Same body resent on retry — no truncation, no double-encoding.
        expect(seenBodies, ['{"value":1}', '{"value":1}']);
        expect(service.refreshAuthTokenCalls, 1);
      },
    );

    test(
      'authenticatedPut retries once with a refreshed token on 401 and resends the body',
      () async {
        final seenAuthHeaders = <String?>[];
        final seenBodies = <String>[];
        final client = MockClient((request) async {
          seenAuthHeaders.add(request.headers['Authorization']);
          seenBodies.add(request.body);

          if (seenAuthHeaders.length == 1) {
            return http.Response('{"message":"Unauthorized"}', 401);
          }
          return http.Response('{"ok":true}', 200);
        });
        final service = _RetryTestAuthService(_RetryTestAppStore(client), _MockWalletService());

        final response = await service.authenticatedPut(
          Uri.parse('https://api.example.test/v1/resource'),
          headers: {'Content-Type': 'application/json'},
          body: '{"value":1}',
        );

        expect(response.statusCode, 200);
        expect(seenAuthHeaders, ['Bearer expired-token', 'Bearer fresh-token']);
        expect(seenBodies, ['{"value":1}', '{"value":1}']);
        expect(service.refreshAuthTokenCalls, 1);
      },
    );

    test('does not retry a third time when the refreshed token also yields 401', () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return http.Response('{"message":"Unauthorized"}', 401);
      });
      final service = _RetryTestAuthService(_RetryTestAppStore(client), _MockWalletService());

      final response = await service.authenticatedGet(
        Uri.parse('https://api.example.test/v1/resource'),
      );

      // Exactly two HTTP calls — initial + one retry — and the 401 is
      // surfaced to the caller.
      expect(calls, 2);
      expect(response.statusCode, 401);
      expect(service.refreshAuthTokenCalls, 1);
    });

    test('propagates exceptions thrown by refreshAuthToken without swallowing them', () async {
      final client = MockClient(
        (_) async => http.Response(
          '{"message":"Unauthorized"}',
          401,
        ),
      );
      final service = _ThrowingRefreshAuthService(_RetryTestAppStore(client), _MockWalletService());

      await expectLater(
        service.authenticatedGet(Uri.parse('https://api.example.test/v1/resource')),
        throwsA(isA<StateError>()),
      );
      expect(service.refreshAuthTokenCalls, 1);
    });

    test(
      'bearerTokenOverride uses the exact token and skips the 401-refresh path',
      () async {
        final seenAuthHeaders = <String?>[];
        var calls = 0;
        final client = MockClient((request) async {
          calls++;
          seenAuthHeaders.add(request.headers['Authorization']);
          return http.Response('{"message":"Unauthorized"}', 401);
        });
        final service = _RetryTestAuthService(_RetryTestAppStore(client), _MockWalletService());

        final response = await service.authenticatedGet(
          Uri.parse('https://api.example.test/v1/resource'),
          bearerTokenOverride: 'link-jwt-for-new-address',
        );

        expect(response.statusCode, 401);
        expect(calls, 1, reason: 'override must not retry on 401');
        expect(seenAuthHeaders, ['Bearer link-jwt-for-new-address']);
        expect(service.authTokenCalls, 0);
        expect(service.refreshAuthTokenCalls, 0);
      },
    );

    test(
      'authenticatedPost bearerTokenOverride lands in the Authorization header',
      () async {
        String? auth;
        final client = MockClient((request) async {
          auth = request.headers['Authorization'];
          return http.Response('{"ok":true}', 201);
        });
        final service = _RetryTestAuthService(_RetryTestAppStore(client), _MockWalletService());

        await service.authenticatedPost(
          Uri.parse('https://api.example.test/v1/resource'),
          headers: {'Content-Type': 'application/json'},
          body: '{"value":1}',
          bearerTokenOverride: 'override-post-token',
        );

        expect(auth, 'Bearer override-post-token');
        expect(service.authTokenCalls, 0);
        expect(service.refreshAuthTokenCalls, 0);
      },
    );

    test(
      'authenticatedPut bearerTokenOverride lands in the Authorization header',
      () async {
        String? auth;
        final client = MockClient((request) async {
          auth = request.headers['Authorization'];
          return http.Response('{"ok":true}', 200);
        });
        final service = _RetryTestAuthService(_RetryTestAppStore(client), _MockWalletService());

        await service.authenticatedPut(
          Uri.parse('https://api.example.test/v1/resource'),
          headers: {'Content-Type': 'application/json'},
          body: '{"value":1}',
          bearerTokenOverride: 'override-put-token',
        );

        expect(auth, 'Bearer override-put-token');
        expect(service.authTokenCalls, 0);
        expect(service.refreshAuthTokenCalls, 0);
      },
    );
  });

  // -------------------------------------------------------------------------
  // ensureSignatureFor — BitBox-pairing pre-warm path.
  // -------------------------------------------------------------------------

  group('$DFXAuthService ensureSignatureFor', () {
    late _MockAppStore appStore;
    late _MockSessionCache sessionCache;
    late _MockWalletService walletService;
    late _StubWalletAccount account;

    // EIP-55 requires either mixed-case checksum OR all lowercase / all
    // uppercase. We use all-lowercase here so the address can be fed into
    // `EthereumAddress.fromHex` without recomputing the case-map.
    const accountAddress = '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    final accountAddressEip55 = EthereumAddress.fromHex(accountAddress).hexEip55;
    const stubSignature = '0xfeedface';

    setUp(() {
      appStore = _MockAppStore();
      sessionCache = _MockSessionCache();
      walletService = _MockWalletService();
      account = _StubWalletAccount(stubSignature, address: accountAddress);

      when(() => appStore.sessionCache).thenReturn(sessionCache);
      when(() => appStore.httpClient).thenReturn(
        MockClient((_) async => http.Response('{"message":"unused"}', 200)),
      );
      when(() => sessionCache.loadSignature()).thenAnswer((_) async {});
      when(() => sessionCache.signature).thenReturn(null);
      when(() => sessionCache.signatureAddress).thenReturn(null);
      when(() => sessionCache.signedMessage).thenReturn(null);
      when(() => sessionCache.saveSignature(any(), any(), any())).thenAnswer((_) async {});
      when(() => walletService.ensureCurrentWalletUnlocked()).thenAnswer((_) async {});
      when(() => walletService.lockCurrentWallet()).thenAnswer((_) async {});
    });

    _SignatureTestAuthService buildService({String? walletAddressOverride}) {
      when(() => appStore.apiConfig).thenReturn(const ApiConfig(networkMode: NetworkMode.mainnet));
      return _SignatureTestAuthService(
        appStore,
        walletService,
        account,
        walletAddressOverride ?? accountAddress,
      );
    }

    test('short-circuits when the cache already holds the address signature', () async {
      when(() => sessionCache.signature).thenReturn(stubSignature);
      when(() => sessionCache.signatureAddress).thenReturn(accountAddressEip55);
      final service = buildService();
      when(() => sessionCache.signedMessage).thenReturn(
        service.buildSignMessage(accountAddressEip55),
      );

      await service.ensureSignatureFor(account);

      // No sign ceremony, no save — the cached entry already matches.
      expect(account.signCallCount, 0);
      verifyNever(() => sessionCache.saveSignature(any(), any(), any()));
    });

    test('builds the sign message locally, signs, and persists when the cache is cold', () async {
      var httpCalled = false;
      final client = MockClient((_) async {
        httpCalled = true;
        return http.Response('unexpected', 500);
      });
      when(() => appStore.httpClient).thenReturn(client);

      final service = buildService();
      await service.ensureSignatureFor(account);

      // No /v1/auth/signMessage round-trip — the message is derived locally
      // from the account address (EIP-55 checksummed), the BitBox-pairing
      // entry point.
      expect(httpCalled, isFalse);
      expect(account.signCallCount, 1);
      verify(
        () => sessionCache.saveSignature(
          accountAddressEip55,
          stubSignature,
          service.buildSignMessage(accountAddressEip55),
        ),
      ).called(1);
    });

    test('signs again when the cached entry belongs to a different address', () async {
      when(() => sessionCache.signature).thenReturn(stubSignature);
      when(() => sessionCache.signatureAddress).thenReturn(
        EthereumAddress.fromHex('0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb').hexEip55,
      );
      when(() => appStore.httpClient).thenReturn(
        MockClient(
          (_) async => http.Response(jsonEncode({'message': 'm'}), 200),
        ),
      );

      final service = buildService();
      await service.ensureSignatureFor(account);

      expect(account.signCallCount, 1);
      verify(
        () => sessionCache.saveSignature(
          accountAddressEip55,
          stubSignature,
          service.buildSignMessage(accountAddressEip55),
        ),
      ).called(1);
    });

    for (final empty in const ['', '0x']) {
      test('throws SigningCancelledException when the device returns "$empty"', () async {
        account = _StubWalletAccount(empty, address: accountAddress);
        when(() => appStore.httpClient).thenReturn(
          MockClient(
            (_) async => http.Response(jsonEncode({'message': 'm'}), 200),
          ),
        );

        expect(
          () => buildService().ensureSignatureFor(account),
          throwsA(isA<SigningCancelledException>()),
        );
      });
    }
  });

  // -------------------------------------------------------------------------
  // warmAuthSignature — never throws, swallows-to-log on failure.
  // -------------------------------------------------------------------------

  group('warmAuthSignature', () {
    test('delegates to ensureSignatureFor on the happy path', () async {
      final auth = _RecordingAuthService();
      final account = _StubWalletAccount(
        '0xfeedface',
        address: '0xcccccccccccccccccccccccccccccccccccccccc',
      );

      await warmAuthSignature(auth, account, loggerName: 'test');

      expect(auth.ensureCalls, 1);
    });

    test('swallows exceptions thrown by ensureSignatureFor', () async {
      final auth = _RecordingAuthService(throwOnEnsure: true);
      final account = _StubWalletAccount(
        '0xfeedface',
        address: '0xcccccccccccccccccccccccccccccccccccccccc',
      );

      // Crucially: no `throwsA`. The contract is "log + return", so the
      // onboarding flow can keep going even if the BitBox pre-warm pops
      // an unexpected confirmation on the next call.
      await warmAuthSignature(auth, account, loggerName: 'test');

      expect(auth.ensureCalls, 1);
    });
  });

  // -------------------------------------------------------------------------
  // getSignMessage / getAuthResponse / getAuthToken / refreshAuthToken /
  // invalidateAuthToken — the wire-shape on the `/v1/auth*` endpoints.
  // -------------------------------------------------------------------------

  group('$DFXAuthService auth wire surface', () {
    late _MockAppStore appStore;
    late SessionCache sessionCache;
    late _MockCacheRepository cacheRepo;
    late _MockWalletService walletService;
    late _StubWalletAccount account;

    // Digits-only fixture: EIP-55 checksumming leaves it unchanged, so the
    // raw constant stays equal to the account's hexEip55 the identity guard
    // in _getSignatureFor compares against.
    const walletAddress = '0x4444444444444444444444444444444444444444';
    const validSignature = '0xfeedface';

    setUp(() {
      appStore = _MockAppStore();
      cacheRepo = _MockCacheRepository();
      // The SessionCache writes the signature back to disk on every
      // saveSignature call — stub the repo so the helper future resolves.
      when(() => cacheRepo.read(any())).thenAnswer((_) async => null);
      when(() => cacheRepo.write(any(), any())).thenAnswer((_) async => 1);
      when(() => cacheRepo.delete(any())).thenAnswer((_) async {});
      sessionCache = SessionCache(cacheRepo);
      walletService = _MockWalletService();
      account = _StubWalletAccount(validSignature, address: walletAddress);

      when(() => appStore.sessionCache).thenReturn(sessionCache);
      when(() => appStore.apiConfig).thenReturn(const ApiConfig(networkMode: NetworkMode.mainnet));
      when(() => walletService.ensureCurrentWalletUnlocked()).thenAnswer((_) async {});
      when(() => walletService.lockCurrentWallet()).thenAnswer((_) async {});
    });

    _SignatureTestAuthService buildService(http.Client client) {
      when(() => appStore.httpClient).thenReturn(client);
      return _SignatureTestAuthService(appStore, walletService, account, walletAddress);
    }

    test('getSignMessage builds the deterministic message locally, no HTTP', () async {
      var httpCalled = false;
      final client = MockClient((_) async {
        httpCalled = true;
        return http.Response('unexpected', 500);
      });

      final message = buildService(client).getSignMessage();

      expect(
        message,
        'By_signing_this_message,_you_confirm_that_you_are_the_sole_owner_'
        'of_the_provided_Blockchain_address._Your_ID:_$walletAddress',
      );
      expect(httpCalled, isFalse, reason: 'no /v1/auth/signMessage round-trip');
    });

    test('buildSignMessage on mainnet keeps the historical PRD text byte-for-byte', () {
      final client = MockClient((_) async => http.Response('', 200));
      final message = buildService(client).buildSignMessage(walletAddress);

      expect(
        message,
        'By_signing_this_message,_you_confirm_that_you_are_the_sole_owner_'
        'of_the_provided_Blockchain_address._Your_ID:_$walletAddress',
      );
      expect(message.startsWith('[dev]_'), isFalse);
    });

    test('buildSignMessage on testnet prefixes the message with [dev]_', () {
      when(() => appStore.apiConfig).thenReturn(const ApiConfig(networkMode: NetworkMode.testnet));
      final client = MockClient((_) async => http.Response('', 200));
      final message = buildService(client).buildSignMessage(walletAddress);

      expect(
        message,
        '[dev]_By_signing_this_message,_you_confirm_that_you_are_the_sole_owner_'
        'of_the_provided_Blockchain_address._Your_ID:_$walletAddress',
      );
    });

    test(
      'getAuthResponse POSTs /v1/auth with wallet + address + signature, returns the parsed 201',
      () async {
        Map<String, dynamic>? sentBody;
        String? sentMethod;
        String? sentPath;
        Map<String, String>? sentHeaders;
        var seq = 0;
        final client = MockClient((request) async {
          seq++;
          sentMethod = request.method;
          sentPath = request.url.path;
          sentHeaders = request.headers;
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(jsonEncode({'accessToken': 'jwt-fresh'}), 201);
        });

        final body = await buildService(client).getAuthResponse();

        expect(body['accessToken'], 'jwt-fresh');
        expect(sentMethod, 'POST');
        expect(sentPath, '/v1/auth');
        expect(sentHeaders!['content-type'], contains('application/json'));
        expect(sentBody!['wallet'], 'RealUnit');
        expect(sentBody!['address'], walletAddress);
        expect(sentBody!['signature'], validSignature);
        // One HTTP call: auth only — the sign message is built locally.
        expect(seq, 1);
      },
    );

    test('getAuthResponse omits walletName when sendWalletName=false', () async {
      Map<String, dynamic>? sentBody;
      final client = MockClient((request) async {
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'accessToken': 'jwt'}), 201);
      });

      await buildService(client).getAuthResponse(false);

      expect(sentBody!.containsKey('wallet'), isFalse);
      expect(sentBody!['address'], walletAddress);
      expect(sentBody!['signature'], validSignature);
    });

    test('getAuthResponse surfaces the 403 message when present', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({'statusCode': 403, 'message': 'country-blocked'}),
          403,
        );
      });

      await expectLater(
        buildService(client).getAuthResponse(),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'toString()',
            contains('country-blocked'),
          ),
        ),
      );
    });

    test('getAuthResponse falls back to the canned 403 message when the body has none', () async {
      final client = MockClient((request) async {
        return http.Response(jsonEncode({'statusCode': 403}), 403);
      });

      await expectLater(
        buildService(client).getAuthResponse(),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'toString()',
            contains('Service unavailable in your country'),
          ),
        ),
      );
    });

    test('getAuthResponse throws on an arbitrary non-201/403 status', () async {
      final client = MockClient((request) async {
        return http.Response('upstream broken', 502);
      });

      expect(
        () => buildService(client).getAuthResponse(),
        throwsA(isA<Exception>()),
      );
    });

    test(
      'getAuthResponse retries with a fresh snapshot when identity changes mid-unlock',
      () async {
        final accountA = _LockedSnapshotWalletAccount(
          address: '0x1111111111111111111111111111111111111111',
        );
        final accountB = _StubWalletAccount(
          '0xsignature-b',
          address: '0x2222222222222222222222222222222222222222',
        );
        late _MutableIdentityAuthService service;
        var unlockCalls = 0;
        when(() => walletService.ensureCurrentWalletUnlocked()).thenAnswer((_) async {
          unlockCalls++;
          if (unlockCalls == 1) service.currentAccount = accountB;
        });
        Map<String, dynamic>? sentBody;
        final client = MockClient((request) async {
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(jsonEncode({'accessToken': 'jwt-b'}), 201);
        });
        when(() => appStore.httpClient).thenReturn(client);
        service = _MutableIdentityAuthService(
          appStore,
          walletService,
          accountA,
        );

        final response = await service.getAuthResponse();

        expect(response['accessToken'], 'jwt-b');
        expect(accountB.signCallCount, 1);
        expect(
          sentBody!['address'],
          accountB.primaryAddress.address.hexEip55,
        );
        expect(unlockCalls, 2);
        verify(() => walletService.lockCurrentWallet()).called(2);
      },
    );

    test(
      'getAuthToken hits the sign-then-auth round-trip on a cold cache and caches the token',
      () async {
        var authCalls = 0;
        final client = MockClient((request) async {
          authCalls++;
          return http.Response(jsonEncode({'accessToken': 'jwt-1'}), 201);
        });

        final service = buildService(client);

        final first = await service.getAuthToken();
        // Second call must short-circuit on the cached JWT — no extra POST.
        final second = await service.getAuthToken();

        expect(first, 'jwt-1');
        expect(second, 'jwt-1');
        expect(authCalls, 1);
        expect(sessionCache.authToken, 'jwt-1');
        expect(sessionCache.authTokenAddress, walletAddress);
      },
    );

    test('getAuthToken treats a token for another address as a cache miss', () async {
      sessionCache.setAuthToken(
        'jwt-for-old-wallet',
        '0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
      );
      var authCalls = 0;
      final client = MockClient((_) async {
        authCalls++;
        return http.Response(jsonEncode({'accessToken': 'jwt-for-current-wallet'}), 201);
      });

      final token = await buildService(client).getAuthToken();

      expect(token, 'jwt-for-current-wallet');
      expect(authCalls, 1);
      expect(sessionCache.authTokenAddress, walletAddress);
    });

    test(
      'wallet identity change during unlock retries with a fresh snapshot',
      () async {
        final accountA = _LockedSnapshotWalletAccount(
          address: '0x1111111111111111111111111111111111111111',
        );
        final accountB = _StubWalletAccount(
          '0xsignature-b',
          address: '0x2222222222222222222222222222222222222222',
        );
        late _MutableIdentityAuthService service;
        var unlockCalls = 0;
        when(() => walletService.ensureCurrentWalletUnlocked()).thenAnswer((_) async {
          unlockCalls++;
          if (unlockCalls == 1) service.currentAccount = accountB;
        });
        Map<String, dynamic>? sentBody;
        final client = MockClient((request) async {
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(jsonEncode({'accessToken': 'jwt-b'}), 201);
        });
        when(() => appStore.httpClient).thenReturn(client);
        service = _MutableIdentityAuthService(
          appStore,
          walletService,
          accountA,
        );

        final token = await service.getAuthToken();

        expect(token, 'jwt-b');
        expect(unlockCalls, 2);
        expect(accountB.signCallCount, 1);
        expect(
          sentBody!['address'],
          accountB.primaryAddress.address.hexEip55,
        );
        verify(() => walletService.lockCurrentWallet()).called(2);
      },
    );

    test(
      'identity change during every unlock fails loudly after three attempts',
      () async {
        final accountA = _StubWalletAccount(
          '0xsignature-a',
          address: '0x1111111111111111111111111111111111111111',
        );
        final accountB = _StubWalletAccount(
          '0xsignature-b',
          address: '0x2222222222222222222222222222222222222222',
        );
        late _MutableIdentityAuthService service;
        var unlockCalls = 0;
        when(() => walletService.ensureCurrentWalletUnlocked()).thenAnswer((_) async {
          unlockCalls++;
          service.currentAccount = identical(service.currentAccount, accountA)
              ? accountB
              : accountA;
        });
        var authCalls = 0;
        final client = MockClient((_) async {
          authCalls++;
          return http.Response(jsonEncode({'accessToken': 'unexpected'}), 201);
        });
        when(() => appStore.httpClient).thenReturn(client);
        service = _MutableIdentityAuthService(
          appStore,
          walletService,
          accountA,
        );

        await expectLater(
          service.getAuthToken(),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'toString()',
              contains('wallet identity changed during authentication'),
            ),
          ),
        );

        expect(unlockCalls, 3);
        expect(authCalls, 0);
        expect(accountA.signCallCount, 0);
        expect(accountB.signCallCount, 0);
        verify(() => walletService.lockCurrentWallet()).called(3);
      },
    );

    test('A-B-A changes never commit the B response under A', () async {
      final accountA = _StubWalletAccount(
        '0xsignature-a',
        address: '0x1111111111111111111111111111111111111111',
      );
      final accountB = _StubWalletAccount(
        '0xsignature-b',
        address: '0x2222222222222222222222222222222222222222',
      );
      final pendingResponses = List.generate(
        3,
        (_) => Completer<http.Response>(),
      );
      final requestArrivals = List.generate(3, (_) => Completer<void>());
      final sentBodies = <Map<String, dynamic>>[];
      var requestIndex = 0;
      final client = MockClient((request) {
        sentBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        final index = requestIndex++;
        requestArrivals[index].complete();
        return pendingResponses[index].future;
      });
      when(() => appStore.httpClient).thenReturn(client);
      final service = _MutableIdentityAuthService(
        appStore,
        walletService,
        accountA,
      );

      final tokenFuture = service.getAuthToken();
      await requestArrivals[0].future;
      expect(sentBodies.single['address'], service.walletAddress);

      service.currentAccount = accountB;
      pendingResponses[0].complete(
        http.Response(jsonEncode({'accessToken': 'jwt-a-old'}), 201),
      );
      await requestArrivals[1].future;
      expect(sentBodies, hasLength(2));
      expect(
        sentBodies[1]['address'],
        accountB.primaryAddress.address.hexEip55,
      );

      service.currentAccount = accountA;
      pendingResponses[1].complete(
        http.Response(jsonEncode({'accessToken': 'jwt-b'}), 201),
      );
      await requestArrivals[2].future;
      expect(sessionCache.authToken, isNull);
      expect(sentBodies, hasLength(3));
      expect(
        sentBodies[2]['address'],
        accountA.primaryAddress.address.hexEip55,
      );

      pendingResponses[2].complete(
        http.Response(jsonEncode({'accessToken': 'jwt-a-current'}), 201),
      );

      expect(await tokenFuture, 'jwt-a-current');
      expect(sessionCache.authToken, 'jwt-a-current');
      expect(
        sessionCache.authTokenAddress,
        accountA.primaryAddress.address.hexEip55,
      );
    });

    test('flapping identity fails loudly after three authentication attempts', () async {
      final accountA = _StubWalletAccount(
        '0xsignature-a',
        address: '0x1111111111111111111111111111111111111111',
      );
      final accountB = _StubWalletAccount(
        '0xsignature-b',
        address: '0x2222222222222222222222222222222222222222',
      );
      late _MutableIdentityAuthService service;
      var authCalls = 0;
      final client = MockClient((_) async {
        authCalls++;
        service.currentAccount = identical(service.currentAccount, accountA)
            ? accountB
            : accountA;
        return http.Response(jsonEncode({'accessToken': 'jwt-$authCalls'}), 201);
      });
      when(() => appStore.httpClient).thenReturn(client);
      service = _MutableIdentityAuthService(
        appStore,
        walletService,
        accountA,
      );

      await expectLater(
        service.getAuthToken(),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'toString()',
            contains('wallet identity changed during authentication'),
          ),
        ),
      );

      expect(authCalls, 3);
      expect(sessionCache.authToken, isNull);
    });

    test('invalidateAuthToken clears the cached JWT', () {
      sessionCache.setAuthToken('to-be-cleared', walletAddress);

      buildService(MockClient((_) async => http.Response('', 200))).invalidateAuthToken();

      expect(sessionCache.authToken, isNull);
      expect(sessionCache.authTokenAddress, isNull);
    });

    test('refreshAuthToken clears the cache and forces a fresh /v1/auth round-trip', () async {
      sessionCache.setAuthToken('stale-jwt', walletAddress);
      var authCalls = 0;
      final client = MockClient((request) async {
        authCalls++;
        return http.Response(jsonEncode({'accessToken': 'jwt-fresh'}), 201);
      });

      final service = buildService(client);
      final refreshed = await service.refreshAuthToken();

      expect(refreshed, 'jwt-fresh');
      // Cache was cleared → exactly one auth round-trip.
      expect(authCalls, 1);
      expect(sessionCache.authToken, 'jwt-fresh');
      expect(sessionCache.authTokenAddress, walletAddress);
    });
  });

  // -------------------------------------------------------------------------
  // Base-class getters — `wallet` and `walletAddress` delegate to the
  // currently-loaded account on `appStore.wallet`. The other groups override
  // them in test subclasses to stay focused on individual code paths; this
  // group pins the default behaviour.
  // -------------------------------------------------------------------------

  group('$DFXAuthService base getters', () {
    test('wallet returns appStore.wallet.currentAccount; walletAddress is its EIP-55 hex', () {
      final appStore = _MockAppStore();
      final mockWallet = _MockAWallet();
      final mockAccount = _MockAWalletAccount();
      final creds = _StubCredentials('0x9F5713DEacB8e9CAB6c2d3FaE1AFc2715F8D2D71');

      when(() => appStore.wallet).thenReturn(mockWallet);
      when(() => mockWallet.currentAccount).thenReturn(mockAccount);
      when(() => mockAccount.primaryAddress).thenReturn(creds);
      when(() => appStore.apiConfig).thenReturn(const ApiConfig(networkMode: NetworkMode.mainnet));
      when(() => appStore.sessionCache).thenReturn(SessionCache(_MockCacheRepository()));
      when(() => appStore.httpClient).thenReturn(
        MockClient((_) async => http.Response('', 200)),
      );

      final service = _BaseGetterAuthService(appStore, _MockWalletService());

      expect(identical(service.wallet, mockAccount), isTrue);
      // The address is checksummed via EIP-55 — matches the format other
      // endpoints (KYC, user-data) expect.
      expect(service.walletAddress, creds.address.hexEip55);
      // `host` proxies the apiConfig getter.
      expect(service.host, 'api.dfx.swiss');
    });
  });

  // -------------------------------------------------------------------------
  // authenticateLinkedAccount — link a NEW address under the current UserData
  // by POSTing /v1/auth with the CURRENT wallet's JWT as Authorization.
  // -------------------------------------------------------------------------

  group('$DFXAuthService authenticateLinkedAccount', () {
    late _MockAppStore appStore;
    late _MockSessionCache sessionCache;
    late _MockWalletService walletService;
    late _StubWalletAccount account;

    const accountAddress = '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    final accountAddressEip55 = EthereumAddress.fromHex(accountAddress).hexEip55;
    const stubSignature = '0xfeedface';
    const linkBearerToken = 'jwt-of-current-software-wallet';

    setUp(() {
      appStore = _MockAppStore();
      sessionCache = _MockSessionCache();
      walletService = _MockWalletService();
      account = _StubWalletAccount(stubSignature, address: accountAddress);

      when(() => appStore.sessionCache).thenReturn(sessionCache);
      when(() => appStore.apiConfig).thenReturn(const ApiConfig(networkMode: NetworkMode.mainnet));
      when(() => sessionCache.loadSignature()).thenAnswer((_) async {});
      when(() => sessionCache.signature).thenReturn(null);
      when(() => sessionCache.signatureAddress).thenReturn(null);
      when(() => sessionCache.signedMessage).thenReturn(null);
      when(() => sessionCache.saveSignature(any(), any(), any())).thenAnswer((_) async {});
      when(() => walletService.ensureCurrentWalletUnlocked()).thenAnswer((_) async {});
      when(() => walletService.lockCurrentWallet()).thenAnswer((_) async {});
    });

    _SignatureTestAuthService buildService(http.Client client) {
      when(() => appStore.httpClient).thenReturn(client);
      return _SignatureTestAuthService(
        appStore,
        walletService,
        account,
        accountAddressEip55,
      );
    }

    test(
      'cache-miss: signs, caches, POSTs /v1/auth with link Bearer + body, returns accessToken',
      () async {
        var saveCalls = 0;
        List<Object?>? savedArguments;
        when(
          () => sessionCache.saveSignature(any(), any(), any()),
        ).thenAnswer((invocation) async {
          saveCalls++;
          savedArguments = invocation.positionalArguments;
        });
        Map<String, dynamic>? sentBody;
        Map<String, String>? sentHeaders;
        String? sentMethod;
        String? sentPath;
        final client = MockClient((request) async {
          sentMethod = request.method;
          sentPath = request.url.path;
          sentHeaders = request.headers;
          sentBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(jsonEncode({'accessToken': 'jwt-for-new-address'}), 201);
        });

        final service = buildService(client);
        final token = await service.authenticateLinkedAccount(
          account,
          linkBearerToken,
        );

        expect(token, 'jwt-for-new-address');
        expect(sentMethod, 'POST');
        expect(sentPath, '/v1/auth');
        expect(sentHeaders!['authorization'], 'Bearer $linkBearerToken');
        expect(sentHeaders!['content-type'], contains('application/json'));
        expect(sentBody!['wallet'], 'RealUnit');
        expect(sentBody!['address'], accountAddressEip55);
        expect(sentBody!['signature'], stubSignature);
        expect(account.signCallCount, 1);
        expect(saveCalls, 1);
        expect(savedArguments, [
          accountAddressEip55,
          stubSignature,
          service.buildSignMessage(accountAddressEip55),
        ]);
        // Returned token must NOT be written to the session cache — the
        // caller owns the identity switch.
        verifyNever(() => sessionCache.setAuthToken(any(), any()));
      },
    );

    test('cache-hit: reuses the cached signature and does not re-sign', () async {
      when(() => sessionCache.signature).thenReturn(stubSignature);
      when(() => sessionCache.signatureAddress).thenReturn(accountAddressEip55);
      Map<String, dynamic>? sentBody;
      final client = MockClient((request) async {
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'accessToken': 'jwt-linked'}), 201);
      });

      final service = buildService(client);
      when(() => sessionCache.signedMessage).thenReturn(
        service.buildSignMessage(accountAddressEip55),
      );
      final token = await service.authenticateLinkedAccount(
        account,
        linkBearerToken,
      );

      expect(token, 'jwt-linked');
      expect(account.signCallCount, 0);
      expect(sentBody!['signature'], stubSignature);
      verifyNever(() => sessionCache.saveSignature(any(), any(), any()));
    });

    test('cache message mismatch re-signs before authenticating the linked account', () async {
      var saveCalls = 0;
      List<Object?>? savedArguments;
      when(
        () => sessionCache.saveSignature(any(), any(), any()),
      ).thenAnswer((invocation) async {
        saveCalls++;
        savedArguments = invocation.positionalArguments;
      });
      when(() => sessionCache.signature).thenReturn(stubSignature);
      when(() => sessionCache.signatureAddress).thenReturn(accountAddressEip55);
      when(() => sessionCache.signedMessage).thenReturn('wrong-environment-message');
      final client = MockClient(
        (_) async => http.Response(jsonEncode({'accessToken': 'jwt-linked'}), 201),
      );
      final service = buildService(client);

      await service.authenticateLinkedAccount(account, linkBearerToken);

      expect(account.signCallCount, 1);
      expect(saveCalls, 1);
      expect(savedArguments, [
        accountAddressEip55,
        stubSignature,
        service.buildSignMessage(accountAddressEip55),
      ]);
    });

    for (final empty in const ['', '0x']) {
      test(
        'throws SigningCancelledException when the device returns "$empty"',
        () async {
          account = _StubWalletAccount(empty, address: accountAddress);
          final client = MockClient((_) async => http.Response('should-not-be-called', 500));

          await expectLater(
            () => buildService(client).authenticateLinkedAccount(account, linkBearerToken),
            throwsA(isA<SigningCancelledException>()),
          );
        },
      );
    }

    test('throws AddressAlreadyLinkedException on 409', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({'statusCode': 409, 'message': 'Address already linked to another account'}),
          409,
        ),
      );

      await expectLater(
        () => buildService(client).authenticateLinkedAccount(account, linkBearerToken),
        throwsA(isA<AddressAlreadyLinkedException>()),
      );
    });

    test('throws a generic Exception on non-201/409 status (e.g. 500)', () async {
      final client = MockClient(
        (_) async => http.Response('upstream broken', 500),
      );

      await expectLater(
        () => buildService(client).authenticateLinkedAccount(account, linkBearerToken),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'toString()',
            contains('Failed to link address. Status: 500'),
          ),
        ),
      );
    });
  });

  // -------------------------------------------------------------------------
  // _signMessageTimeout — 3 min cap on the sign ceremony.
  //
  // Exercised via getSignature (cache-miss path). `fake_async` lets us assert
  // the bound without burning a wall-clock 3 min on every CI run.
  // -------------------------------------------------------------------------

  group('$DFXAuthService sign-message timeout', () {
    test('getSignature throws TimeoutException after the 3-minute cap', () {
      fakeAsync((async) {
        final appStore = _MockAppStore();
        final sessionCache = _MockSessionCache();
        final walletService = _MockWalletService();
        final account = _HangingWalletAccount();

        when(() => appStore.sessionCache).thenReturn(sessionCache);
        when(() => sessionCache.signature).thenReturn(null);
        when(() => sessionCache.signatureAddress).thenReturn(null);
        when(() => sessionCache.signedMessage).thenReturn(null);
        when(() => sessionCache.saveSignature(any(), any(), any())).thenAnswer((_) async {});
        when(() => walletService.ensureCurrentWalletUnlocked()).thenAnswer((_) async {});
        when(() => walletService.lockCurrentWallet()).thenAnswer((_) async {});

        // The service address must match the hanging account's real derived
        // address, otherwise the identity guard fires before the hang.
        final service = _SignatureTestAuthService(
          appStore,
          walletService,
          account,
          account.primaryAddress.address.hexEip55,
        );

        Object? caught;
        service.getSignature('msg').catchError((Object e) {
          caught = e;
          return '';
        });

        // Just under the cap: still pending.
        async.elapse(const Duration(minutes: 2, seconds: 59));
        expect(caught, isNull);

        // Crossing the cap surfaces a TimeoutException.
        async.elapse(const Duration(seconds: 2));
        expect(caught, isA<TimeoutException>());
        // ensureCurrentWalletUnlocked is called once; lockCurrentWallet runs
        // in the `finally` even when the sign hangs out.
        verify(() => walletService.lockCurrentWallet()).called(1);
      });
    });
  });
}

/// Concrete subclass that does NOT override `wallet` / `walletAddress` so we
/// can pin the base-class getter chain (`appStore.wallet.currentAccount` →
/// `.primaryAddress.address.hexEip55`).
class _BaseGetterAuthService extends DFXAuthService {
  _BaseGetterAuthService(super.appStore, super.walletService);
}

class _ThrowingRefreshAuthService extends DFXAuthService {
  _ThrowingRefreshAuthService(super.appStore, super.walletService);

  int refreshAuthTokenCalls = 0;

  @override
  AWalletAccount get wallet => throw UnimplementedError();

  @override
  String get walletAddress => throw UnimplementedError();

  @override
  Future<String?> getAuthToken() async => 'expired-token';

  @override
  Future<String?> refreshAuthToken() async {
    refreshAuthTokenCalls++;
    throw StateError('refresh boom');
  }
}
