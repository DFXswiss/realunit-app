import 'package:drift/drift.dart';
import 'package:realunit_wallet/packages/storage/database.dart';
import 'package:realunit_wallet/packages/storage/transaction_storage.dart';

extension DfxTransactionStorage on AppDatabase {
  Future<int> insertDfxTransactionDetails({
    required String txId,
    required int dfxId,
    String? rate,
    String? inputTxId,
    String? outputTxId,
  }) => into(dfxTransactionDetails).insert(
    DfxTransactionDetailsCompanion.insert(
      txId: txId,
      dfxId: dfxId,
      rate: Value.absentIfNull(rate),
      inputTxId: Value.absentIfNull(inputTxId),
      outputTxId: Value.absentIfNull(outputTxId),
    ),
  );

  Future<int> updateDfxTransactionDetails({
    required String txId,
    int? dfxId,
    String? rate,
    String? inputTxId,
    String? outputTxId,
  }) => (update(dfxTransactionDetails)..where((row) => row.txId.equals(txId))).write(
    DfxTransactionDetailsCompanion(
      dfxId: Value.absentIfNull(dfxId),
      rate: Value.absentIfNull(rate),
      inputTxId: Value.absentIfNull(inputTxId),
      outputTxId: Value.absentIfNull(outputTxId),
    ),
  );

  Future<DfxTransactionDetailsData?> getDfxTransactionDetails(String txId) =>
      (select(dfxTransactionDetails)..where((row) => row.txId.equals(txId))).getSingleOrNull();

  Future<DfxTransactionDetailsData?> getDfxTransactionDetailsByDfxId(int dfxId) =>
      (select(dfxTransactionDetails)..where((row) => row.dfxId.equals(dfxId))).getSingleOrNull();

  Stream<List<DfxTransactionDetailsData>> watchDfxTransactionDetails() =>
      select(dfxTransactionDetails).watch();

  Future<List<DfxTransactionDetailsData>> get allDfxTransactionDetails =>
      dfxTransactionDetails.all().get();

  Future<int> deleteDfxTransactionDetails(String txId) =>
      (delete(dfxTransactionDetails)..where((row) => row.txId.equals(txId))).go();

  /// Hex hashes are stored as the API sent them. Drop Beleg metadata for a
  /// prize even when the payout hash casing differs from the history row.
  Future<int> deleteDfxTransactionDetailsIgnoreCase(String txId) async {
    final rows = await (select(
      dfxTransactionDetails,
    )..where((row) => row.txId.collate(Collate.noCase).equals(txId))).get();
    if (rows.isEmpty) return 0;
    var n = 0;
    for (final row in rows) {
      n += await deleteDfxTransactionDetails(row.txId);
    }
    return n;
  }
}

// The schema getters below are read by `drift_dev` at codegen time and the
// resulting column metadata is consumed via the generated mirror class —
// they are not invoked at runtime, so line-coverage instrumentation never
// marks them as executed. The same coverage gap exists on every Drift
// table in the repo. `// coverage:ignore-line` keeps the file at the
// surface the test suite can actually reach.
@DataClassName('DfxTransactionDetailsData')
class DfxTransactionDetails extends Table {
  TextColumn get txId => text().unique().references(Transactions, #txId)(); // coverage:ignore-line

  IntColumn get dfxId => integer().unique()(); // coverage:ignore-line

  TextColumn get rate => text().nullable()(); // coverage:ignore-line

  TextColumn get inputTxId => text().nullable()(); // coverage:ignore-line

  TextColumn get outputTxId => text().nullable()(); // coverage:ignore-line
}
