import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/models/balance.dart';
import 'package:realunit_wallet/packages/config/api_config.dart';
import 'package:realunit_wallet/packages/config/network_mode.dart';
import 'package:realunit_wallet/packages/repository/balance_repository.dart';
import 'package:realunit_wallet/packages/repository/cache_repository.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/balance_service.dart';
import 'package:realunit_wallet/packages/service/session_cache.dart';
import 'package:realunit_wallet/packages/utils/default_assets.dart';

class MockApiConfig extends Mock implements ApiConfig {}

class MockBalanceRepository extends Mock implements BalanceRepository {}

class MockCacheRepository extends Mock implements CacheRepository {}

class TestAppStore extends AppStore {
  final http.Client client;

  TestAppStore(this.client, ApiConfig Function() apiConfig, CacheRepository cacheRepository)
    : super(apiConfig, SessionCache(cacheRepository));

  @override
  http.Client get httpClient => client;
}

void main() {
  late ApiConfig apiConfig;
  late BalanceService balanceService;
  late MockBalanceRepository balanceRepository;

  setUp(() {
    apiConfig = MockApiConfig();
    balanceRepository = MockBalanceRepository();

    when(() => apiConfig.apiHost).thenReturn('dev.api.dfx.swiss');
    when(() => apiConfig.networkMode).thenReturn(NetworkMode.testnet);
    when(() => apiConfig.asset).thenReturn(realUnitAsset);

    when(() => balanceRepository.saveBalance(any())).thenAnswer((_) async {});
  });

  setUpAll(() {
    registerFallbackValue(
      Balance(
        chainId: 1,
        contractAddress: '0x0',
        walletAddress: '0x0',
        balance: BigInt.zero,
        asset: realUnitAsset,
      ),
    );
    registerFallbackValue(realUnitAsset);
  });

  AppStore buildAppStore(Future<http.Response> Function(http.Request) handler) {
    final client = MockClient(handler);
    return TestAppStore(client, () => apiConfig, MockCacheRepository())
      ..sessionCache.setAuthToken('test-auth-token', '0xTestAddress');
  }

  group('$BalanceService', () {
    group('RealUnit Balance', () {
      test('is updated successfully', () async {
        String? capturedUrl;
        String? capturedMethod;
        Balance? savedBalance;
        final address = '0xTestAddress';

        when(() => balanceRepository.saveBalance(any())).thenAnswer((inv) async {
          savedBalance = inv.positionalArguments[0] as Balance;
        });

        final appStore = buildAppStore((request) async {
          capturedUrl = request.url.toString();
          capturedMethod = request.method;

          return http.Response(
            jsonEncode({
              'balance': '12345',
              'addressType': 0,
            }),
            200,
          );
        });

        balanceService = BalanceService(balanceRepository, appStore);
        await balanceService.updateBalance(address);

        expect(capturedMethod, equals('GET'));
        expect(capturedUrl, contains(apiConfig.apiHost));
        expect(capturedUrl, contains('/v1/realunit/account/'));
        expect(capturedUrl, contains(address));

        expect(savedBalance, isNotNull);
        expect(savedBalance!.balance, equals(BigInt.from(12345)));
        expect(savedBalance!.asset.symbol, equals(realUnitAsset.symbol));
        expect(savedBalance!.walletAddress, equals(address));
      });

      test('skips updating when error occurs', () async {
        final appStore = buildAppStore((request) async {
          return http.Response('{"error": "Server error"}', 500);
        });

        final service = BalanceService(balanceRepository, appStore);

        await expectLater(
          service.updateBalance('0xTestAddress'),
          completes,
        );

        verifyNever(() => balanceRepository.saveBalance(any()));
      });

      test('skips saving when the JSON has no balance field', () async {
        final appStore = buildAppStore(
          (_) async => http.Response(jsonEncode({'addressType': 0}), 200),
        );

        final service = BalanceService(balanceRepository, appStore);
        await service.updateBalance('0xAnyAddress');

        verifyNever(() => balanceRepository.saveBalance(any()));
      });

      test('catches a non-numeric balance string and skips saving', () async {
        // Production code does BigInt.parse on the value; non-numeric raises
        // FormatException which the catch-block swallows.
        final appStore = buildAppStore(
          (_) async => http.Response(jsonEncode({'balance': 'NaN'}), 200),
        );

        final service = BalanceService(balanceRepository, appStore);
        await service.updateBalance('0xAnyAddress');

        verifyNever(() => balanceRepository.saveBalance(any()));
      });

      test('updateBalance with malformed JSON body does not crash', () async {
        final appStore = buildAppStore(
          (_) async => http.Response('not json', 200),
        );

        final service = BalanceService(balanceRepository, appStore);
        await service.updateBalance('0xTestAddress');

        verifyNever(() => balanceRepository.saveBalance(any()));
      });

      group('fetchBalance', () {
        test('returns and persists a fresh balance on 200', () async {
          Balance? savedBalance;
          when(() => balanceRepository.saveBalance(any())).thenAnswer((invocation) async {
            savedBalance = invocation.positionalArguments.single as Balance;
          });
          final appStore = buildAppStore(
            (_) async => http.Response(jsonEncode({'balance': '98765'}), 200),
          );
          final service = BalanceService(balanceRepository, appStore);

          final balance = await service.fetchBalance('0xFresh');

          expect(balance.balance, BigInt.from(98765));
          expect(balance.walletAddress, '0xFresh');
          expect(balance.asset, realUnitAsset);
          expect(savedBalance, same(balance));
        });

        for (final statusCode in const [404, 500]) {
          test('throws on HTTP $statusCode without persisting', () async {
            final appStore = buildAppStore(
              (_) async => http.Response('error', statusCode),
            );
            final service = BalanceService(balanceRepository, appStore);

            await expectLater(
              service.fetchBalance('0xFresh'),
              throwsA(
                isA<Exception>().having(
                  (error) => error.toString(),
                  'message',
                  contains('$statusCode'),
                ),
              ),
            );
            verifyNever(() => balanceRepository.saveBalance(any()));
          });
        }

        test('rethrows a transport failure without persisting', () async {
          final appStore = buildAppStore(
            (_) async => throw http.ClientException('offline'),
          );
          final service = BalanceService(balanceRepository, appStore);

          await expectLater(
            service.fetchBalance('0xFresh'),
            throwsA(isA<http.ClientException>()),
          );
          verifyNever(() => balanceRepository.saveBalance(any()));
        });

        test('throws on an unparseable balance body without persisting', () async {
          final appStore = buildAppStore(
            (_) async => http.Response(jsonEncode({'balance': 'NaN'}), 200),
          );
          final service = BalanceService(balanceRepository, appStore);

          await expectLater(
            service.fetchBalance('0xFresh'),
            throwsA(isA<FormatException>()),
          );
          verifyNever(() => balanceRepository.saveBalance(any()));
        });
      });
    });

    test('getBalance delegates to BalanceRepository.getBalance', () async {
      final expected = Balance(
        chainId: realUnitAsset.chainId,
        contractAddress: realUnitAsset.address,
        walletAddress: '0xAnyAddress',
        balance: BigInt.from(42),
        asset: realUnitAsset,
      );
      when(() => balanceRepository.getBalance(any(), any())).thenAnswer((_) async => expected);

      final appStore = buildAppStore((_) async => http.Response('{}', 200));
      final service = BalanceService(balanceRepository, appStore);

      final result = await service.getBalance(realUnitAsset, '0xAnyAddress');

      expect(result, same(expected));
      verify(() => balanceRepository.getBalance(realUnitAsset, '0xAnyAddress')).called(1);
    });

    test('cancelSync is a safe no-op before startSync has run', () {
      final appStore = buildAppStore((_) async => http.Response('{}', 200));
      final service = BalanceService(balanceRepository, appStore);

      // Should not throw.
      service.cancelSync();
    });

    // startSync installs a 10-second Timer.periodic and is otherwise dead-code
    // from coverage's POV. fake_async drives virtual time so we can assert the
    // tick cadence without a wall-clock sleep that would flake CI.
    group('startSync', () {
      test('runs updateBalance once per 10-second tick of the periodic timer', () {
        // Each tick must hit the network with the same address — proves the
        // periodic body is bound to the address arg passed to startSync, not
        // to an arbitrary captured one.
        fakeAsync((async) {
          final addresses = <String>[];
          final appStore = buildAppStore((request) async {
            addresses.add(request.url.pathSegments.last);
            return http.Response(jsonEncode({'balance': '7'}), 200);
          });
          final service = BalanceService(balanceRepository, appStore);

          service.startSync('0xPeriodic');

          // Just before the first tick — no network call yet (Timer.periodic
          // does not fire on T+0).
          async.elapse(const Duration(seconds: 9));
          expect(addresses, isEmpty);

          // One tick lands at T=10.
          async.elapse(const Duration(seconds: 1));
          async.flushMicrotasks();
          expect(addresses, ['0xPeriodic']);

          // Two more ticks at T=20 and T=30.
          async.elapse(const Duration(seconds: 20));
          async.flushMicrotasks();
          expect(addresses, ['0xPeriodic', '0xPeriodic', '0xPeriodic']);

          // Cancel so the fake_async zone doesn't complain about pending timers.
          service.cancelSync();
        });
      });

      test('a second startSync cancels the previous periodic before installing the new one', () {
        // Without the `cancelSync()` inside startSync, both periodics would
        // fire and we'd see calls for both addresses every interval. The pin
        // here is the absence of '0xOld' calls after the second startSync.
        fakeAsync((async) {
          final addresses = <String>[];
          final appStore = buildAppStore((request) async {
            addresses.add(request.url.pathSegments.last);
            return http.Response(jsonEncode({'balance': '0'}), 200);
          });
          final service = BalanceService(balanceRepository, appStore);

          service.startSync('0xOld');
          async.elapse(const Duration(seconds: 5));
          service.startSync('0xNew');

          // From T=5 the only active periodic targets 0xNew, so the next tick
          // — at T=15 from the new periodic's start at T=5 — fires for 0xNew.
          async.elapse(const Duration(seconds: 30));
          async.flushMicrotasks();

          expect(
            addresses,
            everyElement('0xNew'),
            reason:
                'the previous periodic must have been cancelled, '
                'so no 0xOld probes leak through',
          );
          expect(addresses, isNotEmpty);

          service.cancelSync();
        });
      });

      test('cancelSync stops the periodic and prevents further ticks', () {
        fakeAsync((async) {
          var calls = 0;
          final appStore = buildAppStore((_) async {
            calls++;
            return http.Response(jsonEncode({'balance': '1'}), 200);
          });
          final service = BalanceService(balanceRepository, appStore);

          service.startSync('0xCancelMe');
          async.elapse(const Duration(seconds: 10));
          async.flushMicrotasks();
          final callsAtCancel = calls;
          expect(callsAtCancel, 1);

          service.cancelSync();
          async.elapse(const Duration(minutes: 5));
          async.flushMicrotasks();

          expect(calls, callsAtCancel, reason: 'cancelled timer must not tick again');
        });
      });

      // A wallet with no RealUnit account 404s on every probe; the poll must stop
      // hitting the endpoint after the first 404 instead of hammering it every 10s.
      group('no RealUnit account (404)', () {
        test('stops probing the network after a 404', () {
          fakeAsync((async) {
            var calls = 0;
            final appStore = buildAppStore((_) async {
              calls++;
              return http.Response(
                jsonEncode({
                  'statusCode': 404,
                  'message': 'Account not found',
                  'error': 'Not Found',
                }),
                404,
              );
            });
            final service = BalanceService(balanceRepository, appStore);

            service.startSync('0xNoAccount');

            // First tick at T=10 hits the network once and gets a 404.
            async.elapse(const Duration(seconds: 10));
            async.flushMicrotasks();
            expect(calls, 1);

            // Every later tick must be a no-op — no more 404 spam.
            async.elapse(const Duration(minutes: 5));
            async.flushMicrotasks();
            expect(calls, 1, reason: 'after a 404 the poll must stop hitting the endpoint');

            service.cancelSync();
          });
        });

        test('a fresh startSync re-checks after a previous 404', () {
          fakeAsync((async) {
            var calls = 0;
            final appStore = buildAppStore((_) async {
              calls++;
              return http.Response('{"error": "Not Found"}', 404);
            });
            final service = BalanceService(balanceRepository, appStore);

            service.startSync('0xAddr');
            async.elapse(const Duration(seconds: 10));
            async.flushMicrotasks();
            expect(calls, 1);

            // Onboarding / app-resume re-runs startSync, which must clear the
            // missing-account flag and probe again (the account may now exist).
            service.startSync('0xAddr');
            async.elapse(const Duration(seconds: 10));
            async.flushMicrotasks();
            expect(calls, 2, reason: 'startSync must reset the flag and re-probe');

            service.cancelSync();
          });
        });

        test('a direct updateBalance call still probes after a 404 latched the flag', () {
          // The app-resume path (lifecycle_initializer) calls updateBalance
          // directly, without startSync — it must not be gated by the flag.
          fakeAsync((async) {
            var calls = 0;
            final appStore = buildAppStore((_) async {
              calls++;
              return http.Response('{"error": "Not Found"}', 404);
            });
            final service = BalanceService(balanceRepository, appStore);

            service.startSync('0xAddr');
            async.elapse(const Duration(seconds: 10));
            async.flushMicrotasks();
            expect(calls, 1);

            service.updateBalance('0xAddr');
            async.flushMicrotasks();
            expect(calls, 2, reason: 'direct calls must bypass the missing-account gate');

            service.cancelSync();
          });
        });

        test('a 200 on a direct probe un-latches the flag so the periodic resumes', () {
          fakeAsync((async) {
            var calls = 0;
            var accountExists = false;
            final appStore = buildAppStore((_) async {
              calls++;
              return accountExists
                  ? http.Response(jsonEncode({'balance': '5'}), 200)
                  : http.Response('{"error": "Not Found"}', 404);
            });
            final service = BalanceService(balanceRepository, appStore);

            service.startSync('0xAddr');
            async.elapse(const Duration(seconds: 10));
            async.flushMicrotasks();
            expect(calls, 1);

            // Ticks are gated while the account is missing.
            async.elapse(const Duration(seconds: 30));
            async.flushMicrotasks();
            expect(calls, 1);

            // Account gets created out-of-band; a direct probe (app resume)
            // sees the 200 and must re-enable the periodic poll.
            accountExists = true;
            service.updateBalance('0xAddr');
            async.flushMicrotasks();
            expect(calls, 2);

            async.elapse(const Duration(seconds: 20));
            async.flushMicrotasks();
            expect(calls, 4, reason: 'ticks must resume once a probe confirmed the account');

            service.cancelSync();
          });
        });

        // Reproduces the real re-arm sequence from HomeBloc._updateWallet: an
        // unawaited updateBalance fired immediately before startSync. That eager
        // probe's response resolves AFTER startSync's synchronous reset, so a 404
        // from it must not re-latch the flag and gate the just-armed poll.
        test('a re-arm (eager updateBalance then startSync) survives the eager 404', () {
          fakeAsync((async) {
            var calls = 0;
            var accountExists = false;
            final appStore = buildAppStore((_) async {
              calls++;
              return accountExists
                  ? http.Response(jsonEncode({'balance': '5'}), 200)
                  : http.Response('{"error": "Not Found"}', 404);
            });
            final service = BalanceService(balanceRepository, appStore);

            // Same order as _updateWallet: eager probe (still 404) then startSync.
            service.updateBalance('0xAddr');
            service.startSync('0xAddr');
            async.flushMicrotasks();
            expect(calls, 1, reason: 'only the eager probe has run so far');

            // Account now exists; the armed poll must probe again at T=10 — the
            // stale eager 404 must not have gated it.
            accountExists = true;
            async.elapse(const Duration(seconds: 10));
            async.flushMicrotasks();
            expect(calls, 2, reason: 'a stale eager 404 must not gate the freshly armed poll');

            // And it keeps polling normally now that the account exists.
            async.elapse(const Duration(seconds: 10));
            async.flushMicrotasks();
            expect(calls, 3);

            service.cancelSync();
          });
        });

        // Only a definitive 404 pauses the poll. A transient server error must
        // keep probing so the balance recovers on its own once the backend heals.
        test('a transient 5xx does not latch the poll', () {
          fakeAsync((async) {
            var calls = 0;
            var failing = true;
            final appStore = buildAppStore((_) async {
              calls++;
              return failing
                  ? http.Response('{"error": "Server error"}', 500)
                  : http.Response(jsonEncode({'balance': '5'}), 200);
            });
            final service = BalanceService(balanceRepository, appStore);

            service.startSync('0xAddr');

            async.elapse(const Duration(seconds: 10));
            async.flushMicrotasks();
            expect(calls, 1, reason: 'first tick hits a 500');

            async.elapse(const Duration(seconds: 10));
            async.flushMicrotasks();
            expect(calls, 2, reason: 'a 5xx must not latch — the next tick keeps probing');

            failing = false;
            async.elapse(const Duration(seconds: 10));
            async.flushMicrotasks();
            expect(calls, 3, reason: 'poll recovers to 200 without any restart');

            service.cancelSync();
          });
        });

        // A slow probe issued before the latest startSync can resolve out of
        // order, after a fresh sync already reset the flag. Its stale 404 belongs
        // to an old generation and must not re-gate the current poll.
        test('an out-of-order stale response cannot re-gate a re-armed poll', () {
          fakeAsync((async) {
            final pending = <Completer<http.Response>>[];
            final appStore = buildAppStore((_) {
              final completer = Completer<http.Response>();
              pending.add(completer);
              return completer.future;
            });
            final service = BalanceService(balanceRepository, appStore);

            // Probe R1 fired while the account was still missing (will 404 late).
            service.updateBalance('0xAddr');
            async.flushMicrotasks();
            expect(pending.length, 1);

            // A fresh startSync bumps the generation, resets the flag, arms the poll.
            service.startSync('0xAddr');

            // The stale R1 now resolves 404 — from the old generation, so it must
            // be ignored and must NOT re-latch the flag.
            pending[0].complete(http.Response('{"error": "Not Found"}', 404));
            async.flushMicrotasks();

            // The armed poll must still probe at T=10 (flag was not re-latched).
            async.elapse(const Duration(seconds: 10));
            async.flushMicrotasks();
            expect(pending.length, 2, reason: 'a stale 404 must not gate the armed poll');
            pending[1].complete(http.Response(jsonEncode({'balance': '5'}), 200));
            async.flushMicrotasks();

            // Account confirmed by the in-generation 200 — polling keeps running.
            async.elapse(const Duration(seconds: 10));
            async.flushMicrotasks();
            expect(pending.length, 3);

            service.cancelSync();
          });
        });

        // The reverse of the un-latch: after a 200 cleared the flag, a later 404
        // (account removed server-side) must re-latch it and stop the ticks.
        test('a 404 after a 200 re-latches and stops the poll', () {
          fakeAsync((async) {
            var calls = 0;
            var accountExists = true;
            final appStore = buildAppStore((_) async {
              calls++;
              return accountExists
                  ? http.Response(jsonEncode({'balance': '5'}), 200)
                  : http.Response('{"error": "Not Found"}', 404);
            });
            final service = BalanceService(balanceRepository, appStore);

            service.startSync('0xAddr');

            // While the account exists the poll keeps ticking (200 clears the flag).
            async.elapse(const Duration(seconds: 20));
            async.flushMicrotasks();
            expect(calls, 2, reason: 'poll keeps ticking while the account exists');

            // Account removed server-side: the next tick 404s and must re-latch.
            accountExists = false;
            async.elapse(const Duration(seconds: 10));
            async.flushMicrotasks();
            expect(calls, 3, reason: 'the 404 tick still fires');

            // Now gated again — no further probes.
            async.elapse(const Duration(minutes: 5));
            async.flushMicrotasks();
            expect(calls, 3, reason: 'a 404 after a 200 must re-latch and stop the poll');

            service.cancelSync();
          });
        });

        // Symmetric to the out-of-order 404 case: a slow 200 from an OLD
        // generation must not clear the flag after a fresh startSync re-armed and
        // an in-generation 404 latched the gate — otherwise the stale 200 would
        // wrongly un-gate the poll.
        test('an out-of-order stale 200 cannot un-gate a re-latched poll', () {
          fakeAsync((async) {
            final pending = <Completer<http.Response>>[];
            final appStore = buildAppStore((_) {
              final completer = Completer<http.Response>();
              pending.add(completer);
              return completer.future;
            });
            final service = BalanceService(balanceRepository, appStore);

            // Probe R1 issued in the current generation (will resolve 200 late).
            service.updateBalance('0xAddr');
            async.flushMicrotasks();
            expect(pending.length, 1);

            // A fresh startSync bumps the generation and arms the poll.
            service.startSync('0xAddr');

            // The armed poll's first tick (new generation) 404s and latches.
            async.elapse(const Duration(seconds: 10));
            async.flushMicrotasks();
            expect(pending.length, 2);
            pending[1].complete(http.Response('{"error": "Not Found"}', 404));
            async.flushMicrotasks();

            // Now the stale R1 resolves 200 — from the OLD generation, so it must
            // NOT clear the flag. The poll must stay gated.
            pending[0].complete(http.Response(jsonEncode({'balance': '5'}), 200));
            async.flushMicrotasks();

            async.elapse(const Duration(minutes: 5));
            async.flushMicrotasks();
            expect(pending.length, 2, reason: 'a stale 200 must not un-gate the re-latched poll');

            service.cancelSync();
          });
        });
      });
    });
  });
}
