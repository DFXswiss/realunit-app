import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/config/api_config.dart';
import 'package:realunit_wallet/packages/config/network_mode.dart';
import 'package:realunit_wallet/packages/repository/cache_repository.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_kyc_service.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/models/kyc/dto/kyc_financial_data_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/kyc/kyc_level.dart';
import 'package:realunit_wallet/packages/service/session_cache.dart';
import 'package:realunit_wallet/packages/service/wallet_service.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';
import 'package:realunit_wallet/packages/wallet/wallet_account.dart';
import 'package:realunit_wallet/styles/language.dart';
import 'package:web3dart/web3dart.dart';

class _MockAppStore extends Mock implements AppStore {}

class _MockCacheRepository extends Mock implements CacheRepository {}

class _MockWalletService extends Mock implements WalletService {}

class _StubCreds extends Fake implements CredentialsWithKnownAddress {
  @override
  EthereumAddress get address =>
      EthereumAddress.fromHex('0x0000000000000000000000000000000000000001');
}

class _StubWalletAccount extends AWalletAccount {
  _StubWalletAccount() : super(0, _StubCreds());
  @override
  Future<String> signMessage(String message, {int addressIndex = 0}) async => '0x';
}

class _StubWallet extends AWallet {
  _StubWallet() : super(1, 'Stub');
  @override
  WalletType get walletType => WalletType.software;
  @override
  AWalletAccount get primaryAccount => _StubWalletAccount();
  @override
  AWalletAccount get currentAccount => _StubWalletAccount();
}

const _userJson = {
  'mail': 'a@b.com',
  'kyc': {'hash': 'kyc-hash-123', 'level': 20, 'dataComplete': true},
};

const _emptySessionJson = {
  'kycLevel': 20,
  'kycSteps': <Map<String, dynamic>>[],
};

