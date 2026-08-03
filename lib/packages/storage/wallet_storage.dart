import 'package:drift/drift.dart';
import 'package:realunit_wallet/packages/storage/database.dart';

extension WalletStorage on AppDatabase {
  Future<int> insertWallet(String name, String seed, String address, int walletType) => into(
    walletInfos,
  ).insert(WalletInfosCompanion.insert(name: name, seed: seed, address: address, type: walletType));

  Future<WalletInfo?> getWalletById(int id) =>
      (select(walletInfos)..where((row) => row.id.equals(id))).getSingleOrNull();

  Future<WalletInfo?> getWalletByTypeAndAddress(int walletType, String address) =>
      (select(walletInfos)
            ..where((row) => row.type.equals(walletType) & row.address.equals(address))
            ..limit(1))
          .getSingleOrNull();

  Future<int> updateWalletAddress(int id, String address) => (update(
    walletInfos,
  )..where((row) => row.id.equals(id))).write(WalletInfosCompanion(address: Value(address)));

  Future<int> insertWalletAccount(int walletId, String name, int accountIndex) =>
      into(walletAccountInfos).insert(
        WalletAccountInfosCompanion.insert(
          name: name,
          accountIndex: accountIndex,
          wallet: walletId,
        ),
      );

  Future<List<WalletAccountInfo>> getWalletAccounts(int walletId) =>
      (select(walletAccountInfos)..where((row) => row.wallet.equals(walletId))).get();

  Future<int> deleteWallet(int walletId) =>
      (delete(walletAccountInfos)..where((row) => row.wallet.equals(walletId))).go();

  /// Deletes the `walletInfos` row itself (the encrypted-seed record) after
  /// clearing its dependent `walletAccountInfos` rows (FK in
  /// [WalletAccountInfos.wallet]).
  Future<void> deleteWalletCompletely(int walletId) => transaction(() async {
    await (delete(walletAccountInfos)..where((row) => row.wallet.equals(walletId))).go();
    await (delete(walletInfos)..where((row) => row.id.equals(walletId))).go();
  });

  Future<bool> get hasWallet => select(walletInfos).get().then((result) => result.isNotEmpty);
}

// The schema getters below are read by `drift_dev` at codegen time and the
// resulting column metadata is consumed via the generated mirror class —
// they are not invoked at runtime, so line-coverage instrumentation never
// marks them as executed. The same coverage gap exists on every Drift
// table in the repo. `// coverage:ignore-line` keeps the file at the
// surface the test suite can actually reach.
@DataClassName('WalletInfo')
class WalletInfos extends Table {
  IntColumn get id => integer().autoIncrement()(); // coverage:ignore-line

  TextColumn get name => text()(); // coverage:ignore-line

  TextColumn get seed => text()(); // coverage:ignore-line

  TextColumn get address => text()(); // coverage:ignore-line

  IntColumn get type => integer()(); // coverage:ignore-line
}

@DataClassName('WalletAccountInfo')
class WalletAccountInfos extends Table {
  IntColumn get id => integer().autoIncrement()(); // coverage:ignore-line

  TextColumn get name => text()(); // coverage:ignore-line

  IntColumn get accountIndex => integer()(); // coverage:ignore-line

  IntColumn get wallet => integer().references(WalletInfos, #id)(); // coverage:ignore-line
}
