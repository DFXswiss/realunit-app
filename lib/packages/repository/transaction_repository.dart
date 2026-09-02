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

  Future<int> insertTransaction(Transaction transaction) => _appDatabase.insertTransactions(
    transaction.height,
    transaction.txId,
    transaction.chainId,
    transaction.senderAddress,
    transaction.receiverAddress,
    transaction.amount.toRadixString(16),
    transaction.asset.id,
    transaction.type.index,
    transaction.category?.value ?? '',
    transaction.note ?? '',
    transaction.data ?? '',
    transaction.timestamp,
  );

  Future<int> updateTransaction(Transaction transaction) => _appDatabase.updateTransaction(
    transaction.txId,
    height: transaction.height,
    chainId: transaction.chainId,
    senderAddress: transaction.senderAddress,
    receiverAddress: transaction.receiverAddress,
    amount: transaction.amount.toRadixString(16),
    asset: transaction.asset.id,
    type: transaction.type.index,
    category: transaction.category?.value ?? '',
    note: transaction.note ?? '',
    data: transaction.data ?? '',
    timeStamp: transaction.timestamp,
  );

  Future<void> insertDfxTransaction(DfxTransaction transaction) async {
    await insertTransaction(transaction);
    await _appDatabase.insertDfxTransactionDetails(
      txId: transaction.txId,
      dfxId: transaction.dfxId,
      rate: transaction.rate.toString(),
      inputTxId: transaction.inputTxId,
      outputTxId: transaction.outputTxId,
    );
  }

  Future<void> updateDfxTransaction(DfxTransaction transaction) async {
    await updateTransaction(transaction);
    await _appDatabase.updateDfxTransactionDetails(
      txId: transaction.txId,
      dfxId: transaction.dfxId,
      rate: transaction.rate.toString(),
      inputTxId: transaction.inputTxId,
      outputTxId: transaction.outputTxId,
    );
  }

  Future<bool> existsTransaction(String txId) =>
      _appDatabase.getTransaction(txId).then((txData) => txData != null);

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
            category: TransferCategory.fromValue(txData.category),
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
          category: TransferCategory.fromValue(txData.category),
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
                  category: TransferCategory.fromValue(transactionData.category),
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
                  category: TransferCategory.fromValue(transactionData.category),
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
