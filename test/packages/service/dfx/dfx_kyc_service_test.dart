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
import 'package:realunit_wallet/packages/service/dfx/models/kyc/dto/kyc_session_dto.dart';
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

class _StubWalletAccount extends AWalletAccount {
  _StubWalletAccount() : super(0, _StubCreds());
  @override
  Future<String> signMessage(String message, {int addressIndex = 0}) async => '0xstub-signature';
}

class _StubCreds extends Fake implements CredentialsWithKnownAddress {
  @override
  EthereumAddress get address =>
      EthereumAddress.fromHex('0x0000000000000000000000000000000000000001');
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
  'kyc': {
    'hash': 'kyc-hash-123',
    // Wire format is the numeric level (20 → KycLevel.level20).
    'level': 20,
    'dataComplete': true,
  },
};

const _kycLevelJson = {
  'kycLevel': 20,
  'processStatus': 'InProgress',
  'kycSteps': [
    {
      'name': 'ContactData',
      'type': 'Auto',
      'status': 'Completed',
      'sequenceNumber': 0,
      'isCurrent': false,
      'isRequired': true,
    },
  ],
};

const _kycSessionJson = {
  'kycLevel': 20,
  'processStatus': 'InProgress',
  'kycSteps': [
    {
      'name': 'PersonalData',
      'type': 'Auto',
      'status': 'InProgress',
      'sequenceNumber': 1,
      'isCurrent': true,
      'isRequired': true,
    },
  ],
  'currentStep': {
    'name': 'PersonalData',
    'type': 'Auto',
    'status': 'InProgress',
    'sequenceNumber': 1,
    'isCurrent': true,
    'session': {
      'url': 'https://example.com/kyc/session/abc',
      'type': 'Browser',
    },
  },
};

