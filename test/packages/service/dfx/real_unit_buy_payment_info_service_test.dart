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
import 'package:realunit_wallet/packages/service/dfx/exceptions/payment/buy_exceptions.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_buy_payment_info_service.dart';
import 'package:realunit_wallet/packages/service/session_cache.dart';
import 'package:realunit_wallet/packages/service/wallet_service.dart';
import 'package:realunit_wallet/styles/currency.dart';

class MockApiConfig extends Mock implements ApiConfig {}

class MockCacheRepository extends Mock implements CacheRepository {}

class _MockWalletService extends Mock implements WalletService {}

class TestAppStore extends AppStore {
  final http.Client client;

  TestAppStore(this.client, ApiConfig Function() apiConfig)
    : super(apiConfig, SessionCache(MockCacheRepository()));

  @override
  http.Client get httpClient => client;
}

Map<String, dynamic> _buyPaymentInfoJson({
  int id = 42,
  bool isValid = true,
  String? error,
  String iban = 'CH9300762011623852957',
  String currency = 'CHF',
}) {
  return {
    'id': id,
    'routeId': 99,
    'timestamp': '2026-05-23T10:00:00Z',
    'iban': iban,
    'bic': 'POFICHBEXXX',
    'name': 'DFX AG',
    'street': 'Bahnhofstrasse',
    'number': '7',
    'zip': '6300',
    'city': 'Zug',
    'country': 'CH',
    'amount': 500.0,
    'currency': currency,
    'fees': {
      'rate': 0.01,
      'fixed': 0.5,
      'network': 0,
      'min': 1,
      'dfx': 0.25,
      'total': 1.76,
    },
    'minVolume': 100.0,
    'maxVolume': 100000.0,
    'minVolumeTarget': 100.0,
    'maxVolumeTarget': 100000.0,
    'exchangeRate': 1.1,
    'rate': 1.05,
    'priceSteps': <Map<String, dynamic>>[],
    'estimatedAmount': 480.0,
    'paymentRequest': 'bcr:?query',
    'remittanceInfo': 'REALU-$id',
    'isValid': isValid,
    if (error != null) 'error': error,
  };
}

