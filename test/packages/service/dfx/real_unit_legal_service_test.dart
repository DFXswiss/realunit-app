import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/config/api_config.dart';
import 'package:realunit_wallet/packages/config/network_mode.dart';
import 'package:realunit_wallet/packages/repository/cache_repository.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/models/legal/real_unit_legal_agreement.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_legal_service.dart';
import 'package:realunit_wallet/packages/service/session_cache.dart';
import 'package:realunit_wallet/packages/service/wallet_service.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';
import 'package:realunit_wallet/packages/wallet/wallet_account.dart';

class _MockAppStore extends Mock implements AppStore {}

class _MockWallet extends Mock implements AWallet {}

class _MockAccount extends Mock implements AWalletAccount {}

class _MockCacheRepository extends Mock implements CacheRepository {}

class _MockWalletService extends Mock implements WalletService {}

void main() {
  late _MockAppStore appStore;
  late _MockWallet wallet;
  late _MockAccount account;
  late _MockWalletService walletService;
  late SessionCache session;

  setUp(() {
    appStore = _MockAppStore();
    wallet = _MockWallet();
    account = _MockAccount();
    walletService = _MockWalletService();
    session = SessionCache(_MockCacheRepository());
    session.setAuthToken('jwt-1');

    when(() => appStore.apiConfig).thenReturn(const ApiConfig(networkMode: NetworkMode.mainnet));
    when(() => appStore.sessionCache).thenReturn(session);
    when(() => appStore.wallet).thenReturn(wallet);
    when(() => wallet.primaryAccount).thenReturn(account);
    when(() => walletService.ensureCurrentWalletUnlocked()).thenAnswer((_) async {});
    when(() => walletService.lockCurrentWallet()).thenAnswer((_) async {});
  });

  RealUnitLegalService build(http.Client client) {
    when(() => appStore.httpClient).thenReturn(client);
    return RealUnitLegalService(appStore, walletService);
  }

  // The per-service wiring (401-retry etc.) is covered in dfx_auth_service_test;
  // the "Bearer JWT" assertion below proves the call routes through the
  // authenticated client.
  group('$RealUnitLegalService.getLegalInfo', () {
    test('GETs /v1/realunit/legal with the Bearer JWT and parses the info', () async {
      String? path;
      String? method;
      String? auth;
      final client = MockClient((request) async {
        path = request.url.path;
        method = request.method;
        auth = request.headers['Authorization'];
        return http.Response(
          jsonEncode({
            'agreements': [
              {
                'agreement': 'DfxTermsAndConditions',
                'currentVersion': '20260712',
                'acceptedVersion': '20260712',
                'accepted': true,
              },
              {
                'agreement': 'ResidenceConfirmation',
                'currentVersion': '20260712',
                'acceptedVersion': null,
                'accepted': false,
              },
            ],
            'allAccepted': false,
          }),
          200,
        );
      });

      final info = await build(client).getLegalInfo();

      expect(method, 'GET');
      expect(path, '/v1/realunit/legal');
      expect(auth, 'Bearer jwt-1');
      expect(info.allAccepted, isFalse);
      expect(info.agreements, hasLength(2));
      // Only the not-yet-accepted agreement is outstanding.
      expect(info.outstandingAgreements, [RealUnitLegalAgreement.residenceConfirmation]);
    });

    test('throws ApiException on a non-200 response', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({'statusCode': 500, 'code': 'SERVER_ERROR', 'message': 'boom'}),
          500,
        ),
      );

      expect(() => build(client).getLegalInfo(), throwsA(isA<ApiException>()));
    });
  });

  group('$RealUnitLegalService.acceptLegal', () {
    test('PUTs /v1/realunit/legal with the agreement values and parses the info', () async {
      String? path;
      String? method;
      String? auth;
      Map<String, dynamic>? body;
      final client = MockClient((request) async {
        path = request.url.path;
        method = request.method;
        auth = request.headers['Authorization'];
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'agreements': <dynamic>[], 'allAccepted': true}),
          200,
        );
      });

      final info = await build(client).acceptLegal([
        RealUnitLegalAgreement.dfxTermsAndConditions,
        RealUnitLegalAgreement.residenceConfirmation,
      ]);

      expect(method, 'PUT');
      expect(path, '/v1/realunit/legal');
      expect(auth, 'Bearer jwt-1');
      // The PascalCase server values go on the wire, in order.
      expect(body!['agreements'], ['DfxTermsAndConditions', 'ResidenceConfirmation']);
      expect(info.allAccepted, isTrue);
    });

    test('accepts a 201 Created response as success', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({'agreements': <dynamic>[], 'allAccepted': true}),
          201,
        ),
      );

      final info = await build(client).acceptLegal([RealUnitLegalAgreement.dfxTermsAndConditions]);

      expect(info.allAccepted, isTrue);
    });

    test('throws ApiException on a non-2xx response', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({'statusCode': 400, 'code': 'BAD', 'message': 'nope'}),
          400,
        ),
      );

      expect(
        () => build(client).acceptLegal([RealUnitLegalAgreement.dfxTermsAndConditions]),
        throwsA(isA<ApiException>()),
      );
    });
  });
}
