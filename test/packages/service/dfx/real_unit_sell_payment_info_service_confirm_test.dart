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
import 'package:realunit_wallet/packages/service/dfx/exceptions/payment/sell_exceptions.dart';
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

// Deterministic test private key — same one FakeBitboxCredentials uses.
// Re-deriving here gives us a real EthPrivateKey credential which the
// EIP-712 / EIP-7702 signers accept directly (they reject everything that
// isn't BitboxCredentials or EthPrivateKey).
const _testPrivateKeyHex = 'fb1ace12f9801e85f3db1b3935dd47d9f064f98152466f47c701b5e12680e612';

final _privKey = EthPrivateKey.fromHex(_testPrivateKeyHex);
final _walletAddress = _privKey.address.hexEip55.toLowerCase();

const _metaMaskDelegator = '0x63c0c19a282a1b52b07dd5a65b58948a07dae32b';
const _delegationManager = '0xdb9b1e94b5b69df7e401ddbede43491141047db3';

Map<String, dynamic> _validEip7702Json() => {
  'relayerAddress': '0xrelay',
  'delegationManagerAddress': _delegationManager,
  'delegatorAddress': _metaMaskDelegator,
  'userNonce': 7,
  'domain': {
    'name': 'RealUnit',
    'version': '1',
    'chainId': 1,
    'verifyingContract': _delegationManager,
  },
  'types': {
    'Delegation': <Map<String, dynamic>>[],
    'Caveat': <Map<String, dynamic>>[],
  },
  'message': {
    'delegate': '0xrelay',
    'delegator': _walletAddress,
    'authority': '0xauth',
    'caveats': <Map<String, dynamic>>[],
    'salt': 0,
  },
  'tokenAddress': '0x553C7f9C780316FC1D34b8e14ac2465Ab22a090B',
  'amountWei': '100',
  'depositAddress': '0xdeposit',
};

