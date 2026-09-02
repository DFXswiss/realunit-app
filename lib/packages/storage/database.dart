import 'dart:developer';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:realunit_wallet/packages/io/backup_exclusion_adapter.dart';
import 'package:realunit_wallet/packages/io/backup_exclusion_port.dart';
import 'package:realunit_wallet/packages/io/documents_directory_port.dart';
import 'package:realunit_wallet/packages/io/path_provider_adapter.dart';
import 'package:realunit_wallet/packages/storage/asset_storage.dart';
import 'package:realunit_wallet/packages/storage/balance_storage.dart';
import 'package:realunit_wallet/packages/storage/dfx_transaction_storage.dart';
import 'package:realunit_wallet/packages/storage/key_value_cache.dart';
import 'package:realunit_wallet/packages/storage/node_storage.dart';
import 'package:realunit_wallet/packages/storage/transaction_storage.dart';
import 'package:realunit_wallet/packages/storage/wallet_storage.dart';

part 'database.g.dart';

const _databaseFileName = 'wallet.db.enc';

// `tryOpeningDatabase` constructs the production AppDatabase, which goes
// through `_openDatabase` → SQLCipher + path_provider. Neither is available
// under `flutter test`, so this function cannot be exercised in unit tests;
// it is covered by the integration / device test layer.
// coverage:ignore-start
Future<bool> tryOpeningDatabase(String encryptionPassword) async {
  final database = AppDatabase(encryptionPassword);
  try {
    await database.select(database.assets).get();
    await database.close();
    return true;
  } on SqliteException catch (e) {
    log('SqliteException', error: e, name: 'AppDatabase tryOpeningDatabase');
    if (e.resultCode == 26) {
      log('Wrong Pin', error: e, name: 'AppDatabase tryOpeningDatabase');
    }
  } catch (e) {
    log('Unexpected Error', error: e, name: 'AppDatabase tryOpeningDatabase');
  } finally {
    await database.close();
  }
  return false;
}
// coverage:ignore-end

@DriftDatabase(
  tables: [
    Assets,
    Balances,
    KeyValueCache,
    Nodes,
    Transactions,
    DfxTransactionDetails,
    WalletAccountInfos,
    WalletInfos,
  ],
)
class AppDatabase extends _$AppDatabase {
  // Production constructor — opens the on-disk SQLCipher database. Only
  // reachable from the embedder; tests use `AppDatabase.forTesting`.
  // coverage:ignore-start
  AppDatabase(String encryptionPassword) : super(_openDatabase(encryptionPassword));
  // coverage:ignore-end

  /// In-memory database for unit tests. Bypasses SQLCipher and path_provider.
  @visibleForTesting
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2) {
        await m.createTable(dfxTransactionDetails);
      }
      if (from < 3) {
        await m.addColumn(transactions, transactions.category);
      }
    },
  );

  /// Resolves the on-disk path of the SQLCipher database file.
  ///
  /// Routes through [DocumentsDirectoryPort] so unit tests can substitute a
  /// writable temp-dir fake instead of going through `path_provider`'s
  /// platform channel (which has no in-process implementation under
  /// `flutter test`). Production calls pass nothing; the
  /// [PathProviderAdapter] default forwards 1:1 to
  /// `path_provider.getApplicationDocumentsDirectory`, so runtime behaviour
  /// is unchanged.
  static Future<String> getDatabasePath([
    DocumentsDirectoryPort directory = const PathProviderAdapter(),
  ]) async {
    final path = await directory.getApplicationDocumentsDirectory();
    return p.join(path.path, _databaseFileName);
  }

  /// Excludes the SQLCipher database (and its SQLite `-wal` / `-shm` /
  /// `-journal` sidecars) from the iOS device backup so the encrypted seed is
  /// never uploaded to iCloud. Fixes #298 (NEW-20).
  ///
  /// The file stays at its current path in `Documents/` — excluding it in place
  /// via `NSURLIsExcludedFromBackupKey` (the native side of
  /// [BackupExclusionPort]) avoids moving a wallet-bearing file and the
  /// migration risk that carries (the earlier move-based #293 was closed
  /// unmerged; a lost DB during a move would lose the user's wallet). Note that
  /// `Library/Application Support/` is itself backed up by default, so the move
  /// alone would not have excluded it anyway.
  ///
  /// No-op on Android (backup already disabled via
  /// `android:allowBackup="false"`) and on any non-iOS platform. Idempotent, so
  /// callers invoke it on every launch after the DB is opened; sidecars that do
  /// not exist yet are silently skipped by the platform implementation.
  static Future<void> excludeDatabaseFromBackup([
    BackupExclusionPort exclusion = const BackupExclusionAdapter(),
    DocumentsDirectoryPort directory = const PathProviderAdapter(),
  ]) async {
    final dbPath = await getDatabasePath(directory);
    await exclusion.excludeFromBackup([
      dbPath,
      '$dbPath-wal',
      '$dbPath-shm',
      '$dbPath-journal',
    ]);
  }
}

// coverage:ignore-start
QueryExecutor _openDatabase(String encryptionPassword) {
  return LazyDatabase(() async {
    final path = await AppDatabase.getDatabasePath();

    return NativeDatabase.createInBackground(
      File(path),
      setup: (db) {
        final escapedKey = encryptionPassword.replaceAll("'", "''");
        db.execute("pragma cipher = 'sqlcipher'");
        db.execute('pragma legacy = 4');
        db.execute("pragma key = '$escapedKey'");
        db.execute('select count(*) from sqlite_master');
      },
    );
  });
}

// coverage:ignore-end
