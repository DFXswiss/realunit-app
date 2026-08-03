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
import 'package:realunit_wallet/packages/service/dfx/real_unit_pdf_service.dart';
import 'package:realunit_wallet/packages/service/session_cache.dart';
import 'package:realunit_wallet/packages/service/wallet_service.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';
import 'package:realunit_wallet/styles/currency.dart';
import 'package:realunit_wallet/styles/language.dart';

class _MockAppStore extends Mock implements AppStore {}

class _MockCacheRepository extends Mock implements CacheRepository {}

class _MockWalletService extends Mock implements WalletService {}

const _address = '0x000000000000000000000000000000000000beef';
const _authMnemonic = 'test test test test test test test test test test test junk';

void main() {
  late _MockAppStore appStore;
  late _MockWalletService walletService;
  late SessionCache sessionCache;
  late SoftwareWallet authWallet;

  setUp(() {
    appStore = _MockAppStore();
    walletService = _MockWalletService();
    sessionCache = SessionCache(_MockCacheRepository());
    authWallet = SoftwareWallet(1, 'Auth', _authMnemonic);
    when(() => appStore.sessionCache).thenReturn(sessionCache);
    when(() => appStore.apiConfig)
        .thenReturn(const ApiConfig(networkMode: NetworkMode.mainnet));
    when(() => appStore.wallet).thenReturn(authWallet);
    when(() => appStore.primaryAddress).thenReturn(_address);
    sessionCache.setAuthToken(
      'jwt-pdf',
      authWallet.currentAccount.primaryAddress.address.hexEip55,
    );
    when(() => walletService.ensureCurrentWalletUnlocked()).thenAnswer((_) async {});
    when(() => walletService.lockCurrentWallet()).thenAnswer((_) async {});
  });

  RealUnitPdfService build(http.Client client) {
    when(() => appStore.httpClient).thenReturn(client);
    return RealUnitPdfService(appStore, walletService);
  }

  group('$RealUnitPdfService', () {
    group('getBalanceReport', () {
      test('POSTs the BalancePdfDto payload and parses the pdfData response', () async {
        Map<String, dynamic>? body;
        String? auth;
        String? path;
        final client = MockClient((request) async {
          body = jsonDecode(request.body) as Map<String, dynamic>;
          auth = request.headers['Authorization'];
          path = request.url.path;
          return http.Response(jsonEncode({'pdfData': 'YmFsYW5jZQ=='}), 200);
        });

        final pdf = await build(client).getBalanceReport(
          date: DateTime.utc(2026, 5, 15, 23, 59, 59),
          currency: Currency.chf,
          language: Language.de,
        );

        expect(pdf.pdfData, 'YmFsYW5jZQ==');
        expect(path, '/v1/realunit/balance/pdf');
        expect(auth, 'Bearer jwt-pdf');
        expect(body!['address'], _address);
        expect(body!['currency'], 'CHF');
        // Language is uppercased on the wire.
        expect(body!['language'], 'DE');
      });

      test('accepts a 201 response in addition to 200', () async {
        final client = MockClient((_) async => http.Response(
              jsonEncode({'pdfData': 'AAAA'}),
              201,
            ));

        final pdf = await build(client).getBalanceReport(
          date: DateTime.utc(2026, 1, 1),
          currency: Currency.eur,
          language: Language.en,
        );

        expect(pdf.pdfData, 'AAAA');
      });

      test('throws ApiException on non-2xx', () async {
        final client = MockClient((_) async => http.Response(
              jsonEncode({'statusCode': 500, 'message': 'oops'}),
              500,
            ));

        expect(
          () => build(client).getBalanceReport(
            date: DateTime.utc(2026, 1, 1),
            currency: Currency.chf,
            language: Language.en,
          ),
          throwsA(isA<ApiException>()),
        );
      });
    });

    group('getTransactionsReceipt (multi)', () {
      test('POSTs the txHashes list + currency to the multi-receipt endpoint', () async {
        Map<String, dynamic>? body;
        String? path;
        final client = MockClient((request) async {
          body = jsonDecode(request.body) as Map<String, dynamic>;
          path = request.url.path;
          return http.Response(jsonEncode({'pdfData': 'MULTI'}), 200);
        });

        final pdf = await build(client).getTransactionsReceipt(
          ['0xa', '0xb', '0xc'],
          currency: Currency.eur,
          language: Language.de,
        );

        expect(pdf.pdfData, 'MULTI');
        expect(path, '/v1/realunit/transactions/receipt/multi');
        expect(body!['txHashes'], ['0xa', '0xb', '0xc']);
        expect(body!['currency'], 'EUR');
        // Language is uppercased on the wire.
        expect(body!['language'], 'DE');
      });

      test('defaults currency to CHF when not specified', () async {
        Map<String, dynamic>? body;
        final client = MockClient((request) async {
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(jsonEncode({'pdfData': 'X'}), 200);
        });

        await build(client).getTransactionsReceipt(['0x1'], language: Language.en);

        expect(body!['currency'], 'CHF');
      });

      test('throws ApiException on non-2xx', () async {
        final client = MockClient((_) async => http.Response(
              jsonEncode({'statusCode': 422, 'message': 'bad ids'}),
              422,
            ));

        expect(
          () => build(client).getTransactionsReceipt(['0x1'], language: Language.en),
          throwsA(isA<ApiException>()),
        );
      });
    });

    group('getTransactionReceipt (single)', () {
      test('POSTs the txHash + currency to the single-receipt endpoint', () async {
        Map<String, dynamic>? body;
        String? path;
        final client = MockClient((request) async {
          body = jsonDecode(request.body) as Map<String, dynamic>;
          path = request.url.path;
          return http.Response(jsonEncode({'pdfData': 'SINGLE'}), 200);
        });

        final pdf = await build(client).getTransactionReceipt(
          '0xabc',
          currency: Currency.eur,
          language: Language.de,
        );

        expect(pdf.pdfData, 'SINGLE');
        expect(path, '/v1/realunit/transactions/receipt/single');
        expect(body!['txHash'], '0xabc');
        expect(body!['currency'], 'EUR');
        // Language is uppercased on the wire.
        expect(body!['language'], 'DE');
      });

      test('defaults currency to CHF when not specified', () async {
        Map<String, dynamic>? body;
        final client = MockClient((request) async {
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(jsonEncode({'pdfData': 'X'}), 200);
        });

        await build(client).getTransactionReceipt('0xabc', language: Language.en);

        expect(body!['currency'], 'CHF');
      });

      test('throws ApiException on non-2xx', () async {
        final client = MockClient((_) async => http.Response(
              jsonEncode({'statusCode': 404, 'message': 'no tx'}),
              404,
            ));

        expect(
          () => build(client).getTransactionReceipt('0xmissing', language: Language.en),
          throwsA(isA<ApiException>()),
        );
      });
    });
  });

  group('malformed JSON responses', () {
    test('getBalanceReport with non-JSON 200 throws FormatException', () {
      final client = MockClient((_) async => http.Response('not json', 200));
      expect(
        () => build(client).getBalanceReport(
          date: DateTime(2025, 12, 31),
          currency: Currency.chf,
          language: Language.de,
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
