import 'package:drift/drift.dart';
import 'package:realunit_wallet/packages/storage/database.dart';
import 'package:realunit_wallet/packages/utils/fast_hash.dart';

extension TransactionStorage on AppDatabase {
  Future<int> insertTransactions(
    int height,
    String txId,
    int chainId,
    String senderAddress,
    String receiverAddress,
    String amount,
    int asset,
    int type,
    String category,
    String note,
    String data,
    DateTime timeStamp,
  ) => into(transactions).insert(
    TransactionsCompanion.insert(
      height: height,
      txId: txId,
      chainId: chainId,
      senderAddress: senderAddress,
      receiverAddress: receiverAddress,
      amount: amount,
      asset: asset,
      type: type,
      category: Value(category),
      note: note,
      data: data,
      timeStamp: timeStamp,
    ),
  );

  Future<int> updateTransaction(
    String txId, {
    int? height,
    int? chainId,
    String? senderAddress,
    String? receiverAddress,
    String? amount,
    int? asset,
    int? type,
    String? category,
    String? note,
    String? data,
    DateTime? timeStamp,
  }) => (update(transactions)..where((row) => row.txId.equals(txId))).write(
    TransactionsCompanion(
      height: Value.absentIfNull(height),
      chainId: Value.absentIfNull(chainId),
      senderAddress: Value.absentIfNull(senderAddress),
      receiverAddress: Value.absentIfNull(receiverAddress),
      amount: Value.absentIfNull(amount),
      asset: Value.absentIfNull(asset),
      type: Value.absentIfNull(type),
      category: Value.absentIfNull(category),
      note: Value.absentIfNull(note),
      data: Value.absentIfNull(data),
      timeStamp: Value.absentIfNull(timeStamp),
    ),
  );

  Future<List<TransactionData>> getAllTokenTransactions(int chainId, String address) =>
      (select(transactions)..where((row) => row.asset.equals(fastHash('$chainId:$address')))).get();

  Future<List<TransactionData>> get allTransactions => (select(
    transactions,
  )..orderBy([(u) => OrderingTerm(expression: u.timeStamp, mode: OrderingMode.desc)])).get();

  Stream<List<TransactionData>> watchTransactions() => (select(
    transactions,
  )..orderBy([(u) => OrderingTerm(expression: u.timeStamp, mode: OrderingMode.desc)])).watch();

  // EVM addresses are stored verbatim from the API (EIP-55 mixed case) while
  // `wallet` is lowercase — compare case-insensitively or history renders empty.
  Expression<bool> _involvesWallet($TransactionsTable row, String wallet) => Expression.or([
    row.senderAddress.collate(Collate.noCase).equals(wallet),
    row.receiverAddress.collate(Collate.noCase).equals(wallet),
  ]);

  Stream<List<TransactionData>> watchTransfersOfAssets(Iterable<int> assets, String wallet) =>
      (select(transactions)
            ..where(
              (row) => Expression.and([
                row.asset.isIn(assets),
                row.type.equals(2),
                _involvesWallet(row, wallet),
              ]),
            )
            ..orderBy([(u) => OrderingTerm(expression: u.timeStamp, mode: OrderingMode.desc)]))
          .watch();

  Stream<List<TransactionData>> watchTransfersOfAssetsLimit(
    Iterable<int> assets,
    String wallet,
    int limit,
  ) =>
      (select(transactions)
            ..where(
              (row) => Expression.and([
                row.asset.isIn(assets),
                row.type.equals(2),
                _involvesWallet(row, wallet),
              ]),
            )
            ..orderBy([(u) => OrderingTerm(expression: u.timeStamp, mode: OrderingMode.desc)])
            ..limit(limit))
          .watch();

  Stream<List<TransactionData>> watchTransfersOfSavingsLimit(
    Iterable<int> assets,
    String wallet,
    int limit,
  ) =>
      (select(transactions)
            ..where(
              (row) => Expression.and([
                row.asset.isIn(assets),
                row.type.isIn([3, 4]),
                _involvesWallet(row, wallet),
              ]),
            )
            ..orderBy([(u) => OrderingTerm(expression: u.timeStamp, mode: OrderingMode.desc)])
            ..limit(limit))
          .watch();

  Future<List<TransactionData>> getLatestTransactions({int limit = 1}) =>
      (select(transactions)
            ..orderBy([(u) => OrderingTerm(expression: u.timeStamp, mode: OrderingMode.desc)])
            ..limit(limit))
          .get();

  Future<TransactionData?> getTransaction(String txId) =>
      (select(transactions)..where((row) => row.txId.equals(txId))).getSingleOrNull();
}

// The schema getters below are read by `drift_dev` at codegen time and the
// resulting column metadata is consumed via the generated mirror class —
// they are not invoked at runtime, so line-coverage instrumentation never
// marks them as executed. The same coverage gap exists on every Drift
// table in the repo. `// coverage:ignore-line` keeps the file at the
// surface the test suite can actually reach.
@DataClassName('TransactionData')
class Transactions extends Table {
  IntColumn get height => integer()(); // coverage:ignore-line

  TextColumn get txId => text().unique()(); // coverage:ignore-line

  IntColumn get chainId => integer()(); // coverage:ignore-line

  TextColumn get senderAddress => text()(); // coverage:ignore-line

  TextColumn get receiverAddress => text()(); // coverage:ignore-line

  TextColumn get amount => text()(); // coverage:ignore-line

  IntColumn get asset => integer()(); // coverage:ignore-line

  IntColumn get type => integer()(); // coverage:ignore-line

  // Business category of the transfer as delivered by the API ('' = uncategorized, legacy
  // rows and events without a category). Added in schema v3.
  TextColumn get category => text().withDefault(const Constant(''))(); // coverage:ignore-line

  TextColumn get note => text()(); // coverage:ignore-line

  TextColumn get data => text()(); // coverage:ignore-line

  DateTimeColumn get timeStamp => dateTime()(); // coverage:ignore-line
}