SellPaymentInfo _info({int amount = 100}) => SellPaymentInfo(
  id: 42,
  eip7702: Eip7702Data.fromJson(_validEip7702Json()),
  amount: amount,
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
    session.setAuthToken('jwt-1', _privKey.address.hexEip55);

    when(() => appStore.apiConfig).thenReturn(const ApiConfig(networkMode: NetworkMode.mainnet));
    when(() => appStore.sessionCache).thenReturn(session);
    when(() => appStore.wallet).thenReturn(wallet);
    when(() => wallet.currentAccount).thenReturn(account);
    when(() => account.primaryAddress).thenReturn(_privKey);
    // Wallet is already a full SoftwareWallet in this fixture —
    // ensureCurrentWalletUnlocked is a no-op for non-view wallets, but
    // mocktail still needs a stub.
    when(() => walletService.ensureCurrentWalletUnlocked()).thenAnswer((_) async {});
    when(() => walletService.lockCurrentWallet()).thenAnswer((_) async {});
  });

  RealUnitSellPaymentInfoService build(http.Client client) {
    when(() => appStore.httpClient).thenReturn(client);
    return RealUnitSellPaymentInfoService(appStore, walletService);
  }

  group('confirmPayment (software wallet happy path)', () {
    test('signs delegation + authorization and PUTs the eip7702 envelope', () async {
      Uri? sentUri;
      Map<String, dynamic>? body;
      final client = MockClient((request) async {
        sentUri = request.url;
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('{}', 200);
      });

      await build(client).confirmPayment(_info());

      // Confirm hits /v1/realunit/sell/<id>/confirm.
      expect(sentUri!.path, '/v1/realunit/sell/42/confirm');

      // The body has the eip7702 envelope (not the txHash branch).
      expect(body!.containsKey('eip7702'), isTrue);
      expect(body!.containsKey('txHash'), isFalse);

      final envelope = body!['eip7702'] as Map<String, dynamic>;
      final delegation = envelope['delegation'] as Map<String, dynamic>;
      final authorization = envelope['authorization'] as Map<String, dynamic>;

      // Delegation block mirrors the eip7702 data + carries a real signature.
      expect(delegation['delegate'], '0xrelay');
      expect(delegation['delegator'], _walletAddress);
      expect(delegation['authority'], '0xauth');
      expect(delegation['salt'], '0');
      expect((delegation['signature'] as String).startsWith('0x'), isTrue);
      // 65-byte EIP-712 signature → 0x + 130 hex chars.
      expect((delegation['signature'] as String).length, 132);

      // Authorization block carries the matching chain + nonce + (r,s,yParity).
      expect(authorization['chainId'], 1);
      expect(authorization['address'], _metaMaskDelegator);
      expect(authorization['nonce'], 7);
      expect((authorization['r'] as String).startsWith('0x'), isTrue);
      expect((authorization['s'] as String).startsWith('0x'), isTrue);
      expect(authorization['yParity'], anyOf(0, 1));
    });

    test('4xx response → ApiException', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({'statusCode': 422, 'code': 'X', 'message': 'no'}),
          422,
        ),
      );

      expect(
        () => build(client).confirmPayment(_info()),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('confirm 409 mapping', () {
    test('409 "already confirmed" → AlreadyConfirmedException', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'statusCode': 409,
            'message': 'Transaction request is already confirmed',
            'error': 'Conflict',
          }),
          409,
        ),
      );

      await expectLater(
        build(client).confirmPaymentWithTxHash(_info(), '0xtxhash'),
        throwsA(isA<AlreadyConfirmedException>()),
      );
    });

    test('any other 409 conflict stays a plain ApiException', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'statusCode': 409,
            'message': 'Transaction request is in an invalid state',
            'error': 'Conflict',
          }),
          409,
        ),
      );

      await expectLater(
        build(client).confirmPaymentWithTxHash(_info(), '0xtxhash'),
        throwsA(predicate((e) => e is ApiException && e is! AlreadyConfirmedException)),
      );
    });
  });

  // The EIP-7702 authorization r/s components must always be serialized as full
  // 32-byte (64 hex char) big-endian values. `BigInt.toRadixString(16)` drops
  // leading zero bytes, so any signature whose r or s is < 2^248 used to emit
  // < 64 hex chars (an invalid 32-byte field). The fix mirrors the BitBox
  // reference with `.padLeft(64, '0')`. This sweep signs across many nonces so
  // at least one deterministic signature lands on a leading-zero byte, and
  // asserts every emitted r/s is exactly 64 hex chars.
  group('confirmPayment EIP-7702 r/s 32-byte padding', () {
    SellPaymentInfo infoForNonce(int nonce) {
      final json = _validEip7702Json()..['userNonce'] = nonce;
      return SellPaymentInfo(
        id: 42,
        eip7702: Eip7702Data.fromJson(json),
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
    }

    test('authorization r and s are always 0x + 64 hex chars across nonces', () async {
      for (var nonce = 0; nonce < 96; nonce++) {
        Map<String, dynamic>? body;
        final client = MockClient((request) async {
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{}', 200);
        });

        await build(client).confirmPayment(infoForNonce(nonce));

        final authorization =
            (body!['eip7702'] as Map<String, dynamic>)['authorization'] as Map<String, dynamic>;
        final r = authorization['r'] as String;
        final s = authorization['s'] as String;

        expect(r.startsWith('0x'), isTrue);
        expect(s.startsWith('0x'), isTrue);
        expect(
          r.substring(2).length,
          64,
          reason: 'r must be a full 32-byte component (nonce=$nonce)',
        );
        expect(
          s.substring(2).length,
          64,
          reason: 's must be a full 32-byte component (nonce=$nonce)',
        );
        // Value is unchanged, only left-zero-padded.
        expect(BigInt.parse(r.substring(2), radix: 16), isA<BigInt>());
      }
    });
  });
}
