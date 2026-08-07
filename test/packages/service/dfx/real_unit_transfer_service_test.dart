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
import 'package:realunit_wallet/packages/service/dfx/exceptions/payment/transfer_exceptions.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/transfer/dto/real_unit_transfer_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/transfer/dto/real_unit_transfer_payment_info_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_transfer_service.dart';
import 'package:realunit_wallet/packages/service/session_cache.dart';
import 'package:realunit_wallet/packages/service/wallet_service.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';
import 'package:realunit_wallet/packages/wallet/wallet_account.dart';

class _MockAppStore extends Mock implements AppStore {}

class _MockWallet extends Mock implements AWallet {}

class _MockAccount extends Mock implements AWalletAccount {}

class _MockCacheRepository extends Mock implements CacheRepository {}

class _MockWalletService extends Mock implements WalletService {}

// Deterministic test private key — a real EthPrivateKey credential the
// EIP-712 / EIP-7702 signers accept directly (they reject anything that isn't
// BitboxCredentials or EthPrivateKey).
const _testPrivateKeyHex = 'fb1ace12f9801e85f3db1b3935dd47d9f064f98152466f47c701b5e12680e612';

final _privKey = EthPrivateKey.fromHex(_testPrivateKeyHex);
final _walletAddress = _privKey.address.hexEip55;

const _metaMaskDelegator = '0x63c0c19a282a1b52b07dd5a65b58948a07dae32b';
const _delegationManager = '0xdb9b1e94b5b69df7e401ddbede43491141047db3';

const _confirmedRecipient = '0xRecipient';
const _confirmedAmount = 5;

/// Debug-wallet style credential: it is neither BitboxCredentials nor
/// EthPrivateKey, so `Eip712Signer.signDelegation` hits its `_ => throw
/// UnsupportedError(...)` branch — exactly the debug-wallet capability gap.
class _UnsupportedCreds extends Fake implements CredentialsWithKnownAddress {
  @override
  EthereumAddress get address => _privKey.address;
}

