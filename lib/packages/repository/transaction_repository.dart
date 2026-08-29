import 'dart:async';

import 'package:collection/collection.dart';
import 'package:realunit_wallet/models/asset.dart';
import 'package:realunit_wallet/models/blockchain.dart';
import 'package:realunit_wallet/models/dfx_transaction.dart';
import 'package:realunit_wallet/models/transaction.dart';
import 'package:realunit_wallet/packages/repository/asset_repository.dart';
import 'package:realunit_wallet/packages/storage/database.dart';
import 'package:realunit_wallet/packages/storage/dfx_transaction_storage.dart';
import 'package:realunit_wallet/packages/storage/transaction_storage.dart';

class TransactionRepository {
  final AppDatabase _appDatabase;
  final AssetRepository _assetRepository;

  const TransactionRepository(this._appDatabase, this._assetRepository);

  Future<int> getLatestHeight() async =>
      (await _appDatabase.getLatestTransactions(limit: 1)).firstOrNull?.height ?? 0;

  /// SQLite UNIQUE on `txId` is case-sensitive. A payout hash `0xabc` must
  /// not sit beside a history row `0xAbC` as a second prize/buy
  /// (Offerte Punkt 2). Write onto the stored casing when it exists.
  Future<int> insertTransaction(Transaction transaction) async {
    if (await findTxIdIgnoreCase(transaction.txId) != null) {
      return updateTransaction(transaction);
    }
    return _appDatabase.insertTransactions(
      transaction.height,
      transaction.txId,
      transaction.chainId,
      transaction.senderAddress,
      transaction.receiverAddress,
      transaction.amount.toRadixString(16),
      transaction.asset.id,
      transaction.type.index,
      transaction.note ?? '',
      transaction.data ?? '',
      transaction.timestamp,
    );
  }

  /// Payout hashes and history hashes do not always share casing.
  /// Write onto the stored row so converting an on-chain transfer into a
  /// prize cannot no-op and leave frozen CHF off the history line
  /// (Offerte Punkt 2).
  Future<int> updateTransaction(Transaction transaction) async {
    final stored = await findTxIdIgnoreCase(transaction.txId) ?? transaction.txId;
    return _appDatabase.updateTransaction(
      stored,
      height: transaction.height,
      chainId: transaction.chainId,
      senderAddress: transaction.senderAddress,
      receiverAddress: transaction.receiverAddress,
      amount: transaction.amount.toRadixString(16),
      asset: transaction.asset.id,
      type: transaction.type.index,
      note: transaction.note ?? '',
      data: transaction.data ?? '',
      timeStamp: transaction.timestamp,
    );
  }

  Future<void> insertDfxTransaction(DfxTransaction transaction) async {
    await insertTransaction(transaction);
    final stored = await findTxIdIgnoreCase(transaction.txId) ?? transaction.txId;
    final existing = await _appDatabase.getDfxTransactionDetails(stored);
    if (existing != null) {
      await _appDatabase.updateDfxTransactionDetails(
        txId: stored,
        dfxId: transaction.dfxId,
        rate: transaction.rate.toString(),
        inputTxId: transaction.inputTxId,
        outputTxId: transaction.outputTxId,
      );
      return;
    }
    await _appDatabase.insertDfxTransactionDetails(
      txId: stored,
      dfxId: transaction.dfxId,
      rate: transaction.rate.toString(),
      inputTxId: transaction.inputTxId,
      outputTxId: transaction.outputTxId,
    );
  }

  Future<void> updateDfxTransaction(DfxTransaction transaction) async {
    await updateTransaction(transaction);
    final stored = await findTxIdIgnoreCase(transaction.txId) ?? transaction.txId;
    await _appDatabase.updateDfxTransactionDetails(
      txId: stored,
      dfxId: transaction.dfxId,
      rate: transaction.rate.toString(),
      inputTxId: transaction.inputTxId,
      outputTxId: transaction.outputTxId,
    );
  }

  Future<bool> existsTransaction(String txId) =>
      _appDatabase.getTransaction(txId).then((txData) => txData != null);

  /// Stored `txId` when [txId] matches ignoring case, otherwise null.
  Future<String?> findTxIdIgnoreCase(String txId) =>
      _appDatabase.getTransactionIgnoreCase(txId).then((row) => row?.txId);

  /// True when the stored row is already a prize (Offerte Punkt 2).
  /// Account history must not rewrite it as a buy and drop frozen CHF.
  Future<bool> isReferralPayoutIgnoreCase(String txId) async {
    final row = await _appDatabase.getTransactionIgnoreCase(txId);
    return row?.type == TransactionTypes.referralPayout.index;
  }

  /// Drop leftover DFX Beleg details first so SQLite FK
  /// (`DfxTransactionDetails.txId` → `Transactions.txId`, NO ACTION)
  /// cannot block the leftover synthetic `referral-payout-{id}` delete
  /// when a hashed prize replaces it (Offerte Punkt 2). Match the stored
  /// hash ignoring case — payouts and history do not always share casing.
  Future<int> deleteTransaction(String txId) async {
    final stored = await findTxIdIgnoreCase(txId);
    if (stored == null) return 0;
    await deleteDfxTransactionDetailsIgnoreCase(stored);
    return _appDatabase.deleteTransaction(stored);
  }

  /// Prize rows have no DFX Beleg. Drop leftover buy/sell metadata so a
  /// converted on-chain transfer cannot keep a live rate or receipt id.
  Future<int> deleteDfxTransactionDetailsIgnoreCase(String txId) =>
      _appDatabase.deleteDfxTransactionDetailsIgnoreCase(txId);

