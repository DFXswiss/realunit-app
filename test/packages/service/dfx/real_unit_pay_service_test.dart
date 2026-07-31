import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:web3dart/web3dart.dart';
import 'package:realunit_wallet/packages/config/api_config.dart';
import 'package:realunit_wallet/packages/config/network_mode.dart';
import 'package:realunit_wallet/packages/repository/cache_repository.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/pay/dto/real_unit_ocp_pay_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/pay/dto/real_unit_ocp_pay_status_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/pay/dto/real_unit_ocp_pay_submit_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/pay/dto/real_unit_swap_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/dto/broadcast_transaction_request_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_pay_service.dart';
import 'package:realunit_wallet/packages/service/session_cache.dart';
import 'package:realunit_wallet/packages/service/wallet_service.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';
import 'package:realunit_wallet/packages/wallet/wallet_account.dart';

class _MockAppStore extends Mock implements AppStore {}

class _MockWallet extends Mock implements AWallet {}

class _MockAccount extends Mock implements AWalletAccount {}

class _MockCacheRepository extends Mock implements CacheRepository {}

class _MockWalletService extends Mock implements WalletService {}

class _StubCreds extends Fake implements CredentialsWithKnownAddress {
  @override
  EthereumAddress get address =>
      EthereumAddress.fromHex('0x0000000000000000000000000000000000000001');
}

