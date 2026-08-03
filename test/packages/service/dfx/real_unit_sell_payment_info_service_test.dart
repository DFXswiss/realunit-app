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
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/dto/broadcast_transaction_request_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/dto/eip7702/eip7702_data_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/dto/real_unit_sell_payment_info_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/sell_payment_info.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_sell_payment_info_service.dart';
import 'package:realunit_wallet/packages/service/session_cache.dart';
import 'package:realunit_wallet/packages/service/wallet_service.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';
import 'package:realunit_wallet/packages/wallet/wallet_account.dart';
import 'package:realunit_wallet/styles/currency.dart';
import 'package:web3dart/web3dart.dart';

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

Map<String, dynamic> _sellPaymentInfoJson() => {
      'id': 7,
      'routeId': 9,
      'timestamp': '2026-05-15T10:00:00Z',
      'eip7702': _eip7702Json(),
      'depositAddress': '0xdeposit',
      'amount': 100.0,
      'tokenAddress': '0xtoken',
      'chainId': 1,
      'fees': {
        'rate': 0.01,
        'fixed': 0.5,
        'network': 0,
        'min': 1,
        'dfx': 0.25,
        'total': 1.76,
      },
      'minVolume': 5.0,
      'maxVolume': 5000.0,
      'minVolumeTarget': 5.1,
      'maxVolumeTarget': 5100.0,
      'exchangeRate': 1.1,
      'rate': 1.05,
      'priceSteps': <Map<String, dynamic>>[],
      'estimatedAmount': 95.5,
      'currency': 'CHF',
      'beneficiary': {'name': 'Alice', 'iban': 'CH...'},
      'ethBalance': 0.1,
      'requiredGasEth': 0.001,
      'isValid': true,
    };