  Future<List<Transaction>> get allTransactions async {
    final assets = await _assetRepository.allAssets;
    final dfxDetailsList = await _appDatabase.allDfxTransactionDetails;

    return _appDatabase.allTransactions.then(
      (result) => result.map((txData) {
        final blockchain = Blockchain.getFromChainId(txData.chainId);
        final txType = TransactionTypes.values[txData.type];
        final asset = txType == TransactionTypes.transfer
            ? blockchain.nativeAsset
            : assets.firstWhere(
                (e) => e.id == txData.asset,
                orElse: () => Asset(
                  chainId: blockchain.chainId,
                  address: txData.receiverAddress,
                  name: 'Unknown',
                  symbol: '???',
                  decimals: 18,
                ),
              );

        final dfxDetails = dfxDetailsList.firstWhereOrNull(
          (dfxDetail) => dfxDetail.txId == txData.txId,
        );
        if (dfxDetails != null) {
          return DfxTransaction(
            dfxId: dfxDetails.dfxId,
            rate: double.tryParse(dfxDetails.rate ?? ''),
            inputTxId: dfxDetails.inputTxId,
            outputTxId: dfxDetails.outputTxId,
            height: txData.height,
            txId: txData.txId,
            chainId: txData.chainId,
            senderAddress: txData.senderAddress,
            receiverAddress: txData.receiverAddress,
            amount: BigInt.parse(txData.amount, radix: 16),
            asset: asset,
            type: txType,
            note: txData.note,
            data: txData.data,
            timestamp: txData.timeStamp,
          );
        }

        return Transaction(
          height: txData.height,
          txId: txData.txId,
          chainId: txData.chainId,
          senderAddress: txData.senderAddress,
          receiverAddress: txData.receiverAddress,
          amount: BigInt.parse(txData.amount, radix: 16),
          asset: asset,
          type: txType,
          note: txData.note,
          data: txData.data,
          timestamp: txData.timeStamp,
        );
      }).toList(),
    );
  }

  Stream<List<Transaction>> watchTransactions() =>
      _appDatabase.watchTransactions().transform<List<Transaction>>(_transformer);

  Stream<List<Transaction>> watchTransactionsOfAssets(
    Iterable<Asset> assets,
    String wallet, [
    int? limit,
  ]) {
    if (limit != null) {
      return _appDatabase
          .watchTransfersOfAssetsLimit(assets.map((e) => e.id), wallet, limit)
          .transform<List<Transaction>>(_transformer);
    }
    return _appDatabase
        .watchTransfersOfAssets(assets.map((e) => e.id), wallet)
        .transform<List<Transaction>>(_transformer);
  }

  Stream<List<Transaction>> watchTransactionsSavings(
    Iterable<Asset> assets,
    String wallet,
    int limit,
  ) {
    return _appDatabase
        .watchTransfersOfSavingsLimit(assets.map((e) => e.id), wallet, limit)
        .transform<List<Transaction>>(_transformer);
  }

  StreamTransformer<List<TransactionData>, List<Transaction>> get _transformer =>
      StreamTransformer<List<TransactionData>, List<Transaction>>.fromHandlers(
        handleData: (rawTransactions, sink) async {
          final transactions = <Transaction>[];

          final assets = await _assetRepository.allAssets;
          final dfxDetailsList = await _appDatabase.allDfxTransactionDetails;

          for (final transactionData in rawTransactions) {
            final txType = TransactionTypes.values[transactionData.type];
            final blockchain = Blockchain.getFromChainId(transactionData.chainId);
            final asset = txType == TransactionTypes.transfer
                ? blockchain.nativeAsset
                : assets.firstWhere(
                    (e) => e.id == transactionData.asset,
                    orElse: () => Asset(
                      chainId: blockchain.chainId,
                      address: transactionData.receiverAddress,
                      name: 'Unknown',
                      symbol: '???',
                      decimals: 18,
                    ),
                  );

            final dfxDetails = dfxDetailsList.firstWhereOrNull(
              (dfxDetail) => dfxDetail.txId == transactionData.txId,
            );
            if (dfxDetails != null) {
              transactions.add(
                DfxTransaction(
                  dfxId: dfxDetails.dfxId,
                  rate: double.tryParse(dfxDetails.rate ?? ''),
                  inputTxId: dfxDetails.inputTxId,
                  outputTxId: dfxDetails.outputTxId,
                  height: transactionData.height,
                  txId: transactionData.txId,
                  chainId: transactionData.chainId,
                  senderAddress: transactionData.senderAddress,
                  receiverAddress: transactionData.receiverAddress,
                  amount: BigInt.parse(transactionData.amount, radix: 16),
                  asset: asset,
                  type: txType,
                  note: transactionData.note,
                  data: transactionData.data,
                  timestamp: transactionData.timeStamp,
                ),
              );
            } else {
              transactions.add(
                Transaction(
                  height: transactionData.height,
                  txId: transactionData.txId,
                  chainId: transactionData.chainId,
                  senderAddress: transactionData.senderAddress,
                  receiverAddress: transactionData.receiverAddress,
                  amount: BigInt.parse(transactionData.amount, radix: 16),
                  asset: asset,
                  type: txType,
                  note: transactionData.note,
                  data: transactionData.data,
                  timestamp: transactionData.timeStamp,
                ),
              );
            }
          }

          sink.add(transactions);
        },
      );
}
