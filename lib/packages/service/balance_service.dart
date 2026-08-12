import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:realunit_wallet/models/asset.dart';
import 'package:realunit_wallet/models/balance.dart';
import 'package:realunit_wallet/packages/config/api_config.dart';
import 'package:realunit_wallet/packages/repository/balance_repository.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';

class BalanceService {
  static const _balancePath = '/v1/realunit/account';
  String get _host => _appStore.apiConfig.apiHost;

  final BalanceRepository _balanceRepository;
  final AppStore _appStore;

  BalanceService(BalanceRepository balanceRepository, AppStore appStore)
    : _balanceRepository = balanceRepository,
      _appStore = appStore;

  Timer? _syncTimer;

  // Latched once the account endpoint 404s (wallet has no RealUnit account yet)
  // so the 10s poll stops re-hitting it. Only periodic ticks are gated: direct
  // updateBalance calls (eager fetch, app resume) always probe, and a 200
  // un-latches the flag so polling resumes once the account exists.
  bool _accountMissing = false;

  // Bumped on every startSync. updateBalance captures the generation at call
  // time and only writes _accountMissing while it is still current. This keeps
  // a response from a probe issued *before* the latest startSync from clobbering
  // a fresh reset: HomeBloc fires updateBalance unawaited immediately before
  // startSync, so that eager probe's late 404 would otherwise re-latch the flag
  // right after startSync cleared it and silently gate the just-armed poll. It
  // also covers a slow out-of-order straggler and a probe for a previous wallet
  // address, both of which must not flip the gate of the current sync.
  int _syncGeneration = 0;

  void startSync(String address) {
    cancelSync();

    _accountMissing = false;
    _syncGeneration++;
    _syncTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_accountMissing) return;
      updateBalance(address);
    });
  }

  void cancelSync() => _syncTimer?.cancel();

  Future<void> updateBalance(String address) async {
    final generation = _syncGeneration;
    try {
      final uri = buildUri(_host, '$_balancePath/$address');

      final response = await _appStore.httpClient.get(uri);

      if (response.statusCode == 200) {
        if (generation == _syncGeneration) _accountMissing = false;
        await _parseAndPersistBalance(address, response.body);
      } else if (response.statusCode == 404) {
        if (generation == _syncGeneration) _accountMissing = true;
      }
    } catch (e) {
      developer.log('Failed to update RealUnit balance: $e');
    }
  }

  /// Fresh, fail-loud balance read for money-moving flows (migration wizard):
  /// performs the API fetch and THROWS on any transport error, non-200 status,
  /// or unparseable body instead of falling back to the persisted cache. On
  /// success the fresh value is also persisted (same shape as [updateBalance])
  /// and returned. The polling [updateBalance] path stays log-and-continue —
  /// this method exists precisely because that path may serve stale data.
  Future<Balance> fetchBalance(String address) async {
    final uri = buildUri(_host, '$_balancePath/$address');
    final response = await _appStore.httpClient.get(uri);

    if (response.statusCode == 404) {
      throw Exception('RealUnit account not found (404) for address $address');
    }
    if (response.statusCode != 200) {
      throw Exception(
        'Failed to fetch RealUnit balance. Status: ${response.statusCode} ${response.body}',
      );
    }

    return _parseAndPersistBalance(address, response.body);
  }

  Future<Balance> _parseAndPersistBalance(String address, String responseBody) async {
    final json = jsonDecode(responseBody) as Map<String, dynamic>;
    final balanceString = json['balance'];
    if (balanceString is! String) {
      throw const FormatException('Balance response has no parseable balance');
    }

    final balance = Balance(
      chainId: _appStore.apiConfig.asset.chainId,
      contractAddress: _appStore.apiConfig.asset.address,
      walletAddress: address,
      balance: BigInt.parse(balanceString),
      asset: _appStore.apiConfig.asset,
    );
    await _balanceRepository.saveBalance(balance);
    return balance;
  }

  Future<Balance?> getBalance(Asset asset, String address) =>
      _balanceRepository.getBalance(asset, address);
}
