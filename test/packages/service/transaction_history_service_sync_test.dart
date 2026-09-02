import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/models/dfx_transaction.dart';
import 'package:realunit_wallet/models/transaction.dart';
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

class _FakeTransaction extends Fake implements Transaction {}

class _FakeDfxTransaction extends Fake implements DfxTransaction {}

const _wallet = '0x000000000000000000000000000000000000beef';
const _other = '0x0000000000000000000000000000000000001234';

Map<String, dynamic> _historyEntry({
  required String txHash,
  String from = _other,
  String to = _wallet,
  String value = '1000000',
  String timestamp = '2026-01-01T00:00:00Z',
  String? category,
}) =>
    {
      'timestamp': timestamp,
      'txHash': txHash,
      'transfer': {
        'from': from,
        'to': to,
        'value': value,
      },
      if (category != null) 'category': category,
    };

Map<String, dynamic> _accountHistory(List<Map<String, dynamic>> events) => {
      'address': _wallet,
      'history': events,
      'totalCount': events.length,
    };

Map<String, dynamic> _txJson({
  int id = 1,
  String? inputTxId,
  String? outputTxId,
  String state = 'Completed',
}) =>
    {
      'id': id,
      'type': 'Buy',
      'state': state,
      'rate': 1.0,
      'inputAmount': 100.0,
      'inputAsset': 'CHF',
      'inputTxId': inputTxId,
      'outputAmount': 1.0,
      'outputAsset': 'REALU',
      'outputTxId': outputTxId,
    };