// Per the API's KycFinancialOutData contract: an array of questions and the
// already-submitted responses (`responses` is optional, defaults to []).
const _financialJson = {
  'questions': [
    {
      'key': 'income',
      'type': 'SingleChoice',
      'title': 'What is your income?',
      'description': null,
      'options': [
        {'key': 'low', 'text': '< 50k'},
        {'key': 'high', 'text': '> 50k'},
      ],
    },
  ],
  'responses': [
    {'key': 'income', 'value': 'high'},
  ],
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
    when(() => appStore.apiConfig).thenReturn(const ApiConfig(networkMode: NetworkMode.mainnet));
    when(() => appStore.wallet).thenReturn(_StubWallet());
    when(() => walletService.ensureCurrentWalletUnlocked()).thenAnswer((_) async {});
    when(() => walletService.lockCurrentWallet()).thenAnswer((_) async {});
  });

  DfxKycService build(http.Client client) {
    when(() => appStore.httpClient).thenReturn(client);
    return DfxKycService(appStore, walletService);
  }

  group('$DfxKycService', () {
    group('getUser', () {
      test('GETs /v2/user with the Bearer JWT and parses the response', () async {
        String? path;
        String? auth;
        final client = MockClient((request) async {
          path = request.url.path;
          auth = request.headers['Authorization'];
          return http.Response(jsonEncode(_userJson), 200);
        });

        final user = await build(client).getUser();

        expect(user.mail, 'a@b.com');
        expect(user.kyc.hash, 'kyc-hash-123');
        expect(path, '/v2/user');
        expect(auth, 'Bearer jwt-1');
      });

      test('accepts a 201 in addition to 200', () async {
        final client = MockClient(
          (_) async => http.Response(jsonEncode(_userJson), 201),
        );

        final user = await build(client).getUser();
        expect(user.mail, 'a@b.com');
      });

      test('throws ApiException on a non-2xx non-401 response', () async {
        final client = MockClient(
          (_) async => http.Response(
            jsonEncode({'statusCode': 500, 'message': 'oops'}),
            500,
          ),
        );

        expect(() => build(client).getUser(), throwsA(isA<ApiException>()));
      });
    });

    group('updateUser', () {
      test('PUTs /v2/user with the JSON body and Bearer JWT', () async {
        Map<String, dynamic>? body;
        String? method;
        final client = MockClient((request) async {
          body = jsonDecode(request.body) as Map<String, dynamic>;
          method = request.method;
          return http.Response('{}', 200);
        });

        await build(client).updateUser({'phone': '+41790000000'});

        expect(method, 'PUT');
        expect(body!['phone'], '+41790000000');
      });

      test('accepts a 201 response', () async {
        final client = MockClient((_) async => http.Response('{}', 201));

        await build(client).updateUser({'x': 'y'});
      });

      test('throws ApiException on non-2xx', () async {
        final client = MockClient(
          (_) async => http.Response(
            jsonEncode({'statusCode': 422, 'message': 'bad'}),
            422,
          ),
        );

        expect(
          () => build(client).updateUser({'phone': 'x'}),
          throwsA(isA<ApiException>()),
        );
      });
    });

    group('request2FaCode', () {
      test('POSTs /v2/kyc/2fa?level=Strict with kyc-hash header', () async {
        Uri? uri;
        Map<String, String>? headers;
        String? method;
        final client = MockClient((request) async {
          uri = request.url;
          headers = request.headers;
          method = request.method;
          if (request.url.path == '/v2/user') {
            return http.Response(jsonEncode(_userJson), 200);
          }
          return http.Response('{}', 201);
        });

        await build(client).request2FaCode();

        expect(method, 'POST');
        expect(uri!.path, '/v2/kyc/2fa');
        expect(uri!.queryParameters['level'], 'Strict');
        expect(headers!['x-kyc-code'], 'kyc-hash-123');
      });

      test('throws ApiException on non-2xx', () async {
        final client = MockClient((request) async {
          if (request.url.path == '/v2/user') {
            return http.Response(jsonEncode(_userJson), 200);
          }
          return http.Response(
            jsonEncode({'statusCode': 429, 'message': 'too many'}),
            429,
          );
        });

        expect(
          () => build(client).request2FaCode(),
          throwsA(isA<ApiException>()),
        );
      });
    });

    group('verify2FaCode', () {
      test('POSTs the token to /v2/kyc/2fa/verify with kyc-hash header', () async {
        Map<String, dynamic>? body;
        Uri? uri;
        Map<String, String>? headers;
        final client = MockClient((request) async {
          if (request.url.path == '/v2/user') {
            return http.Response(jsonEncode(_userJson), 200);
          }
          uri = request.url;
          headers = request.headers;
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{}', 201);
        });

        await build(client).verify2FaCode('123456');

        expect(uri!.path, '/v2/kyc/2fa/verify');
        expect(body!['token'], '123456');
        expect(headers!['x-kyc-code'], 'kyc-hash-123');
      });

      test('throws ApiException on non-2xx', () async {
        final client = MockClient((request) async {
          if (request.url.path == '/v2/user') {
            return http.Response(jsonEncode(_userJson), 200);
          }
          return http.Response(
            jsonEncode({'statusCode': 403, 'message': 'wrong code'}),
            403,
          );
        });

        expect(
          () => build(client).verify2FaCode('000000'),
          throwsA(isA<ApiException>()),
        );
      });
    });

    group('getKycStatus', () {
      test('first fetches /v2/user then GETs /v2/kyc with x-kyc-code header', () async {
        final paths = <String>[];
        String? kycCodeHeader;
        final client = MockClient((request) async {
          paths.add(request.url.path);
          if (request.url.path == '/v2/user') {
            return http.Response(jsonEncode(_userJson), 200);
          }
          kycCodeHeader = request.headers['x-kyc-code'];
          return http.Response(jsonEncode(_kycLevelJson), 200);
        });

        final dto = await build(client).getKycStatus();

        // Order matters: the kyc-code is on the User DTO, so the user fetch
        // must precede the kyc fetch.
        expect(paths, ['/v2/user', '/v2/kyc']);
        expect(kycCodeHeader, 'kyc-hash-123');
        expect(dto.kycLevel, KycLevel.level20);
        expect(dto.processStatus, KycProcessStatus.inProgress);
        expect(dto.kycSteps, hasLength(1));
      });

      test('accepts 201 (matches the service\'s 200/201 success contract)', () async {
        final client = MockClient((request) async {
          if (request.url.path == '/v2/user') {
            return http.Response(jsonEncode(_userJson), 200);
          }
          return http.Response(jsonEncode(_kycLevelJson), 201);
        });

        final dto = await build(client).getKycStatus();
        expect(dto.kycLevel, KycLevel.level20);
      });

      test('throws ApiException when /v2/kyc returns 5xx', () async {
        final client = MockClient((request) async {
          if (request.url.path == '/v2/user') {
            return http.Response(jsonEncode(_userJson), 200);
          }
          return http.Response(
            jsonEncode({'statusCode': 503, 'message': 'kyc service down'}),
            503,
          );
        });

        expect(
          () => build(client).getKycStatus(),
          throwsA(isA<ApiException>()),
        );
      });

      test('appends ?context= query param when context is provided', () async {
        Uri? capturedUri;
        final client = MockClient((request) async {
          if (request.url.path == '/v2/user') {
            return http.Response(jsonEncode(_userJson), 200);
          }
          capturedUri = request.url;
          return http.Response(jsonEncode(_kycLevelJson), 200);
        });

        await build(client).getKycStatus(context: 'RealunitBuy');

        expect(capturedUri!.path, '/v2/kyc');
        expect(capturedUri!.queryParameters['context'], 'RealunitBuy');
      });

      test('omits context query param when context is null', () async {
        Uri? capturedUri;
        final client = MockClient((request) async {
          if (request.url.path == '/v2/user') {
            return http.Response(jsonEncode(_userJson), 200);
          }
          capturedUri = request.url;
          return http.Response(jsonEncode(_kycLevelJson), 200);
        });

        await build(client).getKycStatus();

        expect(capturedUri!.path, '/v2/kyc');
        expect(capturedUri!.queryParameters, isNot(contains('context')));
      });

      // Failure on the user-fetch must short-circuit — the kyc-code is
      // unobtainable, so calling /v2/kyc would just produce another error.
      // Uses a 4xx that does NOT trigger the auth-service's 401 token refresh
      // path (which lives on DFXAuthService and would mask the user-fetch
      // failure by trying to obtain a fresh signature).
      test('propagates ApiException from /v2/user before calling /v2/kyc', () async {
        var sawKyc = false;
        final client = MockClient((request) async {
          if (request.url.path == '/v2/kyc') sawKyc = true;
          return http.Response(
            jsonEncode({'statusCode': 422, 'message': 'user fetch failed'}),
            422,
          );
        });

        await expectLater(
          () => build(client).getKycStatus(),
          throwsA(isA<ApiException>()),
        );
        // /v2/kyc must never be reached when the user fetch fails — otherwise
        // the second error would mask the first, and support sees the wrong
        // root cause in the bug report.
        expect(sawKyc, isFalse);
      });
    });

    group('continueKyc', () {
      test('PUTs /v2/kyc with x-kyc-code header and parses KycSessionDto', () async {
        String? method;
        String? path;
        String? kycCodeHeader;
        final client = MockClient((request) async {
          if (request.url.path == '/v2/user') {
            return http.Response(jsonEncode(_userJson), 200);
          }
          method = request.method;
          path = request.url.path;
          kycCodeHeader = request.headers['x-kyc-code'];
          return http.Response(jsonEncode(_kycSessionJson), 200);
        });

        final dto = await build(client).continueKyc();

        expect(method, 'PUT');
        expect(path, '/v2/kyc');
        expect(kycCodeHeader, 'kyc-hash-123');
        expect(dto.currentStep, isNotNull);
        expect(dto.currentStep!.session.url, 'https://example.com/kyc/session/abc');
        expect(dto.currentStep!.session.type, UrlType.browser);
      });

      test('appends ?context= query param when context is provided', () async {
        Uri? capturedUri;
        final client = MockClient((request) async {
          if (request.url.path == '/v2/user') {
            return http.Response(jsonEncode(_userJson), 200);
          }
          capturedUri = request.url;
          return http.Response(jsonEncode(_kycSessionJson), 200);
        });

        await build(client).continueKyc(context: 'RealunitSell');

        expect(capturedUri!.path, '/v2/kyc');
        expect(capturedUri!.queryParameters['context'], 'RealunitSell');
      });

      test('omits context query param when context is null', () async {
        Uri? capturedUri;
        final client = MockClient((request) async {
          if (request.url.path == '/v2/user') {
            return http.Response(jsonEncode(_userJson), 200);
          }
          capturedUri = request.url;
          return http.Response(jsonEncode(_kycSessionJson), 200);
        });

        await build(client).continueKyc();

        expect(capturedUri!.path, '/v2/kyc');
        expect(capturedUri!.queryParameters, isNot(contains('context')));
      });

      test('throws ApiException on a 409 conflict from /v2/kyc', () async {
        final client = MockClient((request) async {
          if (request.url.path == '/v2/user') {
            return http.Response(jsonEncode(_userJson), 200);
          }
          return http.Response(
            jsonEncode({'statusCode': 409, 'message': 'already in progress'}),
            409,
          );
        });

        expect(
          () => build(client).continueKyc(),
          throwsA(isA<ApiException>()),
        );
      });
    });

    group('startStep', () {
      test('GETs /v2/kyc/{stepName.value} with x-kyc-code header', () async {
        Uri? capturedUri;
        String? method;
        String? kycCodeHeader;
        final client = MockClient((request) async {
          if (request.url.path == '/v2/user') {
            return http.Response(jsonEncode(_userJson), 200);
          }
          capturedUri = request.url;
          method = request.method;
          kycCodeHeader = request.headers['x-kyc-code'];
          return http.Response(jsonEncode(_kycSessionJson), 200);
        });

        final dto = await build(client).startStep(KycStepName.personalData);

        expect(method, 'GET');
        // The wire spelling of KycStepName.personalData is "PersonalData" —
        // pin it so a future enum rename / kebab-case shift surfaces here.
        expect(capturedUri!.path, '/v2/kyc/PersonalData');
        expect(kycCodeHeader, 'kyc-hash-123');
        expect(dto.currentStep, isNotNull);
      });

      test('throws ApiException when the step is rejected by the backend', () async {
        final client = MockClient((request) async {
          if (request.url.path == '/v2/user') {
            return http.Response(jsonEncode(_userJson), 200);
          }
          return http.Response(
            jsonEncode({'statusCode': 400, 'message': 'step not available'}),
            400,
          );
        });

        expect(
          () => build(client).startStep(KycStepName.ident),
          throwsA(isA<ApiException>()),
        );
      });
    });

    group('setData', () {
      const sessionUrl = 'https://example.com/kyc/session/123';

      test('PUTs the given session URL with the request body + x-kyc-code header', () async {
        Uri? capturedUri;
        Map<String, dynamic>? capturedBody;
        Map<String, String>? capturedHeaders;
        String? method;
        final client = MockClient((request) async {
          if (request.url.path == '/v2/user') {
            return http.Response(jsonEncode(_userJson), 200);
          }
          capturedUri = request.url;
          capturedHeaders = request.headers;
          method = request.method;
          capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{}', 200);
        });

        await build(client).setData(sessionUrl, {'firstName': 'Alice'});

        expect(method, 'PUT');
        // The full session URL must be used as-is (not rewritten through
        // buildUri) — the backend hands the client an opaque URL that may
        // include a query token, host, etc.
        expect(capturedUri!.toString(), sessionUrl);
        expect(capturedBody!['firstName'], 'Alice');
        expect(capturedHeaders!['x-kyc-code'], 'kyc-hash-123');
      });

      test('accepts 201 in addition to 200', () async {
        final client = MockClient((request) async {
          if (request.url.path == '/v2/user') {
            return http.Response(jsonEncode(_userJson), 200);
          }
          return http.Response('{}', 201);
        });

        await build(client).setData(sessionUrl, {'x': 'y'});
      });

      test('throws ApiException when the session URL rejects the body', () async {
        final client = MockClient((request) async {
          if (request.url.path == '/v2/user') {
            return http.Response(jsonEncode(_userJson), 200);
          }
          return http.Response(
            jsonEncode({'statusCode': 422, 'message': 'invalid data'}),
            422,
          );
        });

        expect(
          () => build(client).setData(sessionUrl, {'bad': 'data'}),
          throwsA(isA<ApiException>()),
        );
      });
    });

    group('getFinancialData', () {
      const sessionUrl = 'https://example.com/kyc/financial';

      test('GETs the session URL with the chosen language and parses the questions', () async {
        Uri? capturedUri;
        Map<String, String>? capturedHeaders;
        String? method;
        final client = MockClient((request) async {
          if (request.url.path == '/v2/user') {
            return http.Response(jsonEncode(_userJson), 200);
          }
          capturedUri = request.url;
          capturedHeaders = request.headers;
          method = request.method;
          return http.Response(jsonEncode(_financialJson), 200);
        });

        final data = await build(client).getFinancialData(
          sessionUrl,
          language: Language.en,
        );

        expect(method, 'GET');
        // `?lang=en` is appended by the service — without that, the API
        // returns localized text in a default language the user didn't pick.
        expect(capturedUri!.queryParameters['lang'], 'en');
        expect(capturedHeaders!['x-kyc-code'], 'kyc-hash-123');
        expect(data.questions, hasLength(1));
        expect(data.questions.first.key, 'income');
        expect(data.responses, hasLength(1));
        expect(data.responses.first.value, 'high');
      });

      test('defaults to language=de when no language is provided', () async {
        Uri? capturedUri;
        final client = MockClient((request) async {
          if (request.url.path == '/v2/user') {
            return http.Response(jsonEncode(_userJson), 200);
          }
          capturedUri = request.url;
          return http.Response(jsonEncode(_financialJson), 200);
        });

        await build(client).getFinancialData(sessionUrl);

        // The DfxKycService signature defaults to Language.de — pin that
        // so a refactor doesn't silently swap to English (different KYC
        // texts shown than the rest of the app would suggest).
        expect(capturedUri!.queryParameters['lang'], 'de');
      });

      test('throws ApiException on non-2xx', () async {
        final client = MockClient((request) async {
          if (request.url.path == '/v2/user') {
            return http.Response(jsonEncode(_userJson), 200);
          }
          return http.Response(
            jsonEncode({'statusCode': 500, 'message': 'oops'}),
            500,
          );
        });

        expect(
          () => build(client).getFinancialData(sessionUrl),
          throwsA(isA<ApiException>()),
        );
      });
    });

    group('setFinancialData', () {
      const sessionUrl = 'https://example.com/kyc/financial';

      test('PUTs the responses serialized as {responses: [...]} payload', () async {
        Map<String, dynamic>? capturedBody;
        String? method;
        Uri? capturedUri;
        final client = MockClient((request) async {
          if (request.url.path == '/v2/user') {
            return http.Response(jsonEncode(_userJson), 200);
          }
          method = request.method;
          capturedUri = request.url;
          capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{}', 200);
        });

        await build(client).setFinancialData(sessionUrl, const [
          KycFinancialResponse(key: 'income', value: 'high'),
          KycFinancialResponse(key: 'occupation', value: 'engineer'),
        ]);

        expect(method, 'PUT');
        expect(capturedUri!.toString(), sessionUrl);
        // Wire shape: `{responses: [{key, value}, ...]}` — without the outer
        // `responses` key the backend rejects the payload with 400.
        final responses = capturedBody!['responses'] as List<dynamic>;
        expect(responses, hasLength(2));
        expect(responses.first, {'key': 'income', 'value': 'high'});
        expect(responses.last, {'key': 'occupation', 'value': 'engineer'});
      });

      test('accepts 201 in addition to 200', () async {
        final client = MockClient((request) async {
          if (request.url.path == '/v2/user') {
            return http.Response(jsonEncode(_userJson), 200);
          }
          return http.Response('{}', 201);
        });

        await build(client).setFinancialData(
          sessionUrl,
          const [KycFinancialResponse(key: 'income', value: 'high')],
        );
      });

      test('serializes an empty response list as {responses: []}', () async {
        Map<String, dynamic>? capturedBody;
        final client = MockClient((request) async {
          if (request.url.path == '/v2/user') {
            return http.Response(jsonEncode(_userJson), 200);
          }
          capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{}', 200);
        });

        await build(client).setFinancialData(sessionUrl, const []);

        // Empty list must still ship the `responses` key so the backend
        // sees a well-formed empty submission instead of a 400 on a
        // missing field.
        expect(capturedBody!['responses'], isEmpty);
      });

      test('throws ApiException on non-2xx', () async {
        final client = MockClient((request) async {
          if (request.url.path == '/v2/user') {
            return http.Response(jsonEncode(_userJson), 200);
          }
          return http.Response(
            jsonEncode({'statusCode': 422, 'message': 'invalid response'}),
            422,
          );
        });

        expect(
          () => build(client).setFinancialData(
            sessionUrl,
            const [KycFinancialResponse(key: 'income', value: 'high')],
          ),
          throwsA(isA<ApiException>()),
        );
      });
    });
  });

  group('malformed JSON responses', () {
    test('getUser with non-JSON 200 throws FormatException', () {
      final client = MockClient((_) async => http.Response('not json', 200));
      expect(
        () => build(client).getUser(),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
