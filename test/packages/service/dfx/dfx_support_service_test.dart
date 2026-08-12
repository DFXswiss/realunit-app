import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/config/api_config.dart';
import 'package:realunit_wallet/packages/config/network_mode.dart';
import 'package:realunit_wallet/packages/repository/cache_repository.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_support_service.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/models/support/support_issue_reason.dart';
import 'package:realunit_wallet/packages/service/dfx/models/support/support_issue_type.dart';
import 'package:realunit_wallet/packages/service/session_cache.dart';
import 'package:realunit_wallet/packages/service/wallet_service.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';

class _MockAppStore extends Mock implements AppStore {}

class _MockCacheRepository extends Mock implements CacheRepository {}

class _MockWalletService extends Mock implements WalletService {}

const _authMnemonic = 'test test test test test test test test test test test junk';

Map<String, dynamic> _ticketJson({String uid = 'uid-1'}) => {
      'uid': uid,
      'state': 'Created',
      'type': 'GenericIssue',
      'reason': 'Other',
      'name': 'Test ticket',
      'created': '2026-01-01T00:00:00Z',
      'messages': <Map<String, dynamic>>[],
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
    // Pre-populate the auth token so the base-class getAuthToken short-
    // circuits without exercising the signing flow.
    sessionCache.setAuthToken(
      'jwt-xyz',
      authWallet.currentAccount.primaryAddress.address.hexEip55,
    );
    when(() => appStore.sessionCache).thenReturn(sessionCache);
    when(() => appStore.apiConfig)
        .thenReturn(const ApiConfig(networkMode: NetworkMode.mainnet));
    when(() => appStore.wallet).thenReturn(authWallet);
    when(() => walletService.ensureCurrentWalletUnlocked()).thenAnswer((_) async {});
    when(() => walletService.lockCurrentWallet()).thenAnswer((_) async {});
  });

  DfxSupportService build(http.Client client) {
    when(() => appStore.httpClient).thenReturn(client);
    return DfxSupportService(appStore, walletService);
  }

  group('$DfxSupportService', () {
    test('getTickets GETs /v1/support/issue with the Bearer JWT', () async {
      String? path;
      String? method;
      String? auth;
      final client = MockClient((request) async {
        path = request.url.path;
        method = request.method;
        auth = request.headers['Authorization'];
        return http.Response(jsonEncode([_ticketJson(uid: 'a'), _ticketJson(uid: 'b')]), 200);
      });

      final list = await build(client).getTickets();

      expect(list.map((t) => t.uid), ['a', 'b']);
      expect(method, 'GET');
      expect(path, '/v1/support/issue');
      expect(auth, 'Bearer jwt-xyz');
    });

    test('getTickets throws ApiException on non-200', () async {
      final client = MockClient((_) async => http.Response(
            jsonEncode({'statusCode': 500, 'message': 'oops'}),
            500,
          ));

      expect(() => build(client).getTickets(), throwsA(isA<ApiException>()));
    });

    test('getTicket GETs /v1/support/issue/<uid> and returns the mapped DTO', () async {
      String? path;
      final client = MockClient((request) async {
        path = request.url.path;
        return http.Response(jsonEncode(_ticketJson(uid: 'abc')), 200);
      });

      final ticket = await build(client).getTicket('abc');

      expect(ticket.uid, 'abc');
      expect(path, '/v1/support/issue/abc');
    });

    test('getTicket throws ApiException on non-200', () async {
      final client = MockClient((_) async => http.Response(
            jsonEncode({'statusCode': 404, 'message': 'not found'}),
            404,
          ));

      expect(
        () => build(client).getTicket('missing'),
        throwsA(isA<ApiException>()),
      );
    });

    test('createTicket POSTs the type+reason+name and includes message when present', () async {
      Map<String, dynamic>? body;
      String? method;
      final client = MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        method = request.method;
        return http.Response(jsonEncode(_ticketJson(uid: 'created')), 201);
      });

      final ticket = await build(client).createTicket(
        type: SupportIssueType.bugReport,
        reason: SupportIssueReason.other,
        name: 'Bug Report',
        message: 'crash on launch',
      );

      expect(ticket.uid, 'created');
      expect(method, 'POST');
      expect(body!['type'], 'BugReport');
      expect(body!['reason'], 'Other');
      expect(body!['name'], 'Bug Report');
      expect(body!['message'], 'crash on launch');
    });

    test('createTicket omits the message field when null', () async {
      Map<String, dynamic>? body;
      final client = MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode(_ticketJson(uid: 'c')), 201);
      });

      await build(client).createTicket(
        type: SupportIssueType.genericIssue,
        reason: SupportIssueReason.other,
        name: 'General Issue',
      );

      expect(body!.containsKey('message'), isFalse);
    });

    test('createTicket with attachment includes file and fileName in the body', () async {
      Map<String, dynamic>? body;
      final client = MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode(_ticketJson(uid: 'with-file')), 201);
      });

      await build(client).createTicket(
        type: SupportIssueType.bugReport,
        reason: SupportIssueReason.other,
        name: 'Bug Report',
        message: 'see screenshot',
        file: 'data:image/jpeg;base64,abc123',
        fileName: 'shot.jpg',
      );

      expect(body!['file'], 'data:image/jpeg;base64,abc123');
      expect(body!['fileName'], 'shot.jpg');
      expect(body!['message'], 'see screenshot');
    });

    test('createTicket without attachment omits file and fileName entirely', () async {
      Map<String, dynamic>? body;
      final client = MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode(_ticketJson(uid: 'no-file')), 201);
      });

      await build(client).createTicket(
        type: SupportIssueType.genericIssue,
        reason: SupportIssueReason.other,
        name: 'General Issue',
        message: 'text only',
      );

      expect(body!.containsKey('file'), isFalse);
      expect(body!.containsKey('fileName'), isFalse);
      expect(body!['message'], 'text only');
    });

    test('createTicket throws ApiException on non-201 (even on 200)', () async {
      final client = MockClient((_) async => http.Response(
            jsonEncode({'statusCode': 200, 'message': 'wrong code'}),
            200,
          ));

      expect(
        () => build(client).createTicket(
          type: SupportIssueType.genericIssue,
          reason: SupportIssueReason.other,
          name: 'x',
        ),
        throwsA(isA<ApiException>()),
      );
    });

    test('sendMessage POSTs to /v1/support/issue/<uid>/message with the body', () async {
      Map<String, dynamic>? body;
      String? path;
      final client = MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        path = request.url.path;
        return http.Response('{}', 201);
      });

      await build(client).sendMessage('uid-1', message: 'hello there');

      expect(path, '/v1/support/issue/uid-1/message');
      expect(body!['message'], 'hello there');
      expect(body!.containsKey('file'), isFalse);
      expect(body!.containsKey('fileName'), isFalse);
    });

    test('sendMessage with attachment and no text sends file+fileName only', () async {
      Map<String, dynamic>? body;
      final client = MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('{}', 201);
      });

      await build(client).sendMessage(
        'uid-1',
        file: 'data:image/png;base64,xyz',
        fileName: 'img.png',
      );

      expect(body!['file'], 'data:image/png;base64,xyz');
      expect(body!['fileName'], 'img.png');
      expect(body!.containsKey('message'), isFalse);
    });

    test('sendMessage throws ApiException on non-201', () async {
      final client = MockClient((_) async => http.Response(
            jsonEncode({'statusCode': 422, 'message': 'too long'}),
            422,
          ));

      expect(
        () => build(client).sendMessage('uid', message: 'm'),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('malformed JSON responses', () {
    test('getTickets with non-JSON 200 throws FormatException', () {
      final client = MockClient((_) async => http.Response('not json', 200));
      expect(
        () => build(client).getTickets(),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