void main() {
  late _MockAppStore appStore;
  late _MockWalletService walletService;
  late SessionCache sessionCache;
  late _MockTransactionRepository txRepo;

  setUpAll(() {
    registerFallbackValue(_FakeTransaction());
    registerFallbackValue(_FakeDfxTransaction());
  });

  setUp(() {
    appStore = _MockAppStore();
    walletService = _MockWalletService();
    sessionCache = SessionCache(_MockCacheRepository());
    txRepo = _MockTransactionRepository();
    when(() => appStore.sessionCache).thenReturn(sessionCache);
    when(() => appStore.apiConfig)
        .thenReturn(const ApiConfig(networkMode: NetworkMode.mainnet));
    when(() => appStore.primaryAddress).thenReturn(_wallet);
    when(() => txRepo.existsTransaction(any())).thenAnswer((_) async => false);
    when(() => txRepo.insertTransaction(any())).thenAnswer((_) async => 1);
    when(() => txRepo.insertDfxTransaction(any())).thenAnswer((_) async {});
    when(() => txRepo.updateTransaction(any())).thenAnswer((_) async => 1);
    when(() => txRepo.updateDfxTransaction(any())).thenAnswer((_) async {});
    when(() => walletService.ensureCurrentWalletUnlocked()).thenAnswer((_) async {});
    when(() => walletService.lockCurrentWallet()).thenAnswer((_) async {});
  });

  TransactionHistoryService build(http.Client client) {
    when(() => appStore.httpClient).thenReturn(client);
    return TransactionHistoryService(appStore, walletService, txRepo);
  }

  group('$TransactionHistoryService.apiBasedSync', () {
    test('does nothing when accountHistory returns non-200', () async {
      // Both endpoints are called via Future.wait. accountHistory non-200 →
      // null result → early return; transactions endpoint result is
      // ignored.
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/history')) {
          return http.Response('boom', 500);
        }
        return http.Response('[]', 200);
      });

      await build(client).apiBasedSync();

      verifyNever(() => txRepo.insertTransaction(any()));
      verifyNever(() => txRepo.insertDfxTransaction(any()));
    });

    test('skips entries with no transfer', () async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/history')) {
          return http.Response(
            jsonEncode({
              'address': _wallet,
              'history': [
                {
                  'timestamp': '2026-01-01T00:00:00Z',
                  'txHash': '0xnotransfer',
                  // transfer: null
                },
              ],
              'totalCount': 1,
            }),
            200,
          );
        }
        return http.Response('[]', 200);
      });

      await build(client).apiBasedSync();

      verifyNever(() => txRepo.insertTransaction(any()));
      verifyNever(() => txRepo.insertDfxTransaction(any()));
    });

    test('inserts a plain Transaction when there is no matching DFX entry', () async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/history')) {
          return http.Response(
            jsonEncode(_accountHistory([_historyEntry(txHash: '0xabc')])),
            200,
          );
        }
        // /v1/transaction returns [] → no matching DFX entry.
        return http.Response('[]', 200);
      });

      await build(client).apiBasedSync();

      final captured = verify(
        () => txRepo.insertTransaction(captureAny()),
      ).captured.single as Transaction;
      expect(captured.txId, '0xabc');
      expect(captured.amount, BigInt.from(1000000));
      expect(captured.category, isNull);
      verifyNever(() => txRepo.insertDfxTransaction(any()));
    });

    test('carries the API transfer category into the stored transaction', () async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/history')) {
          return http.Response(
            jsonEncode(_accountHistory([_historyEntry(txHash: '0xabc', category: 'transferIn')])),
            200,
          );
        }
        return http.Response('[]', 200);
      });

      await build(client).apiBasedSync();

      final captured = verify(
        () => txRepo.insertTransaction(captureAny()),
      ).captured.single as Transaction;
      expect(captured.category, TransferCategory.transferIn);
    });

    test('ignores an unknown category value instead of failing the sync', () async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/history')) {
          return http.Response(
            jsonEncode(_accountHistory([_historyEntry(txHash: '0xabc', category: 'somethingNew')])),
            200,
          );
        }
        return http.Response('[]', 200);
      });

      await build(client).apiBasedSync();

      final captured = verify(
        () => txRepo.insertTransaction(captureAny()),
      ).captured.single as Transaction;
      expect(captured.category, isNull);
    });

    test('inserts a DFX-enriched transaction when /v1/transaction has a matching id', () async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/history')) {
          return http.Response(
            jsonEncode(_accountHistory([_historyEntry(txHash: '0xabc')])),
            200,
          );
        }
        return http.Response(
          jsonEncode([_txJson(id: 42, inputTxId: '0xabc')]),
          200,
        );
      });

      await build(client).apiBasedSync();

      final captured = verify(
        () => txRepo.insertDfxTransaction(captureAny()),
      ).captured.single as DfxTransaction;
      expect(captured.txId, '0xabc');
      expect(captured.dfxId, 42);
      verifyNever(() => txRepo.insertTransaction(any()));
    });

    test('updates existing transactions instead of inserting', () async {
      when(() => txRepo.existsTransaction('0xabc')).thenAnswer((_) async => true);
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/history')) {
          return http.Response(
            jsonEncode(_accountHistory([_historyEntry(txHash: '0xabc')])),
            200,
          );
        }
        return http.Response('[]', 200);
      });

      await build(client).apiBasedSync();

      verify(() => txRepo.updateTransaction(any())).called(1);
      verifyNever(() => txRepo.insertTransaction(any()));
    });

    test('updates an existing DFX transaction when matched', () async {
      when(() => txRepo.existsTransaction('0xabc')).thenAnswer((_) async => true);
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/history')) {
          return http.Response(
            jsonEncode(_accountHistory([_historyEntry(txHash: '0xabc')])),
            200,
          );
        }
        return http.Response(
          jsonEncode([_txJson(id: 42, inputTxId: '0xabc')]),
          200,
        );
      });

      await build(client).apiBasedSync();

      verify(() => txRepo.updateDfxTransaction(any())).called(1);
      verifyNever(() => txRepo.insertDfxTransaction(any()));
    });

    test('matches outputTxId (not just inputTxId) when finding the DFX record', () async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/history')) {
          return http.Response(
            jsonEncode(_accountHistory([_historyEntry(txHash: '0xouttx')])),
            200,
          );
        }
        return http.Response(
          jsonEncode([_txJson(id: 7, outputTxId: '0xouttx')]),
          200,
        );
      });

      await build(client).apiBasedSync();

      final captured = verify(
        () => txRepo.insertDfxTransaction(captureAny()),
      ).captured.single as DfxTransaction;
      expect(captured.dfxId, 7);
    });

    test('ignores DFX rows without an id (null id) and falls back to plain insert', () async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/history')) {
          return http.Response(
            jsonEncode(_accountHistory([_historyEntry(txHash: '0xabc')])),
            200,
          );
        }
        return http.Response(
          jsonEncode([
            {
              // No 'id' → null id → cubit code path that falls through to plain insert.
              'type': 'Buy',
              'state': 'Completed',
              'inputTxId': '0xabc',
            },
          ]),
          200,
        );
      });

      await build(client).apiBasedSync();

      verify(() => txRepo.insertTransaction(any())).called(1);
      verifyNever(() => txRepo.insertDfxTransaction(any()));
    });
  });
}
