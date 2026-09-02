import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/packages/storage/database.dart';
import 'package:realunit_wallet/packages/storage/transaction_storage.dart';
import 'package:realunit_wallet/packages/utils/fast_hash.dart';

void main() {
  // The high-level `TransactionRepository` is exhaustively tested in
  // `transaction_repository_test.dart`. This file only covers the
  // extension methods that the repository does not currently invoke,
  // so the static-only `transaction_storage.dart` API stays exercised.

  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('TransactionStorage extension', () {
    test(
      'getAllTokenTransactions filters by the hashed (chainId, address) asset id',
      () async {
        const chainId = 1;
        const address = '0x553C7f9C780316FC1D34b8e14ac2465Ab22a090B';
        final assetId = fastHash('$chainId:$address');

        // One matching row.
        await db.insertTransactions(
          1,
          'tx-match',
          chainId,
          '0xA',
          '0xB',
          '0xff',
          assetId,
          0,
          '',
          '',
          '',
          DateTime.utc(2025, 1, 1),
        );
        // One row for a different asset → must be excluded.
        await db.insertTransactions(
          2,
          'tx-other',
          chainId,
          '0xA',
          '0xB',
          '0xff',
          assetId + 1,
          0,
          '',
          '',
          '',
          DateTime.utc(2025, 1, 1),
        );

        final rows = await db.getAllTokenTransactions(chainId, address);
        expect(rows.map((r) => r.txId), ['tx-match']);
      },
    );

    test('getAllTokenTransactions returns an empty list when nothing matches', () async {
      final rows = await db.getAllTokenTransactions(
        1,
        '0x0000000000000000000000000000000000000000',
      );
      expect(rows, isEmpty);
    });
  });

  group('transfer filters match addresses case-insensitively', () {
    // The DFX API returns EIP-55 checksummed addresses which are stored
    // verbatim, while the query wallet is the lowercase primary address
    // (`AppStore.primaryAddress` → `.address.hex`). A case-sensitive `=` on
    // TEXT would never match and the whole transaction history renders empty.
    const checksummed = '0x553C7f9C780316FC1D34b8e14ac2465Ab22a090B';
    final walletLower = checksummed.toLowerCase();
    const chainId = 1;
    const assetAddress = '0xRealUnit';
    final assetId = fastHash('$chainId:$assetAddress');
    const other = '0x0000000000000000000000000000000000000001';

    Future<void> insert(
      String txId,
      String sender,
      String receiver,
      int type,
    ) => db.insertTransactions(
      1,
      txId,
      chainId,
      sender,
      receiver,
      '0xff',
      assetId,
      type,
      '',
      '',
      '',
      DateTime.utc(2025, 1, 1),
    );

    test('watchTransfersOfAssets matches a checksummed sender', () async {
      await insert('tx-sender', checksummed, other, 2);

      final rows = await db.watchTransfersOfAssets({assetId}, walletLower).first;

      expect(rows.map((r) => r.txId), ['tx-sender']);
    });

    test('persists the transfer category and defaults it to empty', () async {
      await db.insertTransactions(
        1,
        'tx-cat',
        chainId,
        checksummed,
        other,
        '0xff',
        assetId,
        2,
        'transferIn',
        '',
        '',
        DateTime.utc(2025, 1, 1),
      );

      final row = await db.getTransaction('tx-cat');
      expect(row!.category, 'transferIn');

      await insert('tx-nocat', checksummed, other, 2);
      final plain = await db.getTransaction('tx-nocat');
      expect(plain!.category, '');
    });

    test('watchTransfersOfAssets matches a checksummed receiver', () async {
      await insert('tx-receiver', other, checksummed, 2);

      final rows = await db.watchTransfersOfAssets({assetId}, walletLower).first;

      expect(rows.map((r) => r.txId), ['tx-receiver']);
    });

    test('watchTransfersOfAssetsLimit matches a checksummed address', () async {
      await insert('tx-limit', checksummed, other, 2);

      final rows = await db.watchTransfersOfAssetsLimit({assetId}, walletLower, 10).first;

      expect(rows.map((r) => r.txId), ['tx-limit']);
    });

    test('watchTransfersOfSavingsLimit matches a checksummed address', () async {
      // Savings uses transfer types 3 / 4.
      await insert('tx-savings', checksummed, other, 3);

      final rows = await db.watchTransfersOfSavingsLimit({assetId}, walletLower, 10).first;

      expect(rows.map((r) => r.txId), ['tx-savings']);
    });
  });
}
