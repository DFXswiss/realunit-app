import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/models/balance.dart';
import 'package:realunit_wallet/packages/config/api_config.dart';
import 'package:realunit_wallet/packages/config/network_mode.dart';
import 'package:realunit_wallet/packages/repository/balance_repository.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/utils/default_assets.dart';
import 'package:realunit_wallet/screens/sell/cubits/sell_balance/sell_balance_cubit.dart';

class _MockBalanceRepository extends Mock implements BalanceRepository {}

class _MockAppStore extends Mock implements AppStore {}

class _FakeBalance extends Fake implements Balance {}

const _wallet = '0x000000000000000000000000000000000000beef';

void main() {
  late _MockBalanceRepository repo;
  late _MockAppStore appStore;
  late StreamController<Balance> controller;

  setUpAll(() {
    registerFallbackValue(_FakeBalance());
  });

  setUp(() {
    repo = _MockBalanceRepository();
    appStore = _MockAppStore();
    controller = StreamController<Balance>();
    when(() => appStore.apiConfig)
        .thenReturn(const ApiConfig(networkMode: NetworkMode.mainnet));
    when(() => appStore.primaryAddress).thenReturn(_wallet);
    when(() => repo.watchBalance(any())).thenAnswer((_) => controller.stream);
  });

  tearDown(() async {
    await controller.close();
  });

  group('$SellBalanceCubit', () {
    test('initial state is a zero balance derived from appStore', () {
      final cubit = SellBalanceCubit(repo, appStore);

      expect(cubit.state.chainId, realUnitAsset.chainId);
      expect(cubit.state.contractAddress, realUnitAsset.address);
      expect(cubit.state.walletAddress, _wallet);
      expect(cubit.state.balance, BigInt.zero);
      expect(cubit.state.asset, realUnitAsset);
    });

    test('subscribes to BalanceRepository.watchBalance on init', () {
      SellBalanceCubit(repo, appStore);

      verify(() => repo.watchBalance(any())).called(1);
    });

    test('emits balance updates pushed through the repo stream', () async {
      final cubit = SellBalanceCubit(repo, appStore);

      final updated = Balance(
        chainId: realUnitAsset.chainId,
        contractAddress: realUnitAsset.address,
        walletAddress: _wallet,
        balance: BigInt.from(7000),
        asset: realUnitAsset,
      );
      final ready = cubit.stream.firstWhere((b) => b.balance == BigInt.from(7000));
      controller.add(updated);
      await ready.timeout(const Duration(seconds: 1));

      expect(cubit.state.balance, BigInt.from(7000));
    });

    test(
        'a stream error is handled (not unhandled) and later balances still '
        'update (issue #657 P4 S6 regression)', () async {
      final cubit = SellBalanceCubit(repo, appStore);

      // Without an onError handler this error escaped as an unhandled async
      // error (failing the test) and stopped the sell balance. It must now be
      // logged, and — cancelOnError being false — a later balance still lands.
      controller.addError(Exception('balance backend blip'));
      await Future<void>.delayed(Duration.zero);

      final updated = Balance(
        chainId: realUnitAsset.chainId,
        contractAddress: realUnitAsset.address,
        walletAddress: _wallet,
        balance: BigInt.from(4242),
        asset: realUnitAsset,
      );
      final ready = cubit.stream.firstWhere((b) => b.balance == BigInt.from(4242));
      controller.add(updated);
      await ready.timeout(const Duration(seconds: 1));

      expect(cubit.state.balance, BigInt.from(4242));
    });

    test('close() cancels the subscription cleanly', () async {
      final cubit = SellBalanceCubit(repo, appStore);

      await cubit.close();

      expect(cubit.isClosed, isTrue);
    });
  });
}