Map<String, dynamic> _swapInfoJson() => {
  'id': 99,
  'uid': 'MOCK-UID',
  'routeId': 7,
  'timestamp': '2026-06-03T00:00:00.000Z',
  'amount': 10,
  'estimatedAmount': 960,
  'targetAsset': 'ZCHF',
  'fees': {'dfx': 1, 'network': 0.5, 'total': 1.5},
  'minVolume': 1,
  'maxVolume': 1000,
  'minVolumeTarget': 95,
  'maxVolumeTarget': 95000,
  'ethBalance': 1.0,
  'requiredGasEth': 0.001,
  'isValid': true,
};

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

    when(() => appStore.apiConfig).thenReturn(const ApiConfig(networkMode: NetworkMode.mainnet));
    when(() => appStore.sessionCache).thenReturn(session);
    when(() => appStore.wallet).thenReturn(wallet);
    when(() => wallet.currentAccount).thenReturn(account);
    when(() => account.primaryAddress).thenReturn(_StubCreds());
  });

  RealUnitPayService build(http.Client client) {
    when(() => appStore.httpClient).thenReturn(client);
    return RealUnitPayService(appStore, walletService);
  }

  group('getPaymentDetails', () {
    test('GETs the public lnurlp endpoint (no auth header) and parses it', () async {
      Uri? sentUri;
      Map<String, String>? headers;
      final client = MockClient((request) async {
        sentUri = request.url;
        headers = request.headers;
        return http.Response(
          jsonEncode({
            'requestedAmount': {'asset': 'CHF', 'amount': 42.5},
            'quote': {'id': 'quote_xyz', 'expiration': '2026-06-03T12:00:00.000Z'},
            'transferAmounts': [
              {
                'method': 'Ethereum',
                'assets': [
                  {'asset': 'ZCHF', 'amount': 42.7},
                ],
              },
            ],
          }),
          200,
        );
      });

      final dto = await build(client).getPaymentDetails('pl_abc');

      expect(sentUri!.path, '/v1/lnurlp/pl_abc');
      expect(headers!.containsKey('Authorization'), isFalse);
      expect(dto.quote.id, 'quote_xyz');
      expect(dto.transferAmounts.first.assets.first.amount, 42.7);
    });

    test('non-200 → ApiException', () async {
      final client = MockClient(
        (_) async => http.Response(jsonEncode({'statusCode': 404, 'message': 'gone'}), 404),
      );
      expect(
        () => build(client).getPaymentDetails('pl_abc'),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('getSwapPaymentInfo', () {
    test('PUTs /swap with targetAmount and parses the quote', () async {
      Uri? sentUri;
      Map<String, dynamic>? body;
      final client = MockClient((request) async {
        sentUri = request.url;
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode(_swapInfoJson()), 200);
      });

      final info = await build(
        client,
      ).getSwapPaymentInfo(const RealUnitSwapDto.fromTargetAmount(95.5));

      expect(sentUri!.path, '/v1/realunit/swap');
      expect(body!['targetAmount'], 95.5);
      expect(body!.containsKey('amount'), isFalse);
      expect(info.id, 99);
      expect(info.estimatedAmount, 960);
      expect(info.isValid, isTrue);
    });

    test('non-200 → ApiException', () async {
      final client = MockClient(
        (_) async => http.Response(jsonEncode({'statusCode': 400, 'message': 'bad'}), 400),
      );
      expect(
        () => build(client).getSwapPaymentInfo(const RealUnitSwapDto.fromTargetAmount(95.5)),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('createSwapUnsignedTransaction', () {
    test('200 → parses swap hex', () async {
      Uri? sentUri;
      final client = MockClient((request) async {
        sentUri = request.url;
        return http.Response(jsonEncode({'swap': '0xswap'}), 200);
      });

      final dto = await build(client).createSwapUnsignedTransaction(42);

      expect(sentUri!.path, '/v1/realunit/swap/42/unsigned-transaction');
      expect(dto.swap, '0xswap');
    });

    test('non-200 → ApiException', () async {
      final client = MockClient(
        (_) async => http.Response(jsonEncode({'statusCode': 400, 'message': 'no eth'}), 400),
      );
      expect(
        () => build(client).createSwapUnsignedTransaction(42),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('broadcastSwapTransaction', () {
    test('201 → returns txHash', () async {
      Uri? sentUri;
      Map<String, dynamic>? body;
      final client = MockClient((request) async {
        sentUri = request.url;
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'txHash': '0xabc'}), 201);
      });

      final txHash = await build(client).broadcastSwapTransaction(
        42,
        const BroadcastTransactionRequestDto(unsignedTx: '0xtx', r: '0xr', s: '0xs', v: 27),
      );

      expect(sentUri!.path, '/v1/realunit/swap/42/broadcast');
      expect(body!['unsignedTx'], '0xtx');
      expect(body!['v'], 27);
      expect(txHash, '0xabc');
    });

    test('non-200 → ApiException', () async {
      final client = MockClient(
        (_) async => http.Response(jsonEncode({'statusCode': 400, 'message': 'bad sig'}), 400),
      );
      expect(
        () => build(client).broadcastSwapTransaction(
          42,
          const BroadcastTransactionRequestDto(unsignedTx: '0xtx', r: '0xr', s: '0xs', v: 27),
        ),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('createPayUnsignedTransaction', () {
    // Values from the real Sepolia OCP testnet run (DFXswiss/api #3819):
    // a CHF 2.00 link settling 2.0 ZCHF (2000000000000000000 wei) to the DFX
    // deposit recipient on chain 11155111.
    test('PUTs /pay/unsigned-transaction with the payment refs', () async {
      Uri? sentUri;
      Map<String, dynamic>? body;
      final client = MockClient((request) async {
        sentUri = request.url;
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'unsignedTx':
                '0x02f87483aa36a782019b8502284a84ae8502284a84ae830186a094d3117681ca462268048f57d106d312ba0b1215ea80b844a9059cbb000000000000000000000000fb2a9731cda8b3fca015723ef40f310c1e48366b0000000000000000000000000000000000000000000000001bc16d674ec80000c0',
            'tokenAddress': '0xD3117681cA462268048f57D106d312Ba0b1215eA',
            'recipient': '0xfB2a9731cdA8b3FCa015723EF40f310C1E48366b',
            'amountWei': '2000000000000000000',
            'chainId': 11155111,
          }),
          200,
        );
      });

      final dto = await build(client).createPayUnsignedTransaction(
        const RealUnitOcpPayDto(paymentLinkId: 'pl_realunit_ocp_sepolia', quoteId: 'q1'),
      );

      expect(sentUri!.path, '/v1/realunit/pay/unsigned-transaction');
      expect(body!['paymentLinkId'], 'pl_realunit_ocp_sepolia');
      expect(body!['quoteId'], 'q1');
      expect(dto.recipient, '0xfB2a9731cdA8b3FCa015723EF40f310C1E48366b');
      expect(dto.tokenAddress, '0xD3117681cA462268048f57D106d312Ba0b1215eA');
      expect(dto.amountWei, '2000000000000000000');
      expect(dto.chainId, 11155111);
    });

    test('non-200 → ApiException', () async {
      final client = MockClient(
        (_) async =>
            http.Response(jsonEncode({'statusCode': 400, 'message': 'unsupported method'}), 400),
      );
      expect(
        () => build(client).createPayUnsignedTransaction(
          const RealUnitOcpPayDto(paymentLinkId: 'pl_abc', quoteId: 'q1'),
        ),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('submitPay', () {
    test('PUTs /pay/submit and returns txId', () async {
      Uri? sentUri;
      Map<String, dynamic>? body;
      final client = MockClient((request) async {
        sentUri = request.url;
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'txId': '0xTxId'}), 200);
      });

      final txId = await build(client).submitPay(
        const RealUnitOcpPaySubmitDto(
          unsignedTx: '0xtx',
          r: '0xr',
          s: '0xs',
          v: 27,
          paymentLinkId: 'pl_abc',
          quoteId: 'q1',
        ),
      );

      expect(sentUri!.path, '/v1/realunit/pay/submit');
      expect(body!['paymentLinkId'], 'pl_abc');
      expect(txId, '0xTxId');
    });

    test('non-200 → ApiException', () async {
      final client = MockClient(
        (_) async => http.Response(jsonEncode({'statusCode': 400, 'message': 'fail'}), 400),
      );
      expect(
        () => build(client).submitPay(
          const RealUnitOcpPaySubmitDto(
            unsignedTx: '0xtx',
            r: '0xr',
            s: '0xs',
            v: 27,
            paymentLinkId: 'pl_abc',
            quoteId: 'q1',
          ),
        ),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('getPayStatus', () {
    test('GETs /pay/:id/status and parses the status', () async {
      Uri? sentUri;
      final client = MockClient((request) async {
        sentUri = request.url;
        return http.Response(jsonEncode({'status': 'Completed'}), 200);
      });

      final dto = await build(client).getPayStatus('pl_abc');

      expect(sentUri!.path, '/v1/realunit/pay/pl_abc/status');
      expect(dto.status, OcpPaymentStatus.completed);
    });

    test('non-200 → ApiException', () async {
      final client = MockClient(
        (_) async => http.Response(jsonEncode({'statusCode': 404, 'message': 'none'}), 404),
      );
      expect(
        () => build(client).getPayStatus('pl_abc'),
        throwsA(isA<ApiException>()),
      );
    });
  });
}
