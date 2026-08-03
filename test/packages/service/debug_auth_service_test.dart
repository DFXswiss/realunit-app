import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/config/api_config.dart';
import 'package:realunit_wallet/packages/config/network_mode.dart';
import 'package:realunit_wallet/packages/repository/cache_repository.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/debug_auth_service.dart';
import 'package:realunit_wallet/packages/service/session_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockAppStore extends Mock implements AppStore {}

class _MockCacheRepository extends Mock implements CacheRepository {}

void main() {
  // SharedPreferences needs the binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockAppStore appStore;
  late _MockCacheRepository cache;
  late SessionCache session;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    appStore = _MockAppStore();
    cache = _MockCacheRepository();
    session = SessionCache(cache);

    when(() => cache.write(any(), any())).thenAnswer((_) async => 0);

    when(() => appStore.apiConfig)
        .thenReturn(const ApiConfig(networkMode: NetworkMode.mainnet));
    when(() => appStore.sessionCache).thenReturn(session);
  });

  Future<DebugAuthService> build(http.Client client) async {
    when(() => appStore.httpClient).thenReturn(client);
    final prefs = await SharedPreferences.getInstance();
    return DebugAuthService(appStore, prefs);
  }

  group('savedAddress / savedSignature', () {
    test('return null when SharedPreferences is empty', () async {
      final svc = await build(MockClient((_) async => http.Response('{}', 200)));

      expect(svc.savedAddress, isNull);
      expect(svc.savedSignature, isNull);
    });

    test('return the stored values when present', () async {
      SharedPreferences.setMockInitialValues({
        'debugAuthAddress': '0xabc',
        'debugAuthSignature': '0xsig',
      });
      final svc = await build(MockClient((_) async => http.Response('{}', 200)));

      expect(svc.savedAddress, '0xabc');
      expect(svc.savedSignature, '0xsig');
    });
  });

  group('fetchSignMessage', () {
    test(
      'GETs /v1/auth/signMessage?address=... and returns the message',
      () async {
        Uri? sentUri;
        final client = MockClient((request) async {
          sentUri = request.url;
          return http.Response(jsonEncode({'message': 'Sign me: nonce-42'}), 200);
        });

        final message = await (await build(client))
            .fetchSignMessage('0xWallet');

        expect(sentUri!.path, '/v1/auth/signMessage');
        expect(sentUri!.queryParameters['address'], '0xWallet');
        expect(message, 'Sign me: nonce-42');
      },
    );

    test('non-200 → throws Exception with the status code', () async {
      final client = MockClient((_) async => http.Response('{}', 404));

      expect(
        () async => (await build(client)).fetchSignMessage('0x'),
        throwsA(
          predicate((e) => e.toString().contains('404')),
        ),
      );
    });
  });

  group('authenticate', () {
    test('on 201: stores accessToken in sessionCache + persists creds in prefs',
        () async {
      Uri? sentUri;
      Map<String, dynamic>? body;
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/signMessage')) {
          return http.Response(jsonEncode({'message': 'Sign me exactly'}), 200);
        }
        sentUri = request.url;
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'accessToken': 'jwt-OK'}),
          201,
        );
      });

      // Pass a lowercase address — the service checksums it before stashing
      // the signature in the session cache.
      const addressLower = '0x9f5713deacb8e9cab6c2d3fae1afc2715f8d2d71';
      const checksum = '0x9F5713DEacB8e9CAB6c2d3FaE1AFc2715F8D2D71';
      const signature = '0xdeadbeef';
      const signMessage = 'Sign me exactly';

      final svc = await build(client);
      await svc.fetchSignMessage(addressLower);
      await svc.authenticate(addressLower, signature);

      expect(sentUri!.path, '/v1/auth');
      expect(body!['wallet'], 'RealUnit');
      expect(body!['address'], addressLower);
      expect(body!['signature'], signature);

      // Auth token lands in the session cache.
      expect(session.authToken, 'jwt-OK');
      expect(session.authTokenAddress, checksum);
      // Signature lands under the EIP-55 checksum address.
      expect(session.signatureAddress, checksum);
      expect(session.signedMessage, signMessage);
      // The raw address + signature persist to SharedPreferences.
      expect(svc.savedAddress, addressLower);
      expect(svc.savedSignature, signature);
    });

    test('non-201 → throws Exception with the status code', () async {
      final client = MockClient(
        (request) async => request.url.path.endsWith('/signMessage')
            ? http.Response(jsonEncode({'message': 'Sign me'}), 200)
            : http.Response('boom', 500),
      );
      final service = await build(client);
      await service.fetchSignMessage('0xabc');

      expect(
        () async => service.authenticate('0xabc', '0xsig'),
        throwsA(
          predicate((e) => e.toString().contains('500')),
        ),
      );
    });

    test('requires a sign message fetched for the same address', () async {
      final service = await build(MockClient((_) async => http.Response('{}', 500)));

      await expectLater(
        service.authenticate('0xabc', '0xsig'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