void main() {
  late ApiConfig apiConfig;
  late _MockWalletService walletService;
  late RealUnitBuyPaymentInfoService service;

  setUp(() {
    apiConfig = MockApiConfig();
    walletService = _MockWalletService();
    when(() => apiConfig.apiHost).thenReturn('dev.api.dfx.swiss');
    when(() => apiConfig.networkMode).thenReturn(NetworkMode.testnet);
    when(() => walletService.ensureCurrentWalletUnlocked()).thenAnswer((_) async {});
    when(() => walletService.lockCurrentWallet()).thenAnswer((_) async {});
  });

  AppStore buildAppStore(Future<http.Response> Function(http.Request) handler) {
    final client = MockClient(handler);
    return TestAppStore(client, () => apiConfig)..sessionCache.setAuthToken('test-auth-token');
  }

  group('$RealUnitBuyPaymentInfoService', () {
    group('getPaymentInfo', () {
      test('PUTs /v1/realunit/buy with the buy DTO and maps the 200 response', () async {
        String? capturedMethod;
        String? capturedPath;
        Map<String, String>? capturedHeaders;
        Map<String, dynamic>? capturedBody;
        final appStore = buildAppStore((request) async {
          capturedMethod = request.method;
          capturedPath = request.url.path;
          capturedHeaders = request.headers;
          capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
          // EUR quote must return the EUR settlement IBAN + currency — not a CHF leftover.
          return http.Response(
            jsonEncode(
              _buyPaymentInfoJson(
                iban: 'CH9708307000560946317',
                currency: 'EUR',
              ),
            ),
            200,
          );
        });

        final service = RealUnitBuyPaymentInfoService(appStore, walletService);
        final info = await service.getPaymentInfo(500, currency: Currency.eur);

        expect(capturedMethod, 'PUT');
        expect(capturedPath, '/v1/realunit/buy');
        expect(capturedHeaders!['content-type'], contains('application/json'));
        expect(capturedHeaders!['Authorization'], 'Bearer test-auth-token');
        expect(capturedBody!['amount'], 500);
        expect(capturedBody!['currency'], 'EUR');

        // The service contracts the DTO down to a leaner BuyPaymentInfo —
        // pin the fields the UI / cubits actually consume so a wire-shape
        // drift breaks the test instead of leaking into the buy flow.
        expect(info.id, 42);
        expect(info.iban, 'CH9708307000560946317');
        expect(info.bic, 'POFICHBEXXX');
        expect(info.name, 'DFX AG');
        expect(info.street, 'Bahnhofstrasse');
        expect(info.number, '7');
        expect(info.zip, '6300');
        expect(info.city, 'Zug');
        expect(info.country, 'CH');
        expect(info.currency, Currency.eur);
        expect(info.paymentRequest, 'bcr:?query');
        expect(info.remittanceInfo, 'REALU-42');
        expect(info.isValid, isTrue);
        expect(info.minVolume, 100.0);
        expect(info.maxVolume, 100000.0);
        expect(info.error, isNull);
      });

      test('defaults the currency to CHF and maps the CHF settlement IBAN', () async {
        Map<String, dynamic>? capturedBody;
        final appStore = buildAppStore((request) async {
          capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode(
              _buyPaymentInfoJson(
                iban: 'CH2208307000560946309',
                currency: 'CHF',
              ),
            ),
            200,
          );
        });

        final service = RealUnitBuyPaymentInfoService(appStore, walletService);
        final info = await service.getPaymentInfo(1000);

        expect(capturedBody!['currency'], 'CHF');
        expect(info.iban, 'CH2208307000560946309');
        expect(info.currency, Currency.chf);
      });

      test('propagates the `error` + invalid flag from the API response', () async {
        final appStore = buildAppStore(
          (request) async => http.Response(
            jsonEncode(
              _buyPaymentInfoJson(
                isValid: false,
                error: 'AMOUNT_BELOW_MIN',
              ),
            ),
            200,
          ),
        );

        final service = RealUnitBuyPaymentInfoService(appStore, walletService);
        final info = await service.getPaymentInfo(1);

        expect(info.isValid, isFalse);
        expect(info.error, 'AMOUNT_BELOW_MIN');
      });

      test('throws ApiException with the upstream status on 403', () async {
        final appStore = buildAppStore(
          (_) async => http.Response(
            jsonEncode({'statusCode': 403, 'code': 'COUNTRY_NOT_ALLOWED', 'message': 'blocked'}),
            403,
          ),
        );

        final service = RealUnitBuyPaymentInfoService(appStore, walletService);

        await expectLater(
          service.getPaymentInfo(500),
          throwsA(
            isA<ApiException>()
                .having((e) => e.statusCode, 'statusCode', 403)
                .having((e) => e.code, 'code', 'COUNTRY_NOT_ALLOWED'),
          ),
        );
      });

      test('promotes the 403 to KycLevelRequiredException when code matches', () async {
        final appStore = buildAppStore(
          (_) async => http.Response(
            jsonEncode({
              'statusCode': 403,
              'code': 'KYC_LEVEL_REQUIRED',
              'message': 'KYC level 30 required',
              'requiredLevel': 30,
              'currentLevel': 0,
            }),
            403,
          ),
        );

        final service = RealUnitBuyPaymentInfoService(appStore, walletService);

        await expectLater(
          service.getPaymentInfo(500),
          throwsA(isA<KycLevelRequiredException>()),
        );
      });

      test('throws ApiException on a 500 / non-2xx path', () async {
        final appStore = buildAppStore(
          (_) async => http.Response(
            jsonEncode({'statusCode': 500, 'code': 'X', 'message': 'boom'}),
            500,
          ),
        );

        final service = RealUnitBuyPaymentInfoService(appStore, walletService);

        await expectLater(
          service.getPaymentInfo(500),
          throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'statusCode', 500),
          ),
        );
      });
    });

    group('confirmPayment', () {
      test('sends PUT request to correct endpoint', () async {
        String? capturedUrl;
        String? capturedMethod;
        Map<String, String>? capturedHeaders;
        final referenceText = 'REALU-123';

        final appStore = buildAppStore((request) async {
          capturedUrl = request.url.toString();
          capturedMethod = request.method;
          capturedHeaders = request.headers;
          return http.Response(
            '{"reference":"$referenceText","remittanceInfo":"$referenceText"}',
            200,
          );
        });

        final paymentInfoId = 123;

        service = RealUnitBuyPaymentInfoService(appStore, walletService);
        final result = await service.confirmPayment(paymentInfoId);

        expect(capturedMethod, equals('PUT'));
        expect(capturedUrl, contains(apiConfig.apiHost));
        expect(capturedUrl, contains('/v1/realunit/buy/$paymentInfoId/confirm'));
        expect(capturedHeaders?['Authorization'], equals('Bearer test-auth-token'));
        expect(result.reference, equals(referenceText));
        expect(result.remittanceInfo, equals(referenceText));
      });

      test('throws ApiException on non-200/201 status code', () async {
        final appStore = buildAppStore(
          (request) async => http.Response(
            '{"statusCode": 404, "message": "Not found"}',
            404,
          ),
        );

        final service = RealUnitBuyPaymentInfoService(appStore, walletService);

        expect(
          () => service.confirmPayment(999),
          throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404),
          ),
        );
      });

      test('throws ApiException with statusCode 503 on Aktionariat failure', () async {
        final appStore = buildAppStore(
          (request) async => http.Response(
            '{"statusCode": 503, "message": "Aktionariat API error: upstream"}',
            503,
          ),
        );

        final service = RealUnitBuyPaymentInfoService(appStore, walletService);

        expect(
          () => service.confirmPayment(999),
          throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'statusCode', 503),
          ),
        );
      });

      test('succeeds on 200 status code', () async {
        final referenceText = 'REALU-123';
        final appStore = buildAppStore(
          (request) async => http.Response(
            '{"reference":"$referenceText","remittanceInfo":"$referenceText","paymentRequest":"SPC-qr"}',
            200,
          ),
        );
        service = RealUnitBuyPaymentInfoService(appStore, walletService);

        final result = await service.confirmPayment(1);
        expect(result.reference, equals(referenceText));
        expect(result.remittanceInfo, equals(referenceText));
        expect(result.paymentRequest, equals('SPC-qr'));
      });

      test('backward compatible: a reference-only response (current API) maps '
          'to a DTO with null remittance info / QR', () async {
        final referenceText = 'REALU-123';
        final appStore = buildAppStore(
          (request) async => http.Response(
            '{"reference":"$referenceText"}',
            200,
          ),
        );
        service = RealUnitBuyPaymentInfoService(appStore, walletService);

        final result = await service.confirmPayment(1);
        expect(result.reference, equals(referenceText));
        expect(result.remittanceInfo, isNull);
        expect(result.paymentRequest, isNull);
      });

      test('succeeds on 201 status code', () async {
        final referenceText = 'REALU-123';
        final appStore = buildAppStore(
          (request) async => http.Response(
            '{"reference":"$referenceText","remittanceInfo":"$referenceText"}',
            201,
          ),
        );
        service = RealUnitBuyPaymentInfoService(appStore, walletService);

        final result = await service.confirmPayment(1);
        expect(result.reference, equals(referenceText));
        expect(result.remittanceInfo, equals(referenceText));
        expect(result.paymentRequest, isNull);
      });
    });

    group('malformed JSON responses', () {
      test('confirmPayment with non-JSON 200 throws FormatException', () async {
        final appStore = buildAppStore(
          (_) async => http.Response('not json', 200),
        );
        service = RealUnitBuyPaymentInfoService(appStore, walletService);

        expect(
          () => service.confirmPayment(1),
          throwsA(isA<FormatException>()),
        );
      });
    });
  });
}
