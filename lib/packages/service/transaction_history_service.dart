import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:web3dart/credentials.dart';
import 'package:realunit_wallet/models/dfx_transaction.dart';
import 'package:realunit_wallet/models/transaction.dart';
import 'package:realunit_wallet/packages/config/api_config.dart';
import 'package:realunit_wallet/packages/io/format_frozen_chf.dart';
import 'package:realunit_wallet/packages/repository/transaction_repository.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_auth_service.dart';
import 'package:realunit_wallet/packages/service/dfx/models/history/dto/account_history_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_payout_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/referral_json_list.dart';
import 'package:realunit_wallet/packages/service/dfx/models/transactions/dto/transactions_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_referral_service.dart';

class TransactionHistoryService extends DFXAuthService {
  static String _accountHistoryPath(String address) => '/v1/realunit/account/$address/history';
  static const String _transactionsPath = 'v1/transaction';

  final TransactionRepository _transactionRepository;

  TransactionHistoryService(
    super.appStore,
    super.walletService,
    this._transactionRepository,
  );

  Future<void> apiBasedSync() async {
    final results = await Future.wait([
      _fetchAccountHistory(),
      _fetchTransactions(),
    ]);

    final accountHistory = results.elementAt(0) as AccountHistoryDto?;
    final transactions = results.elementAt(1) as List<TransactionDto>;

    if (accountHistory != null) {
      for (final entry in accountHistory.history) {
        final transfer = entry.transfer;
        if (transfer == null) continue;

        var txId = entry.txHash;
        if (await _transactionRepository.isReferralPayoutIgnoreCase(txId)) {
          continue;
        }
        final storedTxId = await _transactionRepository.findTxIdIgnoreCase(txId);
        final exists = storedTxId != null;
        if (storedTxId != null) txId = storedTxId;
        final matchingTransaction = transactions.firstWhereOrNull(
          (t) => t.inputTxId == txId || t.outputTxId == txId,
        );

        if (matchingTransaction != null && matchingTransaction.id != null) {
          final dfxTransaction = DfxTransaction(
            dfxId: matchingTransaction.id!,
            rate: matchingTransaction.rate,
            inputTxId: matchingTransaction.inputTxId,
            outputTxId: matchingTransaction.outputTxId,
            height: 0, // TODO
            txId: txId,
            chainId: appStore.apiConfig.asset.chainId,
            senderAddress: transfer.from,
            receiverAddress: transfer.to,
            amount: BigInt.parse(transfer.value),
            asset: appStore.apiConfig.asset,
            type: TransactionTypes.tokenTransfer,
            note: '',
            data: null,
            timestamp: entry.timestamp,
          );

          if (exists) {
            await _transactionRepository.updateDfxTransaction(dfxTransaction);
          } else {
            await _transactionRepository.insertDfxTransaction(dfxTransaction);
          }
        } else {
          final transaction = Transaction(
            height: 0, // TODO
            txId: txId,
            chainId: appStore.apiConfig.asset.chainId,
            senderAddress: transfer.from,
            receiverAddress: transfer.to,
            amount: BigInt.parse(transfer.value),
            asset: appStore.apiConfig.asset,
            type: TransactionTypes.tokenTransfer,
            note: '',
            data: null,
            timestamp: entry.timestamp,
          );

          if (exists) {
            await _transactionRepository.updateTransaction(transaction);
          } else {
            await _transactionRepository.insertTransaction(transaction);
          }
        }
      }
    }

    await _syncReferralPayouts();
  }

  Future<void> _syncReferralPayouts() async {
    try {
      final uri = buildUri(host, '/v1/realunit/referral/payouts');
      final response = await authenticatedGet(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(RealUnitReferralService.lookupTimeout);
      if (response.statusCode != 200) return;

      final decoded = jsonDecode(response.body);
      final rows = referralJsonList(decoded);
      if (rows.isEmpty) return;

      final asset = appStore.apiConfig.asset;
      final walletAddress = appStore.primaryAddress;
      final seenIds = <int>{};
      final seenHashes = <String>{};
      for (final raw in rows) {
        final ReferralPayoutDto payout;
        try {
          payout = ReferralPayoutDto.fromJson(raw);
        } catch (_) {
          continue;
        }
        if (!payout.isSettled) continue;
        final hash = payout.txHash;
        final hashKey = hash != null && hash.isNotEmpty ? hash.toLowerCase() : null;
        if (payout.id == 0 && hashKey == null) continue;
        if (payout.id != 0 && !seenIds.add(payout.id)) continue;
        if (hashKey != null && !seenHashes.add(hashKey)) continue;
        var txId = hashKey ?? 'referral-payout-${payout.id}';
        final storedTxId = await _transactionRepository.findTxIdIgnoreCase(txId);
        var exists = storedTxId != null;
        if (storedTxId != null) txId = storedTxId;
        if (!exists && hash != null && hash.isNotEmpty) {
          final byHash = await _transactionRepository.findTxIdIgnoreCase(hash);
          if (byHash != null) {
            txId = byHash;
            exists = true;
          }
        }
        final synthetic = payout.id != 0 ? 'referral-payout-${payout.id}' : null;
        if (hashKey != null && synthetic != null && txId != synthetic) {
          final leftover = await _transactionRepository.findTxIdIgnoreCase(synthetic);
          if (leftover != null) {
            await _transactionRepository.deleteTransaction(leftover);
          }
        }
        await _transactionRepository.deleteDfxTransactionDetailsIgnoreCase(txId);
        final transaction = Transaction(
          height: 0,
          txId: txId,
          chainId: asset.chainId,
          senderAddress: kReferralPayoutSenderAddress,
          receiverAddress: walletAddress,
          amount: BigInt.from(payout.amount.truncate()),
          asset: asset,
          type: TransactionTypes.referralPayout,
          note: '',
          data: formatFrozenChfAmount(payout.chfValue.toString()),
          timestamp: payout.created,
        );
        if (exists) {
          await _transactionRepository.updateTransaction(transaction);
        } else {
          await _transactionRepository.insertTransaction(transaction);
        }
      }
    } catch (_) {
      return;
    }
  }

  Future<AccountHistoryDto?> _fetchAccountHistory() async {
    final address = appStore.primaryAddress;
    final uri = buildUri(host, _accountHistoryPath(address));

    final response = await appStore.httpClient.get(uri);
    if (response.statusCode != 200) return null;

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return AccountHistoryDto.fromJson(body);
  }

  Future<List<TransactionDto>> _fetchTransactions() async {
    final address = appStore.primaryAddress;
    final uri = buildUri(host, _transactionsPath, {'userAddress': address});

    final response = await appStore.httpClient.get(uri);
    if (response.statusCode != 200) return [];

    final List<dynamic> json = jsonDecode(response.body);
    return json.map((e) => TransactionDto.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<TransactionDto>> fetchPendingTransactions() async {
    final uri = buildUri(host, '$_transactionsPath/detail');
    final response = await authenticatedGet(uri);

    if (response.statusCode != 200) return [];

    final List<dynamic> json = jsonDecode(response.body);
    final transactions = json
        .map((e) => TransactionDto.fromJson(e as Map<String, dynamic>))
        .toList();

    final walletAddress = appStore.primaryAddress;
    return transactions.where((t) => t.isPending && t.belongsToWallet(walletAddress)).toList();
  }
}

extension ToEpiAddress on String {
  String get asHexEip55 => EthereumAddress.fromHex(this).hexEip55;

  String get asShortTxId {
    return '${substring(0, 10)}...${substring(length - 10)}';
  }
}
