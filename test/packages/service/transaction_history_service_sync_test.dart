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
}) => {
  'timestamp': timestamp,
  'txHash': txHash,
  'transfer': {
    'from': from,
    'to': to,
    'value': value,
  },
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
}) => {
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
    when(() => appStore.apiConfig).thenReturn(const ApiConfig(networkMode: NetworkMode.mainnet));
    when(() => appStore.primaryAddress).thenReturn(_wallet);
    when(() => txRepo.existsTransaction(any())).thenAnswer((_) async => false);
    when(() => txRepo.findTxIdIgnoreCase(any())).thenAnswer((inv) async {
      final id = inv.positionalArguments[0] as String;
      return await txRepo.existsTransaction(id) ? id : null;
    });
    when(() => txRepo.isReferralPayoutIgnoreCase(any())).thenAnswer((_) async => false);
    when(() => txRepo.deleteTransaction(any())).thenAnswer((_) async => 1);
    when(
      () => txRepo.deleteDfxTransactionDetailsIgnoreCase(any()),
    ).thenAnswer((_) async => 0);
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

      final captured =
          verify(
                () => txRepo.insertTransaction(captureAny()),
              ).captured.single
              as Transaction;
      expect(captured.txId, '0xabc');
      expect(captured.amount, BigInt.from(1000000));
      verifyNever(() => txRepo.insertDfxTransaction(any()));
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

      final captured =
          verify(
                () => txRepo.insertDfxTransaction(captureAny()),
              ).captured.single
              as DfxTransaction;
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

    test(
      'does not rewrite a prize as a buy when account history repeats the hash',
      () async {
        sessionCache.setAuthToken('jwt-1');
        when(() => txRepo.isReferralPayoutIgnoreCase('0xprize')).thenAnswer((_) async => true);
        final client = MockClient((request) async {
          if (request.url.path.endsWith('/history')) {
            return http.Response(
              jsonEncode(_accountHistory([_historyEntry(txHash: '0xprize')])),
              200,
            );
          }
          if (request.url.path.contains('/referral/payouts')) {
            return http.Response('[]', 200);
          }
          return http.Response('[]', 200);
        });

        await build(client).apiBasedSync();

        verifyNever(() => txRepo.updateTransaction(any()));
        verifyNever(() => txRepo.insertTransaction(any()));
        verifyNever(() => txRepo.updateDfxTransaction(any()));
        verifyNever(() => txRepo.insertDfxTransaction(any()));
      },
    );

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

      final captured =
          verify(
                () => txRepo.insertDfxTransaction(captureAny()),
              ).captured.single
              as DfxTransaction;
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

    test('a settled payout with no txHash gets a synthetic id-based txId', () async {
      sessionCache.setAuthToken('jwt-1');
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/history')) {
          return http.Response(jsonEncode(_accountHistory([])), 200);
        }
        if (request.url.path.contains('/referral/payouts')) {
          return http.Response(
            jsonEncode([
              {
                'id': 9,
                'amount': 20,
                'chfValue': 246.5,
                'created': '2026-08-24T10:00:00Z',
                'kind': 'Invite',
                'status': 'Complete',
              },
            ]),
            200,
          );
        }
        return http.Response('[]', 200);
      });

      await build(client).apiBasedSync();

      final captured =
          verify(() => txRepo.insertTransaction(captureAny())).captured.single
              as Transaction;
      expect(captured.txId, 'referral-payout-9');
      expect(captured.type, TransactionTypes.referralPayout);
    });

    test('writes referral payouts with frozen CHF even when chain history is empty', () async {
      sessionCache.setAuthToken('jwt-1');
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/history')) {
          return http.Response(jsonEncode(_accountHistory([])), 200);
        }
        if (request.url.path.contains('/referral/payouts')) {
          return http.Response(
            jsonEncode([
              {
                'id': 9,
                'amount': 20,
                'chfValue': 246.5,
                'created': '2026-08-24T10:00:00Z',
                'kind': 'Invite',
                'status': 'Complete',
                'txHash': '0xpayout',
              },
            ]),
            200,
          );
        }
        return http.Response('[]', 200);
      });

      await build(client).apiBasedSync();

      final captured =
          verify(
                () => txRepo.insertTransaction(captureAny()),
              ).captured.single
              as Transaction;
      expect(captured.txId, '0xpayout');
      expect(captured.type, TransactionTypes.referralPayout);
      expect(captured.amount, BigInt.from(20));
      expect(captured.data, '246.50');
    });

    test('truncates a fractional REALU prize and never rounds up', () async {
      sessionCache.setAuthToken('jwt-1');
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/history')) {
          return http.Response(jsonEncode(_accountHistory([])), 200);
        }
        if (request.url.path.contains('/referral/payouts')) {
          return http.Response(
            jsonEncode([
              {
                'id': 9,
                'amount': 20.9,
                'chfValue': '246,5',
                'created': '2026-08-24T10:00:00Z',
                'kind': 'Invite',
                'status': 'Complete',
                'txHash': '0xfrac',
              },
            ]),
            200,
          );
        }
        return http.Response('[]', 200);
      });

      await build(client).apiBasedSync();

      final captured =
          verify(
                () => txRepo.insertTransaction(captureAny()),
              ).captured.single
              as Transaction;
      expect(captured.amount, BigInt.from(20));
      expect(captured.data, '246.50');
    });

    test('writes wrapped {payouts: [...]} rows with frozen CHF', () async {
      sessionCache.setAuthToken('jwt-1');
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/history')) {
          return http.Response(jsonEncode(_accountHistory([])), 200);
        }
        if (request.url.path.contains('/referral/payouts')) {
          return http.Response(
            jsonEncode({
              'payouts': [
                {
                  'id': 9,
                  'amount': 20,
                  'chfValue': 246.5,
                  'created': '2026-08-24T10:00:00Z',
                  'kind': 'Invite',
                  'status': 'Complete',
                  'txHash': '0xwrap',
                },
              ],
            }),
            200,
          );
        }
        return http.Response('[]', 200);
      });

      await build(client).apiBasedSync();

      final captured =
          verify(
                () => txRepo.insertTransaction(captureAny()),
              ).captured.single
              as Transaction;
      expect(captured.txId, '0xwrap');
      expect(captured.type, TransactionTypes.referralPayout);
      expect(captured.data, '246.50');
    });

    test('does not write pending referral payouts into history', () async {
      sessionCache.setAuthToken('jwt-1');
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/history')) {
          return http.Response(jsonEncode(_accountHistory([])), 200);
        }
        if (request.url.path.contains('/referral/payouts')) {
          return http.Response(
            jsonEncode([
              {
                'id': 9,
                'amount': 20,
                'chfValue': 246.5,
                'created': '2026-08-24T10:00:00Z',
                'kind': 'Invite',
                'status': 'Pending',
              },
            ]),
            200,
          );
        }
        return http.Response('[]', 200);
      });

      await build(client).apiBasedSync();

      verifyNever(() => txRepo.insertTransaction(any()));
    });

    test('updates an existing payout row when the hash casing differs', () async {
      sessionCache.setAuthToken('jwt-1');
      when(() => txRepo.existsTransaction('0xPayOut')).thenAnswer((_) async => false);
      when(() => txRepo.existsTransaction('0xpayout')).thenAnswer((_) async => true);
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/history')) {
          return http.Response(jsonEncode(_accountHistory([])), 200);
        }
        if (request.url.path.contains('/referral/payouts')) {
          return http.Response(
            jsonEncode([
              {
                'id': 9,
                'amount': 20,
                'chfValue': 246.5,
                'created': '2026-08-24T10:00:00Z',
                'kind': 'Invite',
                'status': 'Complete',
                'txHash': '0xPayOut',
              },
            ]),
            200,
          );
        }
        return http.Response('[]', 200);
      });

      await build(client).apiBasedSync();

      final captured =
          verify(
                () => txRepo.updateTransaction(captureAny()),
              ).captured.single
              as Transaction;
      expect(captured.txId, '0xpayout');
      expect(captured.type, TransactionTypes.referralPayout);
      verifyNever(() => txRepo.insertTransaction(any()));
    });

    test(
      'converts a mixed-case on-chain transfer to a prize instead of inserting a second row',
      () async {
        sessionCache.setAuthToken('jwt-1');
        when(() => txRepo.findTxIdIgnoreCase('0xpayout')).thenAnswer((_) async => '0xPayOut');
        final client = MockClient((request) async {
          if (request.url.path.endsWith('/history')) {
            return http.Response(jsonEncode(_accountHistory([])), 200);
          }
          if (request.url.path.contains('/referral/payouts')) {
            return http.Response(
              jsonEncode([
                {
                  'id': 9,
                  'amount': 20,
                  'chfValue': 246.5,
                  'created': '2026-08-24T10:00:00Z',
                  'kind': 'Invite',
                  'status': 'Complete',
                  'txHash': '0xpayout',
                },
              ]),
              200,
            );
          }
          return http.Response('[]', 200);
        });

        await build(client).apiBasedSync();

        final captured =
            verify(
                  () => txRepo.updateTransaction(captureAny()),
                ).captured.single
                as Transaction;
        expect(captured.txId, '0xPayOut');
        expect(captured.type, TransactionTypes.referralPayout);
        expect(captured.data, '246.50');
        verify(
          () => txRepo.deleteDfxTransactionDetailsIgnoreCase('0xPayOut'),
        ).called(1);
        verifyNever(() => txRepo.insertTransaction(any()));
      },
    );

    test(
      'drops the synthetic payout row once the transfer hash lands',
      () async {
        sessionCache.setAuthToken('jwt-1');
        when(
          () => txRepo.findTxIdIgnoreCase('referral-payout-9'),
        ).thenAnswer((_) async => 'referral-payout-9');
        final client = MockClient((request) async {
          if (request.url.path.endsWith('/history')) {
            return http.Response(jsonEncode(_accountHistory([])), 200);
          }
          if (request.url.path.contains('/referral/payouts')) {
            return http.Response(
              jsonEncode([
                {
                  'id': 9,
                  'amount': 20,
                  'chfValue': 246.5,
                  'created': '2026-08-24T10:00:00Z',
                  'kind': 'Invite',
                  'status': 'Complete',
                  'txHash': '0xabc',
                },
              ]),
              200,
            );
          }
          return http.Response('[]', 200);
        });

        await build(client).apiBasedSync();

        verify(() => txRepo.deleteTransaction('referral-payout-9')).called(1);
        verifyNever(
          () => txRepo.deleteDfxTransactionDetailsIgnoreCase(
            'referral-payout-9',
          ),
        );
        final captured =
            verify(
                  () => txRepo.insertTransaction(captureAny()),
                ).captured.single
                as Transaction;
        expect(captured.txId, '0xabc');
        expect(captured.type, TransactionTypes.referralPayout);
      },
    );

    test('writes a duplicate id or hash in one payload only once', () async {
      sessionCache.setAuthToken('jwt-1');
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/history')) {
          return http.Response(jsonEncode(_accountHistory([])), 200);
        }
        if (request.url.path.contains('/referral/payouts')) {
          return http.Response(
            jsonEncode([
              {
                'id': 7,
                'amount': 20,
                'chfValue': 246.5,
                'created': '2026-08-24T10:00:00Z',
                'kind': 'Invite',
                'status': 'Complete',
                'txHash': '0xabc',
              },
              {
                'id': 7,
                'amount': 20,
                'chfValue': 246.5,
                'created': '2026-08-24T11:00:00Z',
                'kind': 'Invite',
                'status': 'Complete',
                'txHash': '0xdef',
              },
              {
                'id': 8,
                'amount': 20,
                'chfValue': 10,
                'created': '2026-08-24T12:00:00Z',
                'kind': 'Promo',
                'status': 'Complete',
                'txHash': '0xABC',
              },
            ]),
            200,
          );
        }
        return http.Response('[]', 200);
      });

      await build(client).apiBasedSync();

      final captured =
          verify(
                () => txRepo.insertTransaction(captureAny()),
              ).captured.single
              as Transaction;
      expect(captured.txId, '0xabc');
      expect(captured.data, '246.50');
    });

    test('does not write a settled payout with neither id nor tx hash', () async {
      sessionCache.setAuthToken('jwt-1');
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/history')) {
          return http.Response(jsonEncode(_accountHistory([])), 200);
        }
        if (request.url.path.contains('/referral/payouts')) {
          return http.Response(
            jsonEncode([
              {
                'id': 0,
                'amount': 20,
                'chfValue': 246.5,
                'created': '2026-08-24T10:00:00Z',
                'kind': 'Invite',
                'status': 'Complete',
              },
            ]),
            200,
          );
        }
        return http.Response('[]', 200);
      });

      await build(client).apiBasedSync();

      verifyNever(() => txRepo.insertTransaction(any()));
    });
  });
}
