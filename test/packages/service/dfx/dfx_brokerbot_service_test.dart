import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/config/api_config.dart';
import 'package:realunit_wallet/packages/config/network_mode.dart';
import 'package:realunit_wallet/packages/repository/cache_repository.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_brokerbot_service.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/session_cache.dart';
import 'package:realunit_wallet/packages/service/wallet_service.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';
import 'package:realunit_wallet/packages/wallet/wallet_account.dart';
import 'package:realunit_wallet/styles/currency.dart';
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

/// The address every cached auth token in this file is bound to — must match
/// [_StubCreds.address] so `getAuthToken`'s address check treats the token as
/// belonging to the current wallet.
final _stubAddress =
    EthereumAddress.fromHex('0x0000000000000000000000000000000000000001').hexEip55;

void main() {
  late _MockAppStore appStore;
  late _MockWalletService walletService;
  late SessionCache sessionCache;

  setUp(() {
    appStore = _MockAppStore();
    walletService = _MockWalletService();
    sessionCache = SessionCache(_MockCacheRepository());
    when(() => appStore.sessionCache).thenReturn(sessionCache);
    when(() => appStore.apiConfig).thenReturn(const ApiConfig(networkMode: NetworkMode.mainnet));
    when(() => appStore.wallet).thenReturn(_StubWallet());
    when(() => walletService.ensureCurrentWalletUnlocked()).thenAnswer((_) async {});
    when(() => walletService.lockCurrentWallet()).thenAnswer((_) async {});
  });

  DfxBrokerbotService build(http.Client client) {
    when(() => appStore.httpClient).thenReturn(client);
    return DfxBrokerbotService(appStore, walletService);
  }

  group('$DfxBrokerbotService', () {
    group('getBuyPrice', () {
      test('GETs /buyPrice with shares + currency and maps the response', () async {
        Uri? capturedUri;
        final client = MockClient((request) async {
          capturedUri = request.url;
          return http.Response(
            jsonEncode({'totalPrice': 100.5, 'pricePerShare': 10.05, 'availableShares': 50}),
            200,
          );
        });

        final price = await build(client).getBuyPrice('10', Currency.chf);

        expect(price.totalCost, 100.5);
        expect(price.pricePerShare, 10.05);
        expect(price.availableShares, 50);
        expect(capturedUri!.path, '/v1/realunit/brokerbot/buyPrice');
        expect(capturedUri!.queryParameters['shares'], '10');
        expect(capturedUri!.queryParameters['currency'], 'CHF');
      });

      test('throws for non-numeric shares input', () {
        final client = MockClient((_) async => http.Response('{}', 200));

        expect(
          () => build(client).getBuyPrice('abc', Currency.chf),
          throwsException,
        );
      });

      test('throws for zero / negative shares input', () {
        final client = MockClient((_) async => http.Response('{}', 200));

        expect(
          () => build(client).getBuyPrice('0', Currency.chf),
          throwsException,
        );
        expect(
          () => build(client).getBuyPrice('-3', Currency.chf),
          throwsException,
        );
      });

      test('throws when the server returns a non-200', () async {
        final client = MockClient((_) async => http.Response('boom', 500));

        expect(
          () => build(client).getBuyPrice('5', Currency.chf),
          throwsException,
        );
      });

      test('throws for Infinity input (UI prevents this via digitsOnly formatter)', () {
        expect(
          () => build(
            MockClient((_) async => http.Response('{}', 200)),
          ).getBuyPrice('Infinity', Currency.chf),
          throwsException,
        );
      });

      test('throws for NaN input (UI prevents this via digitsOnly formatter)', () {
        expect(
          () => build(
            MockClient((_) async => http.Response('{}', 200)),
          ).getBuyPrice('NaN', Currency.chf),
          throwsException,
        );
      });
    });

    group('getBuyShares', () {
      test('GETs /buyShares with amount + currency and maps the response', () async {
        Uri? uri;
        final client = MockClient((request) async {
          uri = request.url;
          return http.Response(
            jsonEncode({'shares': 7, 'pricePerShare': 12.5, 'availableShares': 100}),
            200,
          );
        });

        final shares = await build(client).getBuyShares('100.0', Currency.eur);

        expect(shares.shares, 7);
        expect(shares.pricePerShare, 12.5);
        expect(uri!.queryParameters['amount'], '100.0');
        expect(uri!.queryParameters['currency'], 'EUR');
      });

      test('normalises a comma decimal separator before parsing (300,75 → amount=300.75)', () async {
        // The fiat converter field allows a comma; without normalization
        // `double.tryParse("300,75")` is null and the converter fails silently.
        Uri? uri;
        final client = MockClient((request) async {
          uri = request.url;
          return http.Response(
            jsonEncode({'shares': 3, 'pricePerShare': 100.25, 'availableShares': 100}),
            200,
          );
        });

        final shares = await build(client).getBuyShares('300,75', Currency.chf);

        expect(shares.shares, 3);
        expect(uri!.queryParameters['amount'], '300.75');
      });

      test('throws for non-numeric / zero / negative amount input', () {
        final client = MockClient((_) async => http.Response('{}', 200));

        expect(() => build(client).getBuyShares('hi', Currency.chf), throwsException);
        expect(() => build(client).getBuyShares('0', Currency.chf), throwsException);
        expect(() => build(client).getBuyShares('-1.5', Currency.chf), throwsException);
      });

      test('throws when the server returns a non-200', () async {
        // Coverage pin for the `if (res.statusCode != 200) throw …` branch on
        // the unauthenticated /buyShares path. The other three brokerbot
        // endpoints already exercise their respective non-2xx paths.
        final client = MockClient((_) async => http.Response('boom', 503));

        expect(
          () => build(client).getBuyShares('100', Currency.chf),
          throwsException,
        );
      });
    });

    group('getSellPrice', () {
      test('GETs /sellPrice with the Bearer JWT', () async {
        sessionCache.setAuthToken('jwt-1', _stubAddress);
        String? auth;
        Uri? uri;
        final client = MockClient((request) async {
          auth = request.headers['Authorization'];
          uri = request.url;
          return http.Response(
            jsonEncode({
              'shares': 5,
              'pricePerShare': 9.0,
              'estimatedAmount': 45.0,
              'currency': 'CHF',
            }),
            200,
          );
        });

        final price = await build(client).getSellPrice('5', Currency.chf);

        expect(price.shares, 5);
        expect(price.estimatedAmount, 45.0);
        expect(auth, 'Bearer jwt-1');
        expect(uri!.path, '/v1/realunit/brokerbot/sellPrice');
      });

      test('throws ApiException with the JSON body on non-200', () async {
        sessionCache.setAuthToken('jwt-1', _stubAddress);
        final client = MockClient(
          (_) async => http.Response(
            jsonEncode({'statusCode': 422, 'message': 'no'}),
            422,
          ),
        );

        expect(
          () => build(client).getSellPrice('5', Currency.chf),
          throwsA(isA<ApiException>()),
        );
      });

      test('throws when shares input is invalid (before any HTTP call)', () async {
        var called = false;
        final client = MockClient((_) async {
          called = true;
          return http.Response('{}', 200);
        });

        expect(
          () => build(client).getSellPrice('bad', Currency.chf),
          throwsException,
        );
        await Future<void>.delayed(Duration.zero);
        expect(called, isFalse);
      });
    });

    group('getSellShares', () {
      test('GETs /sellShares with the Bearer JWT and maps the response', () async {
        sessionCache.setAuthToken('jwt-2', _stubAddress);
        final client = MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer jwt-2');
          return http.Response(
            jsonEncode({
              'targetAmount': 100.0,
              'shares': 11,
              'pricePerShare': 9.09,
              'currency': 'EUR',
            }),
            200,
          );
        });

        final shares = await build(client).getSellShares('100.0', Currency.eur);

        expect(shares.shares, 11);
        expect(shares.targetAmount, 100.0);
      });

      test('throws ApiException on non-200', () async {
        sessionCache.setAuthToken('jwt-2', _stubAddress);
        final client = MockClient(
          (_) async => http.Response(
            jsonEncode({'statusCode': 503, 'message': 'broker offline'}),
            503,
          ),
        );

        expect(
          () => build(client).getSellShares('100', Currency.eur),
          throwsA(isA<ApiException>()),
        );
      });

      test('normalises a comma decimal separator before parsing (300,75 → amount=300.75)', () async {
        sessionCache.setAuthToken('jwt-2', _stubAddress);
        Uri? uri;
        final client = MockClient((request) async {
          uri = request.url;
          return http.Response(
            jsonEncode({
              'targetAmount': 300.75,
              'shares': 3,
              'pricePerShare': 100.25,
              'currency': 'CHF',
            }),
            200,
          );
        });

        final shares = await build(client).getSellShares('300,75', Currency.chf);

        expect(shares.shares, 3);
        expect(uri!.queryParameters['amount'], '300.75');
      });

      test('throws when amount is invalid (before any HTTP call)', () async {
        var called = false;
        final client = MockClient((_) async {
          called = true;
          return http.Response('{}', 200);
        });

        expect(
          () => build(client).getSellShares('not-a-num', Currency.eur),
          throwsException,
        );
        await Future<void>.delayed(Duration.zero);
        expect(called, isFalse);
      });
    });
  });

  group('malformed JSON responses', () {
    late _MockAppStore appStore;
    late _MockWalletService walletService;
    late SessionCache sessionCache;

    setUp(() {
      appStore = _MockAppStore();
      walletService = _MockWalletService();
      sessionCache = SessionCache(_MockCacheRepository());
      when(() => appStore.sessionCache).thenReturn(sessionCache);
      when(() => appStore.apiConfig).thenReturn(const ApiConfig(networkMode: NetworkMode.mainnet));
      when(() => appStore.wallet).thenReturn(_StubWallet());
      when(() => walletService.ensureCurrentWalletUnlocked()).thenAnswer((_) async {});
      when(() => walletService.lockCurrentWallet()).thenAnswer((_) async {});
    });

    DfxBrokerbotService buildLocal(http.Client client) {
      when(() => appStore.httpClient).thenReturn(client);
      return DfxBrokerbotService(appStore, walletService);
    }

    test('getBuyPrice with non-JSON 200 throws FormatException', () {
      final client = MockClient((_) async => http.Response('not json', 200));
      expect(
        () => buildLocal(client).getBuyPrice('10', Currency.chf),
        throwsA(isA<FormatException>()),
      );
    });

    test('getSellPrice with non-JSON 200 throws FormatException', () {
      sessionCache.setAuthToken('jwt-test', _stubAddress);
      final client = MockClient((_) async => http.Response('not json', 200));
      expect(
        () => buildLocal(client).getSellPrice('10', Currency.chf),
        throwsA(isA<FormatException>()),
      );
    });

    test('getBuyShares with non-JSON 200 throws FormatException', () {
      final client = MockClient((_) async => http.Response('not json', 200));
      expect(
        () => buildLocal(client).getBuyShares('100', Currency.chf),
        throwsA(isA<FormatException>()),
      );
    });

    test('getSellShares with non-JSON 200 throws FormatException', () {
      sessionCache.setAuthToken('jwt-test', _stubAddress);
      final client = MockClient((_) async => http.Response('not json', 200));
      expect(
        () => buildLocal(client).getSellShares('100', Currency.chf),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
