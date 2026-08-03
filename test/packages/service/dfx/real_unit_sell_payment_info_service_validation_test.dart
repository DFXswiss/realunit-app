import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/config/api_config.dart';
import 'package:realunit_wallet/packages/config/network_mode.dart';
import 'package:realunit_wallet/packages/repository/cache_repository.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
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

class _PrivKeyCreds extends Fake implements CredentialsWithKnownAddress {
  _PrivKeyCreds(this._address);
  final String _address;
  @override
  EthereumAddress get address => EthereumAddress.fromHex(_address);
}

// MetaMask Delegation Framework v1.3.0 constants pinned in
// real_unit_sell_payment_info_service.dart — kept verbatim here so a refactor
// that touches one but not both surfaces in this file.
const _metaMaskDelegator = '0x63c0c19a282a1b52b07dd5a65b58948a07dae32b';
const _delegationManager = '0xdb9b1e94b5b69df7e401ddbede43491141047db3';

// All-lowercase hex so EthereumAddress.fromHex accepts it without an EIP-55
// checksum. The validation guard lowercases both sides before comparison.
const _walletAddress = '0x9f5713deacb8e9cab6c2d3fae1afc2715f8d2d71';

Map<String, dynamic> _validEip7702Json() => {
      'relayerAddress': '0xrelay',
      'delegationManagerAddress': _delegationManager,
      'delegatorAddress': _metaMaskDelegator,
      'userNonce': 7,
      'domain': {
        'name': 'RealUnit',
        'version': '1',
        'chainId': 1, // mainnet
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
      // Mainnet RealUnit asset address from default_assets.dart.
      'tokenAddress': '0x553C7f9C780316FC1D34b8e14ac2465Ab22a090B',
      // realUnitAsset.decimals == 0, so userAmount=100 → amountWei = 100 * 10^0 = 100.
      'amountWei': '100',
      'depositAddress': '0xdeposit',
    };

SellPaymentInfo _info({
  Map<String, dynamic>? eip7702Override,
  int amount = 100,
}) =>
    SellPaymentInfo(
      id: 42,
      eip7702: Eip7702Data.fromJson(eip7702Override ?? _validEip7702Json()),
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
    session.setAuthToken(
      'jwt-1',
      EthereumAddress.fromHex(_walletAddress).hexEip55,
    );

    when(() => appStore.apiConfig)
        .thenReturn(const ApiConfig(networkMode: NetworkMode.mainnet));
    when(() => appStore.sessionCache).thenReturn(session);
    when(() => appStore.wallet).thenReturn(wallet);
    when(() => wallet.currentAccount).thenReturn(account);
    // Wallet address must match message.delegator for the validation guard
    // to pass the delegator check.
    when(() => account.primaryAddress).thenReturn(_PrivKeyCreds(_walletAddress));
    when(() => walletService.ensureCurrentWalletUnlocked()).thenAnswer((_) async {});
    when(() => walletService.lockCurrentWallet()).thenAnswer((_) async {});
  });

  RealUnitSellPaymentInfoService build({http.Client? client}) {
    when(() => appStore.httpClient)
        .thenReturn(client ?? MockClient((_) async => http.Response('{}', 200)));
    return RealUnitSellPaymentInfoService(appStore, walletService);
  }

  group('confirmPayment validation guard', () {
    test('wrong delegatorAddress → throws "MetaMask Delegator"', () async {
      final json = _validEip7702Json()..['delegatorAddress'] = '0xWRONGdelegator';

      await expectLater(
        build().confirmPayment(_info(eip7702Override: json)),
        throwsA(predicate(
          (e) => e.toString().contains('MetaMask Delegator'),
        )),
      );
    });

    test('wrong delegationManagerAddress → throws "delegation manager"', () async {
      final json = _validEip7702Json()..['delegationManagerAddress'] = '0xWRONGmgr';

      await expectLater(
        build().confirmPayment(_info(eip7702Override: json)),
        throwsA(predicate(
          (e) => e.toString().contains('delegation manager'),
        )),
      );
    });

    test('wrong verifyingContract → throws "verifying contract"', () async {
      final json = _validEip7702Json();
      json['domain'] = {
        ...json['domain'] as Map<String, dynamic>,
        'verifyingContract': '0xWRONG',
      };

      await expectLater(
        build().confirmPayment(_info(eip7702Override: json)),
        throwsA(predicate(
          (e) => e.toString().contains('verifying contract'),
        )),
      );
    });

    test('message.delegator != walletAddress → throws "delegator does not match"', () async {
      final json = _validEip7702Json();
      json['message'] = {
        ...json['message'] as Map<String, dynamic>,
        'delegator': '0xSomeoneElse',
      };

      await expectLater(
        build().confirmPayment(_info(eip7702Override: json)),
        throwsA(predicate(
          (e) => e.toString().contains('delegator does not match wallet address'),
        )),
      );
    });

    test('domain.chainId != expectedChainId → throws "chain ID mismatch"', () async {
      final json = _validEip7702Json();
      json['domain'] = {
        ...json['domain'] as Map<String, dynamic>,
        'chainId': 5,
      };

      await expectLater(
        build().confirmPayment(_info(eip7702Override: json)),
        throwsA(predicate(
          (e) => e.toString().contains('chain ID mismatch'),
        )),
      );
    });

    test('message.delegate != relayerAddress → throws "delegate does not match"', () async {
      final json = _validEip7702Json();
      json['message'] = {
        ...json['message'] as Map<String, dynamic>,
        'delegate': '0xOTHER',
      };

      await expectLater(
        build().confirmPayment(_info(eip7702Override: json)),
        throwsA(predicate(
          (e) => e.toString().contains('delegate does not match relayer'),
        )),
      );
    });

    test('tokenAddress != RealUnit asset address → throws "token address"', () async {
      final json = _validEip7702Json()..['tokenAddress'] = '0xOtherToken';

      await expectLater(
        build().confirmPayment(_info(eip7702Override: json)),
        throwsA(predicate(
          (e) => e.toString().contains('token address does not match RealUnit'),
        )),
      );
    });

    test('amountWei != userAmount * 10^decimals → throws "amount mismatch"', () async {
      final json = _validEip7702Json()..['amountWei'] = '99';

      await expectLater(
        build().confirmPayment(_info(eip7702Override: json, amount: 100)),
        throwsA(predicate(
          (e) => e.toString().contains('amount mismatch'),
        )),
      );
    });

    test('amountWei is non-numeric → throws "amount mismatch"', () async {
      final json = _validEip7702Json()..['amountWei'] = 'not-a-bigint';

      await expectLater(
        build().confirmPayment(_info(eip7702Override: json)),
        throwsA(predicate(
          (e) => e.toString().contains('amount mismatch'),
        )),
      );
    });
  });
}
