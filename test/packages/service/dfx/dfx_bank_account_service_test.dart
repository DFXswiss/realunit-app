import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/config/api_config.dart';
import 'package:realunit_wallet/packages/config/network_mode.dart';
import 'package:realunit_wallet/packages/repository/cache_repository.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_bank_account_service.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/session_cache.dart';
import 'package:realunit_wallet/packages/service/wallet_service.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';

class _MockAppStore extends Mock implements AppStore {}

class _MockCacheRepository extends Mock implements CacheRepository {}

class _MockWalletService extends Mock implements WalletService {}

const _authMnemonic = 'test test test test test test test test test test test junk';

Map<String, dynamic> _bankAccount({
  int id = 1,
  String iban = 'CH5604835012345678009',
  String? label,
  bool isActive = true,
  bool isDefault = false,
}) => {
  'id': id,
  'iban': iban,
  'label': label,
  'active': isActive,
  'default': isDefault,
};

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
    // Pre-seed the JWT so `authenticatedGet/Put/Post` short-circuits the
    // `getAuthToken` refresh path (which would otherwise need a fully
    // stubbed wallet + signMessage endpoint).
    sessionCache.setAuthToken(
      'test-jwt',
      authWallet.currentAccount.primaryAddress.address.hexEip55,
    );
    when(() => appStore.sessionCache).thenReturn(sessionCache);
    when(() => appStore.apiConfig).thenReturn(const ApiConfig(networkMode: NetworkMode.mainnet));
    when(() => appStore.wallet).thenReturn(authWallet);
    when(() => walletService.ensureCurrentWalletUnlocked()).thenAnswer((_) async {});
    when(() => walletService.lockCurrentWallet()).thenAnswer((_) async {});
  });

  DfxBankAccountService build(http.Client client) {
    when(() => appStore.httpClient).thenReturn(client);
    return DfxBankAccountService(appStore, walletService);
  }

  group('$DfxBankAccountService', () {
    test('getBankAccounts GETs /v1/bankAccount with the JWT and maps the list', () async {
      sessionCache.setAuthToken(
        'jwt-1',
        authWallet.currentAccount.primaryAddress.address.hexEip55,
      );
      String? capturedAuth;
      String? capturedPath;
      String? capturedMethod;
      final client = MockClient((request) async {
        capturedAuth = request.headers['Authorization'];
        capturedPath = request.url.path;
        capturedMethod = request.method;
        return http.Response(
          jsonEncode([_bankAccount(id: 1), _bankAccount(id: 2, label: 'Main')]),
          200,
        );
      });

      final list = await build(client).getBankAccounts();

      expect(list, hasLength(2));
      expect(list[1].label, 'Main');
      expect(capturedMethod, 'GET');
      expect(capturedPath, '/v1/bankAccount');
      expect(capturedAuth, 'Bearer jwt-1');
    });

    test('getBankAccounts throws ApiException on non-2xx', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({'statusCode': 403, 'message': 'forbidden'}),
          403,
        ),
      );

      expect(
        () => build(client).getBankAccounts(),
        throwsA(isA<ApiException>()),
      );
    });

    test('createBankAccount POSTs the iban and optional label', () async {
      Map<String, dynamic>? body;
      String? method;
      final client = MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        method = request.method;
        return http.Response(jsonEncode(_bankAccount(id: 9, label: 'NewLabel')), 201);
      });

      final created = await build(client).createBankAccount('CH123', 'NewLabel');

      expect(created.id, 9);
      expect(created.label, 'NewLabel');
      expect(method, 'POST');
      expect(body!['iban'], 'CH123');
      expect(body!['label'], 'NewLabel');
    });

    test('createBankAccount omits the label key when null', () async {
      Map<String, dynamic>? body;
      final client = MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode(_bankAccount(id: 9)), 201);
      });

      await build(client).createBankAccount('CH123', null);

      expect(body!.containsKey('label'), isFalse);
      expect(body!['iban'], 'CH123');
    });

    test('createBankAccount throws ApiException on non-2xx', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({'statusCode': 422, 'message': 'invalid iban'}),
          422,
        ),
      );

      expect(
        () => build(client).createBankAccount('NOT_AN_IBAN', null),
        throwsA(isA<ApiException>()),
      );
    });

    test('updateBankAccount PUTs to /v1/bankAccount/{id} with only the provided fields', () async {
      Map<String, dynamic>? body;
      String? method;
      String? path;
      final client = MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        method = request.method;
        path = request.url.path;
        return http.Response(jsonEncode(_bankAccount(id: 7, label: 'X', isDefault: true)), 200);
      });

      final updated = await build(client).updateBankAccount(
        id: 7,
        label: 'X',
        isDefault: true,
      );

      expect(updated.id, 7);
      expect(updated.isDefault, isTrue);
      expect(method, 'PUT');
      expect(path, '/v1/bankAccount/7');
      expect(body!['label'], 'X');
      // `isDefault` becomes `default` in the wire payload.
      expect(body!['default'], isTrue);
      // No `active` field because the caller did not pass `isActive`.
      expect(body!.containsKey('active'), isFalse);
    });

    test('updateBankAccount propagates isActive as `active` on the wire', () async {
      // Coverage pin for the `if (isActive != null) 'active': isActive` branch
      // — none of the existing assertions pass `isActive`, so the wire-payload
      // key for de/re-activation would silently regress without this guard.
      Map<String, dynamic>? body;
      final client = MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode(_bankAccount(id: 5, isActive: false)), 200);
      });

      final updated = await build(client).updateBankAccount(id: 5, isActive: false);

      expect(updated.isActive, isFalse);
      expect(body!['active'], isFalse);
      // `default` and `label` must be omitted when the caller did not pass them.
      expect(body!.containsKey('default'), isFalse);
      expect(body!.containsKey('label'), isFalse);
    });

    test('updateBankAccount throws ApiException on non-2xx', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({'statusCode': 404, 'message': 'not found'}),
          404,
        ),
      );

      expect(
        () => build(client).updateBankAccount(id: 99, label: 'x'),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('malformed JSON responses', () {
    test('getBankAccounts with non-JSON 200 throws FormatException', () {
      final client = MockClient((_) async => http.Response('not json', 200));
      expect(
        () => build(client).getBankAccounts(),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