Map<String, dynamic> _eip7702Json() => {
      'relayerAddress': '0xrelay',
      'delegationManagerAddress': '0xmgr',
      'delegatorAddress': '0xdr',
      'userNonce': 7,
      'domain': {
        'name': 'RealUnit',
        'version': '1',
        'chainId': 1,
        'verifyingContract': '0xverify',
      },
      'types': {
        'Delegation': <Map<String, dynamic>>[],
        'Caveat': <Map<String, dynamic>>[],
      },
      'message': {
        'delegate': '0xd',
        'delegator': '0xdr',
        'authority': '0xauth',
        'caveats': <Map<String, dynamic>>[],
        'salt': 0,
      },
      'tokenAddress': '0xtoken',
      'amountWei': '12345',
      'depositAddress': '0xdeposit',
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
    session.setAuthToken(
      'jwt-1',
      EthereumAddress.fromHex('0x0000000000000000000000000000000000000001').hexEip55,
    );

    when(() => appStore.apiConfig)
        .thenReturn(const ApiConfig(networkMode: NetworkMode.mainnet));
    when(() => appStore.sessionCache).thenReturn(session);
    when(() => appStore.wallet).thenReturn(wallet);
    when(() => wallet.currentAccount).thenReturn(account);
    when(() => account.primaryAddress).thenReturn(_StubCreds());
    when(() => walletService.ensureCurrentWalletUnlocked()).thenAnswer((_) async {});
    when(() => walletService.lockCurrentWallet()).thenAnswer((_) async {});
  });

  RealUnitSellPaymentInfoService build(http.Client client) {
    when(() => appStore.httpClient).thenReturn(client);
    return RealUnitSellPaymentInfoService(appStore, walletService);
  }

  group('getPaymentInfo', () {
    test('happy path: 200 → parsed SellPaymentInfo', () async {
      Uri? sentUri;
      String? sentBody;
      final client = MockClient((request) async {
        sentUri = request.url;
        sentBody = request.body;
        return http.Response(jsonEncode(_sellPaymentInfoJson()), 200);
      });

      final info = await build(client).getPaymentInfo(100, 'CH...', currency: Currency.eur);

      expect(sentUri!.path, '/v1/realunit/sell');
      // PUT body must carry amount + iban + currency code.
      final body = jsonDecode(sentBody!) as Map<String, dynamic>;
      expect(body['amount'], 100);
      expect(body['iban'], 'CH...');
      expect(body['currency'], 'EUR');

      expect(info.id, 7);
      expect(info.amount, 100);
      expect(info.currency, Currency.chf); // response.currency wins
      expect(info.beneficiary.iban, 'CH...');
      expect(info.depositAddress, '0xdeposit');
    });

    test('403 → ApiException', () async {
      final client = MockClient((_) async => http.Response(
            jsonEncode({'statusCode': 403, 'code': 'X', 'message': 'no'}),
            403,
          ));

      expect(
        () => build(client).getPaymentInfo(100, 'CH...'),
        throwsA(isA<ApiException>()),
      );
    });

    test('500 → ApiException', () async {
      final client = MockClient((_) async => http.Response(
            jsonEncode({'statusCode': 500, 'code': 'X', 'message': 'boom'}),
            500,
          ));

      expect(
        () => build(client).getPaymentInfo(100, 'CH...'),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('createUnsignedTransactions', () {
    test('200 → parsed swap + deposit', () async {
      Uri? sentUri;
      final client = MockClient((request) async {
        sentUri = request.url;
        return http.Response(
          jsonEncode({'swap': '0xswap', 'deposit': '0xdeposit'}),
          200,
        );
      });

      final dto = await build(client).createUnsignedTransactions(42);

      expect(sentUri!.path, '/v1/realunit/sell/42/unsigned-transactions');
      expect(dto.swap, '0xswap');
      expect(dto.deposit, '0xdeposit');
    });

    test('500 → ApiException', () async {
      final client = MockClient((_) async => http.Response(
            jsonEncode({'statusCode': 500, 'code': 'X', 'message': 'boom'}),
            500,
          ));

      expect(
        () => build(client).createUnsignedTransactions(42),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('broadcastTransaction', () {
    test('201 → returns txHash', () async {
      Uri? sentUri;
      String? sentBody;
      final client = MockClient((request) async {
        sentUri = request.url;
        sentBody = request.body;
        return http.Response(jsonEncode({'txHash': '0xabc'}), 201);
      });

      final txHash = await build(client).broadcastTransaction(
        42,
        const BroadcastTransactionRequestDto(
          unsignedTx: '0xtx',
          r: '0xr',
          s: '0xs',
          v: 27,
        ),
      );

      expect(sentUri!.path, '/v1/realunit/sell/42/broadcast');
      final body = jsonDecode(sentBody!) as Map<String, dynamic>;
      expect(body['unsignedTx'], '0xtx');
      expect(body['v'], 27);
      expect(txHash, '0xabc');
    });

    test('500 → ApiException', () async {
      final client = MockClient((_) async => http.Response(
            jsonEncode({'statusCode': 500, 'code': 'X', 'message': 'boom'}),
            500,
          ));

      expect(
        () => build(client).broadcastTransaction(
          42,
          const BroadcastTransactionRequestDto(
            unsignedTx: '0xtx',
            r: '0xr',
            s: '0xs',
            v: 27,
          ),
        ),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('confirmPaymentWithTxHash', () {
    test('PUTs /confirm with only the txHash payload', () async {
      Uri? sentUri;
      Map<String, dynamic>? body;
      final client = MockClient((request) async {
        sentUri = request.url;
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('{}', 200);
      });

      final info = SellPaymentInfo(
        id: 42,
        eip7702: Eip7702Data.fromJson(_eip7702Json()),
        amount: 100,
        exchangeRate: 1.0,
        rate: 1.0,
        beneficiary: const BeneficiaryDto(iban: 'CH...'),
        estimatedAmount: 100.0,
        currency: Currency.chf,
        depositAddress: '0xdeposit',
        tokenAddress: '0xtoken',
        chainId: 1,
        ethBalance: 0.1,
        requiredGasEth: 0.001,
      );

      await build(client).confirmPaymentWithTxHash(info, '0xabc');

      expect(sentUri!.path, '/v1/realunit/sell/42/confirm');
      expect(body!['txHash'], '0xabc');
      // No eip7702 envelope on the txHash branch.
      expect(body!.containsKey('eip7702'), isFalse);
    });
  });

  group('malformed JSON responses', () {
    test('getPaymentInfo with non-JSON 200 throws FormatException', () {
      final client = MockClient((_) async => http.Response('not json', 200));
      expect(
        () => build(client).getPaymentInfo(100, 'CH...'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
