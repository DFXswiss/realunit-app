import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/packages/storage/database.dart';
import 'package:realunit_wallet/packages/storage/dfx_transaction_storage.dart';
import 'package:realunit_wallet/packages/storage/transaction_storage.dart';

void main() {
  late AppDatabase db;

  Future<void> seedTx(String txId, {int height = 1}) => db.insertTransactions(
    height,
    txId,
    1,
    '0xA',
    '0xB',
    '0xff',
    1,
    0,
    '',
    '',
    '',
    DateTime.utc(2025, 1, 1),
  );

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('DfxTransactionStorage extension', () {
    test(
      'insertDfxTransactionDetails persists the row and updateDfxTransactionDetails mutates it',
      () async {
        await seedTx('tx-1');

        final rowId = await db.insertDfxTransactionDetails(
          txId: 'tx-1',
          dfxId: 7,
          rate: '1.25',
          inputTxId: 'in-1',
          outputTxId: 'out-1',
        );
        expect(rowId, greaterThan(0));

        final affected = await db.updateDfxTransactionDetails(
          txId: 'tx-1',
          rate: '2.5',
          inputTxId: 'in-2',
        );
        expect(affected, 1);

        final fetched = await db.getDfxTransactionDetails('tx-1');
        expect(fetched, isNotNull);
        expect(fetched!.dfxId, 7);
        expect(fetched.rate, '2.5');
        expect(fetched.inputTxId, 'in-2');
        // updateDfxTransactionDetails uses Value.absentIfNull, so outputTxId
        // stays at its previous value when omitted.
        expect(fetched.outputTxId, 'out-1');
      },
    );

    test('getDfxTransactionDetails returns null for an unknown txId', () async {
      expect(await db.getDfxTransactionDetails('nope'), isNull);
    });

    test('getDfxTransactionDetailsByDfxId looks up by the DFX id', () async {
      await seedTx('tx-1');
      await db.insertDfxTransactionDetails(txId: 'tx-1', dfxId: 42);

      final fetched = await db.getDfxTransactionDetailsByDfxId(42);
      expect(fetched, isNotNull);
      expect(fetched!.txId, 'tx-1');

      expect(await db.getDfxTransactionDetailsByDfxId(9999), isNull);
    });

    test('allDfxTransactionDetails lists every inserted row', () async {
      await seedTx('tx-1', height: 1);
      await seedTx('tx-2', height: 2);
      await db.insertDfxTransactionDetails(txId: 'tx-1', dfxId: 1);
      await db.insertDfxTransactionDetails(txId: 'tx-2', dfxId: 2);

      final all = await db.allDfxTransactionDetails;
      expect(all, hasLength(2));
      expect(all.map((d) => d.txId).toSet(), {'tx-1', 'tx-2'});
    });

    test('watchDfxTransactionDetails emits the latest snapshot after each insert', () async {
      await seedTx('tx-1');

      // expectLater drives the broadcast stream deterministically: it
      // pumps the event queue until a snapshot matching our predicate
      // (`dfxId == 99`) is observed. No wall-clock delay is needed.
      final settled = expectLater(
        db.watchDfxTransactionDetails(),
        emitsThrough(
          predicate<List<DfxTransactionDetailsData>>(
            (rows) => rows.length == 1 && rows.single.dfxId == 99,
          ),
        ),
      );

      await db.insertDfxTransactionDetails(txId: 'tx-1', dfxId: 99);
      await settled;
    });
  });
}