Map<String, dynamic> _eip7702Json({int chainId = 1, String recipient = _confirmedRecipient}) => {
  'relayerAddress': '0xrelay',
  'delegationManagerAddress': _delegationManager,
  'delegatorAddress': _metaMaskDelegator,
  'userNonce': 7,
  'domain': {
    'name': 'RealUnit',
    'version': '1',
    'chainId': chainId,
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
  // The asset address the mainnet RealUnit token resolves to in this fixture.
  'tokenAddress': '0x553C7f9C780316FC1D34b8e14ac2465Ab22a090B',
  'amountWei': '5',
  'recipient': recipient,
};

RealUnitTransferPaymentInfoDto _info({
  String toAddress = _confirmedRecipient,
  int amount = _confirmedAmount,
  String eip7702Recipient = _confirmedRecipient,
}) => RealUnitTransferPaymentInfoDto.fromJson({
  'id': 42,
  'uid': 'RTabc',
  'toAddress': toAddress,
  'amount': amount,
  'tokenAddress': '0xRealu',
  'chainId': 1,
  'eip7702': _eip7702Json(recipient: eip7702Recipient),
});

/// Happy-path confirm with matching user-confirmed recipient/amount.
Future<String> _confirm(
  RealUnitTransferService service,
  RealUnitTransferPaymentInfoDto info, {
  String confirmedRecipient = _confirmedRecipient,
  int confirmedAmount = _confirmedAmount,
}) {
  return service.confirmTransfer(
    info,
    confirmedRecipient: confirmedRecipient,
    confirmedAmount: confirmedAmount,
  );
}

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
    when(() => account.primaryAddress).thenReturn(_privKey);
    when(() => walletService.ensureCurrentWalletUnlocked()).thenAnswer((_) async {});
    when(() => walletService.lockCurrentWallet()).thenAnswer((_) async {});
  });

  RealUnitTransferService build(http.Client client) {
    when(() => appStore.httpClient).thenReturn(client);
    return RealUnitTransferService(appStore, walletService);
  }

  group('prepareTransfer', () {
    test('200 → parses the payment-info DTO and PUTs toAddress + amount', () async {
      Uri? sentUri;
      Map<String, dynamic>? body;
      final client = MockClient((request) async {
        sentUri = request.url;
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'id': 42,
            'uid': 'RTabc',
            'toAddress': '0xRecipient',
            'amount': 5,
            'tokenAddress': '0xRealu',
            'chainId': 1,
            'eip7702': _eip7702Json(),
          }),
          200,
        );
      });

      final info = await build(client).prepareTransfer(
        const RealUnitTransferDto(toAddress: '0xRecipient', amount: 5),
      );

      expect(sentUri!.path, '/v1/realunit/transfer');
      expect(body, {'toAddress': '0xRecipient', 'amount': 5});
      expect(info.id, 42);
      expect(info.eip7702.recipient, '0xRecipient');
    });

    test('503 → TransferGasFundingUnavailableException', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({'statusCode': 503, 'message': 'W2W gas funding temporarily unavailable'}),
          503,
        ),
      );

      expect(
        () => build(client).prepareTransfer(
          const RealUnitTransferDto(toAddress: '0xRecipient', amount: 5),
        ),
        throwsA(isA<TransferGasFundingUnavailableException>()),
      );
    });

    test('400 (invalid recipient / insufficient REALU) → ApiException', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({'statusCode': 400, 'code': 'X', 'message': 'Invalid recipient address'}),
          400,
        ),
      );

      expect(
        () => build(client).prepareTransfer(
          const RealUnitTransferDto(toAddress: 'bad', amount: 5),
        ),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('confirmTransfer (software wallet happy path)', () {
    test('signs delegation + authorization, PUTs the envelope, returns txHash', () async {
      Uri? sentUri;
      Map<String, dynamic>? body;
      final client = MockClient((request) async {
        sentUri = request.url;
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'txHash': '0xdeadbeef'}), 200);
      });

      final txHash = await _confirm(build(client), _info());

      expect(txHash, '0xdeadbeef');
      expect(sentUri!.path, '/v1/realunit/transfer/42/confirm');

      final envelope = body!;
      expect(envelope.containsKey('delegation'), isTrue);
      expect(envelope.containsKey('authorization'), isTrue);

      final delegation = envelope['delegation'] as Map<String, dynamic>;
      expect(delegation['delegate'], '0xrelay');
      expect(delegation['delegator'], _walletAddress);
      expect(delegation['authority'], '0xauth');
      expect(delegation['salt'], '0');
      expect((delegation['signature'] as String).length, 132);

      final authorization = envelope['authorization'] as Map<String, dynamic>;
      expect(authorization['chainId'], 1);
      expect(authorization['address'], _metaMaskDelegator);
      expect(authorization['nonce'], 7);
      // r/s are always full 32-byte (64 hex char) big-endian values.
      expect((authorization['r'] as String).substring(2).length, 64);
      expect((authorization['s'] as String).substring(2).length, 64);
      expect(authorization['yParity'], anyOf(0, 1));
    });

    test('locks the wallet after signing (key never left resident)', () async {
      final client = MockClient((_) async => http.Response(jsonEncode({'txHash': '0x1'}), 200));

      await _confirm(build(client), _info());

      verify(() => walletService.ensureCurrentWalletUnlocked()).called(1);
      verify(() => walletService.lockCurrentWallet()).called(1);
    });

    test('debug-wallet credentials → TransferSignatureUnsupportedException', () async {
      when(() => account.primaryAddress).thenReturn(_UnsupportedCreds());
      final client = MockClient((_) async => http.Response('{}', 200));

      expect(
        () => _confirm(build(client), _info()),
        throwsA(isA<TransferSignatureUnsupportedException>()),
      );
    });

    test('503 on confirm → TransferGasFundingUnavailableException', () async {
      final client = MockClient(
        (_) async => http.Response(jsonEncode({'message': 'unavailable'}), 503),
      );

      expect(
        () => _confirm(build(client), _info()),
        throwsA(isA<TransferGasFundingUnavailableException>()),
      );
    });

    test('4xx on confirm → ApiException', () async {
      final client = MockClient(
        (_) async =>
            http.Response(jsonEncode({'statusCode': 409, 'code': 'X', 'message': 'no'}), 409),
      );

      expect(
        () => _confirm(build(client), _info()),
        throwsA(isA<ApiException>()),
      );
    });

    // Every pinned contract/field is rejected before signing, mirroring the
    // sell software-confirm guard. Each case mutates one field of the otherwise
    // valid eip7702 payload and asserts validation throws WITHOUT any PUT.
    group('eip7702 validation pins (throw before any PUT)', () {
      RealUnitTransferPaymentInfoDto infoWith(Map<String, dynamic> Function() mutate) =>
          RealUnitTransferPaymentInfoDto.fromJson({
            'id': 42,
            'uid': 'RTabc',
            'toAddress': _confirmedRecipient,
            'amount': _confirmedAmount,
            'tokenAddress': '0xRealu',
            'chainId': 1,
            'eip7702': mutate(),
          });

      Future<void> expectRejected(RealUnitTransferPaymentInfoDto info) async {
        var called = false;
        final client = MockClient((_) async {
          called = true;
          return http.Response('{}', 200);
        });
        await expectLater(() => _confirm(build(client), info), throwsException);
        expect(called, isFalse, reason: 'no PUT must happen when validation rejects the payload');
      }

      test('wrong delegator (MetaMask delegator) contract', () async {
        await expectRejected(infoWith(() => _eip7702Json()..['delegatorAddress'] = '0xWrong'));
      });

      test('wrong delegation manager contract', () async {
        await expectRejected(
          infoWith(() => _eip7702Json()..['delegationManagerAddress'] = '0xWrong'),
        );
      });

      test('verifying contract != delegation manager', () async {
        await expectRejected(
          infoWith(() {
            final json = _eip7702Json();
            (json['domain'] as Map<String, dynamic>)['verifyingContract'] = '0xWrong';
            return json;
          }),
        );
      });

      test('message delegator != wallet address', () async {
        await expectRejected(
          infoWith(() {
            final json = _eip7702Json();
            (json['message'] as Map<String, dynamic>)['delegator'] = '0xSomeoneElse';
            return json;
          }),
        );
      });

      test('chain id mismatch', () async {
        await expectRejected(infoWith(() => _eip7702Json(chainId: 999)));
      });

      test('message delegate != relayer address', () async {
        await expectRejected(
          infoWith(() {
            final json = _eip7702Json();
            (json['message'] as Map<String, dynamic>)['delegate'] = '0xOtherRelayer';
            return json;
          }),
        );
      });

      test('token address != RealUnit token', () async {
        await expectRejected(infoWith(() => _eip7702Json()..['tokenAddress'] = '0xNotRealu'));
      });

      test('amount-wei mismatch', () async {
        await expectRejected(infoWith(() => _eip7702Json()..['amountWei'] = '6'));
      });

      test('unparseable amount-wei', () async {
        await expectRejected(infoWith(() => _eip7702Json()..['amountWei'] = 'not-a-number'));
      });
    });

    // User-confirmed recipient/amount must match the prepare response before
    // any signature is produced (blind-sign guard).
    group('user-confirmed recipient/amount guard (throw before any PUT)', () {
      Future<void> expectMismatch(
        RealUnitTransferPaymentInfoDto info, {
        String confirmedRecipient = _confirmedRecipient,
        int confirmedAmount = _confirmedAmount,
      }) async {
        var called = false;
        final client = MockClient((_) async {
          called = true;
          return http.Response('{}', 200);
        });
        await expectLater(
          () => _confirm(
            build(client),
            info,
            confirmedRecipient: confirmedRecipient,
            confirmedAmount: confirmedAmount,
          ),
          throwsA(isA<TransferConfirmMismatchException>()),
        );
        expect(called, isFalse, reason: 'no PUT must happen when user-confirm guard rejects');
      }

      test('toAddress mismatch → TransferConfirmMismatchException', () async {
        await expectMismatch(_info(toAddress: '0xOtherRecipient'));
      });

      test('eip7702.recipient mismatch → TransferConfirmMismatchException', () async {
        await expectMismatch(_info(eip7702Recipient: '0xOtherRecipient'));
      });

      test('amount mismatch → TransferConfirmMismatchException', () async {
        await expectMismatch(_info(amount: 99));
      });

      test('case-insensitive recipient match is accepted (no throw)', () async {
        final client = MockClient(
          (_) async => http.Response(jsonEncode({'txHash': '0xok'}), 200),
        );
        final txHash = await _confirm(
          build(client),
          _info(toAddress: '0xrecipient', eip7702Recipient: '0xRECIPIENT'),
          confirmedRecipient: '0xReCiPiEnT',
        );
        expect(txHash, '0xok');
      });
    });
  });

  group('confirm 409 mapping', () {
    test('409 "already confirmed" → TransferAlreadyConfirmedException', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'statusCode': 409,
            'message': 'Transaction request is already confirmed',
            'error': 'Conflict',
            'txHash': '0xfrom409',
          }),
          409,
        ),
      );

      await expectLater(
        _confirm(build(client), _info()),
        throwsA(
          isA<TransferAlreadyConfirmedException>()
              .having((e) => e.txHash, 'txHash', '0xfrom409')
              .having(
                (e) => e.message.toLowerCase().contains('already confirmed'),
                'message mentions already confirmed',
                isTrue,
              ),
        ),
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
        _confirm(build(client), _info()),
        throwsA(
          predicate((e) => e is ApiException && e is! TransferAlreadyConfirmedException),
        ),
      );
    });
  });
}
