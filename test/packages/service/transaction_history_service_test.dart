import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/config/api_config.dart';
import 'package:realunit_wallet/packages/config/network_mode.dart';
import 'package:realunit_wallet/packages/repository/cache_repository.dart';
import 'package:realunit_wallet/packages/repository/transaction_repository.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/session_cache.dart';
import 'package:realunit_wallet/packages/service/transaction_history_service.dart';
import 'package:realunit_wallet/packages/service/wallet_service.dart';

class _MockAppStore extends Mock implements AppStore {}

class _MockCacheRepository extends Mock implements CacheRepository {}

class _MockTransactionRepository extends Mock implements TransactionRepository {}

class _MockWalletService extends Mock implements WalletService {}

const _wallet = '0x000000000000000000000000000000000000beef';
const _other = '0x0000000000000000000000000000000000001234';

Map<String, dynamic> _txJson({
  int id = 1,
  String state = 'Processing',
  String? source = _wallet,
  String? target,
}) => {
  'id': id,
  'type': 'Buy',
  'state': state,
  'rate': 1.0,
  'inputAmount': 100.0,
  'inputAsset': 'CHF',
  'inputTxId': null,
  'outputAmount': 1.0,
  'outputAsset': 'REALU',
  'outputTxId': null,
  'sourceAccount': source,
  'targetAccount': target,
};

void main() {
  late _MockAppStore appStore;
  late _MockWalletService walletService;
  late SessionCache sessionCache;
  late _MockTransactionRepository txRepo;

  setUp(() {
    appStore = _MockAppStore();
    walletService = _MockWalletService();
    sessionCache = SessionCache(_MockCacheRepository());
    txRepo = _MockTransactionRepository();
    when(() => appStore.sessionCache).thenReturn(sessionCache);
    when(() => appStore.apiConfig).thenReturn(const ApiConfig(networkMode: NetworkMode.mainnet));
    when(() => appStore.primaryAddress).thenReturn(_wallet);
    when(() => walletService.ensureCurrentWalletUnlocked()).thenAnswer((_) async {});
    when(() => walletService.lockCurrentWallet()).thenAnswer((_) async {});
  });

  TransactionHistoryService build(http.Client client) {
    when(() => appStore.httpClient).thenReturn(client);
    return TransactionHistoryService(appStore, walletService, txRepo);
  }

  group('$TransactionHistoryService', () {
    group('fetchPendingTransactions', () {
      // The pre-migration "no auth token -> silent empty list" branch is
      // gone: the request now routes through `authenticatedGet`, which
      // triggers the sign + token-exchange bootstrap on a missing token and
      // refreshes on 401. The 401-retry plumbing is exercised exhaustively
      // in `dfx_auth_service_test.dart`.

      test('GETs /v1/transaction/detail with the Bearer JWT', () async {
        sessionCache.setAuthToken('jwt-1');
        String? auth;
        String? path;
        final client = MockClient((request) async {
          auth = request.headers['Authorization'];
          path = request.url.path;
          return http.Response(jsonEncode([_txJson()]), 200);
        });

        await build(client).fetchPendingTransactions();

        expect(auth, 'Bearer jwt-1');
        expect(path, '/v1/transaction/detail');
      });

      test('returns [] on non-200 (does not throw)', () async {
        sessionCache.setAuthToken('jwt-1');
        final client = MockClient((_) async => http.Response('boom', 500));

        final list = await build(client).fetchPendingTransactions();

        expect(list, isEmpty);
      });

      test('filters out completed transactions (isPending=false)', () async {
        sessionCache.setAuthToken('jwt-1');
        final client = MockClient(
          (_) async => http.Response(
            jsonEncode([
              _txJson(id: 1, state: 'Processing'),
              _txJson(id: 2, state: 'Completed'),
              _txJson(id: 3, state: 'Failed'),
              _txJson(id: 4, state: 'Returned'),
              _txJson(id: 5, state: 'CheckPending'),
            ]),
            200,
          ),
        );

        final list = await build(client).fetchPendingTransactions();

        expect(list.map((t) => t.id), [1, 5]);
      });

      test('filters out transactions that do not belong to the current wallet', () async {
        sessionCache.setAuthToken('jwt-1');
        final client = MockClient(
          (_) async => http.Response(
            jsonEncode([
              _txJson(id: 1, source: _wallet),
              _txJson(id: 2, source: _other, target: _other),
              _txJson(id: 3, source: null, target: _wallet),
            ]),
            200,
          ),
        );

        final list = await build(client).fetchPendingTransactions();

        // 1 (source = wallet) and 3 (target = wallet) belong, 2 doesn't.
        expect(list.map((t) => t.id), [1, 3]);
      });

      test('wallet match is case-insensitive', () async {
        sessionCache.setAuthToken('jwt-1');
        when(() => appStore.primaryAddress).thenReturn(_wallet.toUpperCase());
        final client = MockClient(
          (_) async => http.Response(
            jsonEncode([_txJson(id: 1, source: _wallet)]),
            200,
          ),
        );

        final list = await build(client).fetchPendingTransactions();

        expect(list, hasLength(1));
      });
    });
  });

  // The two String extensions live in the same file as the service and are
  // used by tx-detail UI to render addresses + shortened txids. Without the
  // pins below they remain dead-code from coverage's point of view, even
  // though screens depend on them.
  group('ToEpiAddress', () {
    test('asHexEip55 round-trips through EthereumAddress.fromHex', () {
      // Lowercase hex in → EIP-55 mixed-case out. EthereumAddress.fromHex
      // would throw on an invalid 40-hex address, so the round-trip also
      // documents that the extension is a thin alias, not a parser.
      const lower = '0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed';
      expect(lower.asHexEip55, '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed');
    });

    test('asShortTxId trims long txids to 0xHEAD…TAIL', () {
      const txid = '0x1234567890abcdefdeadbeefcafef00d1234567890abcdefdeadbeefcafef00d';
      // Production format keeps the first 10 chars (0x + 8 hex) and the
      // last 10 chars; the rest collapses to "..." for compactness.
      expect(txid.asShortTxId, '0x12345678...efcafef00d');
      expect(txid.asShortTxId.contains('...'), isTrue);
      expect(txid.asShortTxId.length, 23); // 10 + 3 + 10
    });

    test('asShortTxId returns a short id whole without a RangeError '
        '(issue #657 P9 L1 regression)', () {
      // Anything not longer than the elided form is shown whole; the old code
      // crashed with a RangeError on substring(0, 10) / substring(length - 10)
      // for these inputs.
      expect('0xabc'.asShortTxId, '0xabc');
      expect(''.asShortTxId, '');
      expect('0x12345678'.asShortTxId, '0x12345678'); // length 10, would overlap
    });
  });
}
