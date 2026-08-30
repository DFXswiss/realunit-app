import 'dart:async';
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
import 'package:realunit_wallet/packages/service/dfx/real_unit_referral_service.dart';
import 'package:realunit_wallet/packages/service/session_cache.dart';
import 'package:realunit_wallet/packages/service/wallet_service.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';
import 'package:realunit_wallet/packages/wallet/wallet_account.dart';

class _MockAppStore extends Mock implements AppStore {}

class _MockWallet extends Mock implements AWallet {}

class _MockAccount extends Mock implements AWalletAccount {}

class _MockCacheRepository extends Mock implements CacheRepository {}

class _MockWalletService extends Mock implements WalletService {}

void main() {
  late _MockAppStore appStore;
  late _MockWallet wallet;
  late _MockAccount account;
  late _MockWalletService walletService;
  late SessionCache session;

  setUp(() {
    appStore = _MockAppStore();
    wallet = _MockWallet();
    account = _MockAccount();
    walletService = _MockWalletService();
    session = SessionCache(_MockCacheRepository());
    session.setAuthToken('jwt-1');

    when(() => appStore.apiConfig).thenReturn(
      const ApiConfig(networkMode: NetworkMode.mainnet),
    );
    when(() => appStore.sessionCache).thenReturn(session);
    when(() => appStore.wallet).thenReturn(wallet);
    when(() => wallet.primaryAccount).thenReturn(account);
    when(() => wallet.currentAccount).thenReturn(account);
    when(() => walletService.ensureCurrentWalletUnlocked()).thenAnswer((_) async {});
    when(() => walletService.lockCurrentWallet()).thenAnswer((_) async {});
  });

  RealUnitReferralService build(http.Client client) {
    when(() => appStore.httpClient).thenReturn(client);
    return RealUnitReferralService(appStore, walletService);
  }

  group('$RealUnitReferralService.getSummary', () {
    test('GETs /v1/realunit/referral/summary with Bearer JWT', () async {
      String? path;
      String? auth;
      final client = MockClient((request) async {
        path = request.url.path;
        auth = request.headers['Authorization'];
        return http.Response(
          jsonEncode({
            'eligible': true,
            'termsAccepted': true,
            'openCount': 0,
            'creditedCount': 0,
            'realuSum': 0,
            'chfSum': 0,
          }),
          200,
        );
      });

      final summary = await build(client).getSummary();

      expect(path, '/v1/realunit/referral/summary');
      expect(auth, 'Bearer jwt-1');
      expect(summary.eligible, isTrue);
    });

    test('unwraps a {summary: {...}} payload and coerces eligible:1', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'summary': {
              'eligible': 1,
              'termsAccepted': 'yes',
              'openCount': 0,
              'creditedCount': 0,
              'realuSum': 0,
              'chfSum': 0,
            },
          }),
          200,
        ),
      );

      final summary = await build(client).getSummary();
      expect(summary.eligible, isTrue);
      expect(summary.termsAccepted, isTrue);
    });

    test('keeps eligible when a sibling data object is present', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'eligible': true,
            'termsAccepted': true,
            'openCount': 1,
            'creditedCount': 0,
            'realuSum': 0,
            'chfSum': 0,
            'data': {'kind': 'Promo'},
          }),
          200,
        ),
      );

      final summary = await build(client).getSummary();
      expect(summary.eligible, isTrue);
      expect(summary.openCount, 1);
    });

    test('throws ApiException on a non-200 response', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({'statusCode': 500, 'code': 'SERVER_ERROR', 'message': 'boom'}),
          500,
        ),
      );

      expect(() => build(client).getSummary(), throwsA(isA<ApiException>()));
    });
  });

  group('$RealUnitReferralService.createInvite', () {
    test('POSTs guestName and parses the created invite', () async {
      Map<String, dynamic>? body;
      final client = MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'code': 'AB12',
            'url': 'https://realunit.app/invite/AB12',
            'guestName': 'Alice',
            'copyText':
                'Hey Alice, Björn lädt dich ein zu RealUnit: https://realunit.app/invite/AB12',
            'copyTextEn':
                'Hey Alice, Björn is inviting you to RealUnit: https://realunit.app/invite/AB12',
            'inviterName': 'Björn',
          }),
          201,
        );
      });

      final created = await build(client).createInvite(guestName: 'Alice');

      expect(body, {'guestName': 'Alice', 'termsAccepted': true});
      expect(created.url, 'https://realunit.app/invite/AB12');
      expect(created.inviterName, 'Björn');
      expect(
        created.copyTextForLocale('en'),
        'Hey Alice, Björn is inviting you to RealUnit: https://realunit.app/invite/AB12',
      );
    });

    test('unwraps an {invite: {...}} create payload', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'invite': {
              'code': 'AB12',
              'url': 'https://realunit.app/invite/AB12',
              'guestName': 'Alice',
            },
          }),
          201,
        ),
      );

      final created = await build(client).createInvite(guestName: 'Alice');
      expect(created.code, 'AB12');
      expect(created.guestName, 'Alice');
    });

    test('throws ApiException on a non-200/201 response', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({'statusCode': 400, 'code': 'LIMIT', 'message': 'max'}),
          400,
        ),
      );

      expect(
        () => build(client).createInvite(guestName: 'Alice'),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('$RealUnitReferralService.lookupCode', () {
    test('GETs the public code route without a Bearer token', () async {
      String? path;
      String? auth;
      final client = MockClient((request) async {
        path = request.url.path;
        auth = request.headers['Authorization'];
        return http.Response(
          jsonEncode({
            'kind': 'invite',
            'inviterName': 'Björn',
            'inviteeName': 'Alice',
          }),
          200,
        );
      });

      final result = await build(client).lookupCode('AB12');

      expect(path, '/v1/realunit/referral/code/AB12');
      expect(auth, isNull);
      expect(result.isInvite, isTrue);
      expect(result.inviterName, 'Björn');
    });

    test('keeps a slash in the code as one path segment', () async {
      List<String>? segments;
      final client = MockClient((request) async {
        segments = request.url.pathSegments;
        return http.Response(
          jsonEncode({'kind': 'invite', 'inviterName': 'Björn'}),
          200,
        );
      });

      await build(client).lookupCode('AB/12');
      expect(segments, ['v1', 'realunit', 'referral', 'code', 'AB/12']);
    });

    test('percent-decodes the lookup path segment', () async {
      List<String>? segments;
      final client = MockClient((request) async {
        segments = request.url.pathSegments;
        return http.Response(
          jsonEncode({'kind': 'invite', 'inviterName': 'Björn'}),
          200,
        );
      });

      await build(client).lookupCode('AB%2F12');
      expect(segments, ['v1', 'realunit', 'referral', 'code', 'AB/12']);
    });

    test('extracts the code from an invite URL before lookup', () async {
      List<String>? segments;
      final client = MockClient((request) async {
        segments = request.url.pathSegments;
        return http.Response(
          jsonEncode({'kind': 'invite', 'inviterName': 'Björn'}),
          200,
        );
      });

      await build(client).lookupCode('https://realunit.app/invite/AB12');
      expect(segments, ['v1', 'realunit', 'referral', 'code', 'AB12']);
    });

    test('rejects an empty code without calling the network', () async {
      var called = false;
      final client = MockClient((request) async {
        called = true;
        return http.Response('{}', 200);
      });

      await expectLater(
        build(client).lookupCode('   '),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 400)
              .having((e) => e.code, 'code', 'INVALID'),
        ),
      );
      await expectLater(
        build(client).lookupCode('%20'),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 400)),
      );
      expect(called, isFalse);
    });

    test('aborts a stalled public lookup', () async {
      final client = MockClient((request) async {
        await Future<void>.delayed(const Duration(seconds: 30));
        return http.Response('{}', 200);
      });

      await expectLater(
        build(client).lookupCode(
          'AB12',
          timeout: const Duration(milliseconds: 20),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('throws ApiException on a non-200 response', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({'statusCode': 404, 'code': 'NOT_FOUND', 'message': 'gone'}),
          404,
        ),
      );

      expect(() => build(client).lookupCode('AB12'), throwsA(isA<ApiException>()));
    });
  });

  group('$RealUnitReferralService.bind', () {
    test('POSTs the code and returns promo campaign text 1:1', () async {
      Map<String, dynamic>? body;
      final client = MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'kind': 'Promo',
            'campaignText': 'Mit dem Code XY schenken wir dir 20 Token.',
            'minBuyRealu': 200,
            'redemptionCap': 50,
          }),
          200,
        );
      });

      final result = await build(client).bind(code: 'XY');

      expect(body, {'code': 'XY'});
      expect(result.isPromo, isTrue);
      expect(result.minBuyRealu, 200);
      expect(result.redemptionCap, 50);
      expect(
        result.campaignText,
        'Mit dem Code XY schenken wir dir 20 Token.',
      );
    });

    test('unwraps a {data: ...} bind payload with inviterName', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'data': {
              'kind': 'Invite',
              'inviterName': 'Björn',
              'actionText': 'Hey Alice, Björn lädt dich ein',
            },
          }),
          200,
        ),
      );

      final result = await build(client).bind(code: 'AB12CD');
      expect(result.isInvite, isTrue);
      expect(result.inviterName, 'Björn');
      expect(result.displayInviterName, 'Björn');
      expect(result.actionText, 'Hey Alice, Björn lädt dich ein');
    });

    test('rejects an empty code without calling the network', () async {
      var called = false;
      final client = MockClient((request) async {
        called = true;
        return http.Response('{}', 200);
      });

      await expectLater(
        build(client).bind(code: '  '),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 400)
              .having((e) => e.message, 'message', 'empty'),
        ),
      );
      expect(called, isFalse);
    });

    test('percent-decodes the bind code', () async {
      Map<String, dynamic>? body;
      final client = MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'kind': 'Invite'}),
          200,
        );
      });

      await build(client).bind(code: 'AB%2F12');
      expect(body, {'code': 'AB/12'});
    });

    test('extracts the code from an invite URL before bind', () async {
      Map<String, dynamic>? body;
      final client = MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'kind': 'Invite'}),
          200,
        );
      });

      await build(client).bind(code: 'https://realunit.app/invite/AB12CD');
      expect(body, {'code': 'AB12CD'});
    });

    test('aborts a stalled bind', () async {
      final client = MockClient((request) async {
        await Future<void>.delayed(const Duration(seconds: 30));
        return http.Response('{}', 200);
      });

      await expectLater(
        build(client).bind(
          code: 'XY',
          timeout: const Duration(milliseconds: 20),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('throws ApiException on a non-200/201 response', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({'statusCode': 409, 'code': 'CONFLICT', 'message': 'used'}),
          409,
        ),
      );

      expect(() => build(client).bind(code: 'XY'), throwsA(isA<ApiException>()));
    });
  });

  group('$RealUnitReferralService.acceptTerms', () {
    test('POSTs accepted:true and accepts 200 or 201', () async {
      Map<String, dynamic>? body;
      final client = MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(request.url.path, '/v1/realunit/referral/terms/accept');
        expect(request.headers['Authorization'], 'Bearer jwt-1');
        return http.Response('{}', 201);
      });

      await build(client).acceptTerms();
      expect(body, {'accepted': true});
    });

    test('throws ApiException on a non-200/201 response', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({'statusCode': 403, 'code': 'FORBIDDEN', 'message': 'no'}),
          403,
        ),
      );

      expect(() => build(client).acceptTerms(), throwsA(isA<ApiException>()));
    });
  });

  group('$RealUnitReferralService.getInvites', () {
    test('GETs /v1/realunit/referral/invites and parses open rows', () async {
      String? path;
      final client = MockClient((request) async {
        path = request.url.path;
        return http.Response(
          jsonEncode([
            {
              'id': 1,
              'code': 'AB12',
              'url': 'https://realunit.app/invite/AB12',
              'guestName': 'Alice',
              'copyText':
                  'Hey Alice, Björn lädt dich ein zu RealUnit: https://realunit.app/invite/AB12',
              'copyTextEn':
                  'Hey Alice, Björn is inviting you to RealUnit: https://realunit.app/invite/AB12',
              'inviterName': 'Björn',
              'status': 'Open',
              'created': '2026-08-24T10:00:00Z',
            },
          ]),
          200,
        );
      });

      final invites = await build(client).getInvites();
      expect(path, '/v1/realunit/referral/invites');
      expect(invites, hasLength(1));
      expect(invites.single.isOpen, isTrue);
      expect(invites.single.guestName, 'Alice');
      expect(invites.single.inviterName, 'Björn');
      expect(
        invites.single.copyTextForLocale('en'),
        'Hey Alice, Björn is inviting you to RealUnit: https://realunit.app/invite/AB12',
      );
    });

    test('folds Bound and Review to Open (TB Ziff. 7)', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode([
            {
              'id': 1,
              'code': 'AB12',
              'url': 'https://realunit.app/invite/AB12',
              'guestName': 'Alice',
              'status': 'Bound',
              'created': '2026-08-24T10:00:00Z',
            },
            {
              'id': 2,
              'code': 'CD34',
              'url': 'https://realunit.app/invite/CD34',
              'guestName': 'Bob',
              'status': 'Review',
              'created': '2026-08-24T10:00:00Z',
            },
          ]),
          200,
        ),
      );

      final invites = await build(client).getInvites();
      expect(invites.map((i) => i.status), ['Open', 'Open']);
      expect(invites.every((i) => i.isOpen), isTrue);
    });

    test('unwraps an {invites: [...]} payload', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'invites': [
              {
                'id': 1,
                'code': 'AB12',
                'url': 'https://realunit.app/invite/AB12',
                'guestName': 'Alice',
                'status': 'Open',
                'created': '2026-08-24T10:00:00Z',
              },
            ],
          }),
          200,
        ),
      );

      final invites = await build(client).getInvites();
      expect(invites, hasLength(1));
      expect(invites.single.guestName, 'Alice');
    });

    test('skips a malformed invite row and keeps the valid open invite', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode([
            {'id': 1, 'guestName': 'nope'},
            {
              'id': 2,
              'code': 'AB12',
              'url': 'https://realunit.app/invite/AB12',
              'guestName': 'Alice',
              'status': 'Open',
              'created': 1787565600,
            },
          ]),
          200,
        ),
      );

      final invites = await build(client).getInvites();
      expect(invites, hasLength(1));
      expect(invites.single.guestName, 'Alice');
      expect(invites.single.created, DateTime.utc(2026, 8, 24, 10));
    });

    test('throws ApiException on a non-200 response', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({'statusCode': 500, 'code': 'SERVER_ERROR', 'message': 'boom'}),
          500,
        ),
      );

      expect(() => build(client).getInvites(), throwsA(isA<ApiException>()));
    });
  });

  group('$RealUnitReferralService.getPayouts', () {
    test('GETs /v1/realunit/referral/payouts and keeps chfValue frozen', () async {
      String? path;
      final client = MockClient((request) async {
        path = request.url.path;
        return http.Response(
          jsonEncode([
            {
              'id': 1,
              'amount': 20,
              'chfValue': 246.5,
              'created': '2026-08-24T10:00:00Z',
              'kind': 'Invite',
              'status': 'Complete',
            },
          ]),
          200,
        );
      });

      final payouts = await build(client).getPayouts();
      expect(path, '/v1/realunit/referral/payouts');
      expect(payouts, hasLength(1));
      expect(payouts.single.chfValue, 246.5);
      expect(payouts.single.amount, 20);
    });

    test('unwraps a {payouts: [...]} payload', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'payouts': [
              {
                'id': 1,
                'amount': 20,
                'chfValue': 246.5,
                'created': '2026-08-24T10:00:00Z',
                'status': 'Complete',
              },
            ],
          }),
          200,
        ),
      );

      final payouts = await build(client).getPayouts();
      expect(payouts, hasLength(1));
      expect(payouts.single.chfValue, 246.5);
    });

    test('keeps a settled prize when frozen CHF is null', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode([
            {
              'id': 1,
              'amount': 20,
              'chfValue': null,
              'created': '2026-08-24T10:00:00Z',
              'status': 'Settled',
            },
          ]),
          200,
        ),
      );

      final payouts = await build(client).getPayouts();
      expect(payouts, hasLength(1));
      expect(payouts.single.amount, 20);
      expect(payouts.single.chfValue, 0);
    });

    test('skips a malformed payout row and keeps the valid prize', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode([
            {'id': 1, 'created': '2026-08-24T10:00:00Z'},
            {
              'id': 2,
              'amount': '20',
              'chfValue': '246.5',
              'created': '2026-08-24T10:00:00Z',
              'status': 'Complete',
            },
          ]),
          200,
        ),
      );

      final payouts = await build(client).getPayouts();
      expect(payouts, hasLength(1));
      expect(payouts.single.id, 2);
      expect(payouts.single.amount, 20);
    });

    test('drops Pending rows so history cannot show an unconfirmed prize', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode([
            {
              'id': 1,
              'amount': 20,
              'chfValue': 1,
              'created': '2026-08-24T10:00:00Z',
              'status': 'Pending',
            },
            {
              'id': 2,
              'amount': 20,
              'chfValue': 246.5,
              'created': '2026-08-24T10:00:00Z',
              'status': 'Settled',
            },
          ]),
          200,
        ),
      );

      final payouts = await build(client).getPayouts();
      expect(payouts, hasLength(1));
      expect(payouts.single.id, 2);
      expect(payouts.single.status, 'Settled');
    });

    test('throws ApiException on a non-200 response', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({'statusCode': 500, 'code': 'SERVER_ERROR', 'message': 'boom'}),
          500,
        ),
      );

      expect(() => build(client).getPayouts(), throwsA(isA<ApiException>()));
    });
  });

  group('$RealUnitReferralService.getTerms', () {
    test('GETs /v1/realunit/referral/terms and parses markdown 1:1', () async {
      String? path;
      final client = MockClient((request) async {
        path = request.url.path;
        return http.Response(
          jsonEncode({
            'version': '2026-08-14',
            'markdown': '# TB',
            'markdownEn': '# Terms',
          }),
          200,
        );
      });

      final terms = await build(client).getTerms();
      expect(path, '/v1/realunit/referral/terms');
      expect(terms.textForLang('de'), '# TB');
      expect(terms.textForLang('en'), '# Terms');
    });

    test('aborts a stalled terms fetch so the bundled TB can load', () async {
      final client = MockClient((request) async {
        await Future<void>.delayed(const Duration(seconds: 30));
        return http.Response('{}', 200);
      });

      await expectLater(
        build(client).getTerms(timeout: const Duration(milliseconds: 20)),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('throws ApiException on a non-200 response', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({'statusCode': 500, 'code': 'SERVER_ERROR', 'message': 'boom'}),
          500,
        ),
      );

      expect(() => build(client).getTerms(), throwsA(isA<ApiException>()));
    });
  });
}