void main() {
  late _MockAppStore appStore;
  late _MockWalletService walletService;
  late SessionCache sessionCache;

  setUp(() {
    appStore = _MockAppStore();
    walletService = _MockWalletService();
    sessionCache = SessionCache(_MockCacheRepository());
    sessionCache.setAuthToken(
      'jwt-1',
      EthereumAddress.fromHex('0x0000000000000000000000000000000000000001').hexEip55,
    );
    when(() => appStore.sessionCache).thenReturn(sessionCache);
    when(() => appStore.apiConfig)
        .thenReturn(const ApiConfig(networkMode: NetworkMode.mainnet));
    when(() => appStore.wallet).thenReturn(_StubWallet());
    when(() => walletService.ensureCurrentWalletUnlocked()).thenAnswer((_) async {});
    when(() => walletService.lockCurrentWallet()).thenAnswer((_) async {});
  });

  DfxKycService build(http.Client client) {
    when(() => appStore.httpClient).thenReturn(client);
    return DfxKycService(appStore, walletService);
  }

  http.Response userResp() => http.Response(jsonEncode(_userJson), 200);

  group('$DfxKycService remaining methods', () {
    group('continueKyc', () {
      test('PUTs /v2/kyc with kyc-hash header and returns the parsed session', () async {
        Uri? uri;
        String? method;
        Map<String, String>? headers;
        final client = MockClient((request) async {
          if (request.url.path == '/v2/user') return userResp();
          uri = request.url;
          method = request.method;
          headers = request.headers;
          return http.Response(jsonEncode(_emptySessionJson), 200);
        });

        final session = await build(client).continueKyc();

        expect(method, 'PUT');
        expect(uri!.path, '/v2/kyc');
        expect(headers!['x-kyc-code'], 'kyc-hash-123');
        expect(session.kycLevel, KycLevel.level20);
      });

      test('throws ApiException on non-2xx', () async {
        final client = MockClient((request) async {
          if (request.url.path == '/v2/user') return userResp();
          return http.Response(jsonEncode({'statusCode': 500, 'message': 'x'}), 500);
        });

        expect(() => build(client).continueKyc(), throwsA(isA<ApiException>()));
      });
    });

    group('startStep', () {
      test('GETs /v2/kyc/<stepName.value> and returns the parsed session', () async {
        Uri? uri;
        String? method;
        final client = MockClient((request) async {
          if (request.url.path == '/v2/user') return userResp();
          uri = request.url;
          method = request.method;
          return http.Response(jsonEncode(_emptySessionJson), 200);
        });

        final session = await build(client).startStep(KycStepName.nameChange);

        expect(method, 'GET');
        // KycStepName.nameChange.value is the wire string for the path segment.
        expect(uri!.path, '/v2/kyc/${KycStepName.nameChange.value}');
        expect(session.kycLevel, KycLevel.level20);
      });

      test('throws ApiException on non-2xx', () async {
        final client = MockClient((request) async {
          if (request.url.path == '/v2/user') return userResp();
          return http.Response(jsonEncode({'statusCode': 403, 'message': 'no'}), 403);
        });

        expect(
          () => build(client).startStep(KycStepName.nameChange),
          throwsA(isA<ApiException>()),
        );
      });
    });

    group('setData', () {
      test('PUTs the given URL with body + kyc-hash header', () async {
        Uri? uri;
        Map<String, dynamic>? body;
        Map<String, String>? headers;
        final client = MockClient((request) async {
          if (request.url.path == '/v2/user') return userResp();
          uri = request.url;
          body = jsonDecode(request.body) as Map<String, dynamic>;
          headers = request.headers;
          return http.Response('{}', 201);
        });

        await build(client).setData(
          'https://kyc.example/session/abc',
          {'firstName': 'A', 'lastName': 'B'},
        );

        expect(uri!.toString(), 'https://kyc.example/session/abc');
        expect(body!['firstName'], 'A');
        expect(body!['lastName'], 'B');
        expect(headers!['x-kyc-code'], 'kyc-hash-123');
      });

      test('throws ApiException on non-2xx', () async {
        final client = MockClient((request) async {
          if (request.url.path == '/v2/user') return userResp();
          return http.Response(jsonEncode({'statusCode': 422, 'message': 'no'}), 422);
        });

        expect(
          () => build(client).setData('https://kyc.example/x', {'k': 'v'}),
          throwsA(isA<ApiException>()),
        );
      });
    });

    group('getFinancialData', () {
      test('GETs <url>?lang=<lang.code> and returns the parsed data', () async {
        Uri? uri;
        Map<String, String>? headers;
        final client = MockClient((request) async {
          if (request.url.path == '/v2/user') return userResp();
          uri = request.url;
          headers = request.headers;
          return http.Response(
            jsonEncode({
              'questions': <Map<String, dynamic>>[],
              'responses': <Map<String, dynamic>>[],
            }),
            200,
          );
        });

        final data = await build(client).getFinancialData(
          'https://kyc.example/financial/abc',
          language: Language.en,
        );

        expect(uri!.queryParameters['lang'], 'en');
        expect(headers!['x-kyc-code'], 'kyc-hash-123');
        expect(data.questions, isEmpty);
        expect(data.responses, isEmpty);
      });

      test('defaults language to DE', () async {
        Uri? uri;
        final client = MockClient((request) async {
          if (request.url.path == '/v2/user') return userResp();
          uri = request.url;
          return http.Response(
            jsonEncode({
              'questions': <Map<String, dynamic>>[],
              'responses': <Map<String, dynamic>>[],
            }),
            200,
          );
        });

        await build(client).getFinancialData('https://kyc.example/financial/abc');

        expect(uri!.queryParameters['lang'], 'de');
      });

      test('throws ApiException on non-2xx', () async {
        final client = MockClient((request) async {
          if (request.url.path == '/v2/user') return userResp();
          return http.Response(jsonEncode({'statusCode': 500, 'message': 'x'}), 500);
        });

        expect(
          () => build(client).getFinancialData('https://kyc.example/x'),
          throwsA(isA<ApiException>()),
        );
      });
    });

    group('setFinancialData', () {
      test('PUTs the given URL with {responses: [...]} body + kyc-hash header', () async {
        Map<String, dynamic>? body;
        Map<String, String>? headers;
        Uri? uri;
        final client = MockClient((request) async {
          if (request.url.path == '/v2/user') return userResp();
          uri = request.url;
          body = jsonDecode(request.body) as Map<String, dynamic>;
          headers = request.headers;
          return http.Response('{}', 201);
        });

        await build(client).setFinancialData(
          'https://kyc.example/financial/abc',
          const [
            KycFinancialResponse(key: 'q1', value: 'a1'),
            KycFinancialResponse(key: 'q2', value: 'a2'),
          ],
        );

        expect(uri!.toString(), 'https://kyc.example/financial/abc');
        expect(headers!['x-kyc-code'], 'kyc-hash-123');
        final responses = body!['responses'] as List<dynamic>;
        expect(responses, hasLength(2));
        expect(responses.first, {'key': 'q1', 'value': 'a1'});
      });

      test('throws ApiException on non-2xx', () async {
        final client = MockClient((request) async {
          if (request.url.path == '/v2/user') return userResp();
          return http.Response(jsonEncode({'statusCode': 422, 'message': 'no'}), 422);
        });

        expect(
          () => build(client).setFinancialData(
            'https://kyc.example/x',
            const [KycFinancialResponse(key: 'k', value: 'v')],
          ),
          throwsA(isA<ApiException>()),
        );
      });
    });
  });
}
