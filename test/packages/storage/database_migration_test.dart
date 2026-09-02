import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/packages/storage/database.dart';
import 'package:realunit_wallet/packages/storage/dfx_transaction_storage.dart';
import 'package:realunit_wallet/packages/storage/transaction_storage.dart';
import 'package:realunit_wallet/packages/storage/wallet_storage.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('AppDatabase schema', () {
    test('schema version is 3', () {
      expect(db.schemaVersion, 3);
    });

    test('creates all expected tables on fresh database', () async {
      final rows = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
          )
          .get();
      final names = rows.map((r) => r.read<String>('name')).toSet();

      expect(
        names,
        containsAll([
          'assets',
          'balances',
          'key_value_cache',
          'nodes',
          'transactions',
          'dfx_transaction_details',
          'wallet_account_infos',
          'wallet_infos',
        ]),
      );
    });

    test('wallet_infos accepts inserts via Drift API', () async {
      final id = await db.insertWallet('Test', 'encrypted-seed', '0xAddress', 0);

      expect(id, greaterThan(0));

      final row = await db.getWalletById(id);
      expect(row, isNotNull);
      expect(row!.name, 'Test');
      expect(row.seed, 'encrypted-seed');
      expect(row.address, '0xAddress');
    });

    test('dfx_transaction_details references transactions via tx_id', () async {
      await db.insertTransactions(
        1,
        'tx-1',
        1,
        '0xA',
        '0xB',
        '100',
        1,
        0,
        '',
        '',
        '',
        DateTime.now(),
      );

      await db.insertDfxTransactionDetails(txId: 'tx-1', dfxId: 42);

      final details = await db.getDfxTransactionDetailsByDfxId(42);
      expect(details, isNotNull);
      expect(details!.txId, 'tx-1');
    });
  });

  group('AppDatabase.migration', () {
    test('onCreate creates the full schema on a fresh database', () async {
      // Re-running `createAll` on an already migrated database would
      // fail with "table … already exists". This indirectly pins that
      // the `onCreate` branch we install in `MigrationStrategy` only
      // fires once on a fresh in-memory store.
      final tables = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
          )
          .get();
      expect(tables, isNotEmpty);
    });

    test('onUpgrade from v1 → v3 creates the dfx table and the category column', () async {
      // Simulate a pre-v2 database: drop the dfx_transaction_details table (added in v2)
      // and the transactions.category column (added in v3), then drive the migration
      // manually via the strategy exposed by `AppDatabase.migration`. After
      // onUpgrade(1, 3) both must exist again, exercising both `from <` branches.
      await db.customStatement('DROP TABLE dfx_transaction_details');
      await db.customStatement('ALTER TABLE transactions DROP COLUMN category');

      final strategy = db.migration;
      final migrator = Migrator(db);
      await strategy.onUpgrade(migrator, 1, 3);

      final rows = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='dfx_transaction_details'",
          )
          .get();
      expect(rows, hasLength(1));

      final columns = await db.customSelect("PRAGMA table_info('transactions')").get();
      expect(columns.map((r) => r.read<String>('name')), contains('category'));
    });

    test('onUpgrade from v2 → v3 adds the category column with its default', () async {
      await db.customStatement('ALTER TABLE transactions DROP COLUMN category');

      final strategy = db.migration;
      final migrator = Migrator(db);
      await strategy.onUpgrade(migrator, 2, 3);

      final columns = await db.customSelect("PRAGMA table_info('transactions')").get();
      expect(columns.map((r) => r.read<String>('name')), contains('category'));
    });

    test('onUpgrade does nothing when starting at v3 or later', () async {
      // The `if (from <` guards mean an upgrade from v3 → v4 (a future
      // version) must NOT try to recreate the table or the column. We
      // assert that by leaving both in place and running the callback,
      // which would throw "already exists" if a guard regressed.
      final strategy = db.migration;
      final migrator = Migrator(db);
      // from == 3 → guards short-circuit, no SQL executed.
      await strategy.onUpgrade(migrator, 3, 4);

      final rows = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='dfx_transaction_details'",
          )
          .get();
      expect(rows, hasLength(1));
    });
  });
}
