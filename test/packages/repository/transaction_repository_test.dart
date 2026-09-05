import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/models/asset.dart';
import 'package:realunit_wallet/models/blockchain.dart';
import 'package:realunit_wallet/models/dfx_transaction.dart';
import 'package:realunit_wallet/models/transaction.dart';
import 'package:realunit_wallet/packages/repository/asset_repository.dart';
import 'package:realunit_wallet/packages/repository/transaction_repository.dart';
import 'package:realunit_wallet/packages/storage/database.dart';
import 'package:realunit_wallet/packages/storage/dfx_transaction_storage.dart';

void main() {
  late AppDatabase db;
  late AssetRepository assetRepository;
  late TransactionRepository repo;

  // Use the same chainId values Blockchain knows about — the transformer
  // calls `Blockchain.getFromChainId(...)` which throws on unknown ids.
  const tokenAssetMainnet = Asset(
    chainId: 1,
    address: '0x553C7f9C780316FC1D34b8e14ac2465Ab22a090B',
    name: 'RealUnit Token',
    symbol: 'REALU',
    decimals: 0,
  );

  const tokenAssetSepolia = Asset(
    chainId: 11155111,
    address: '0x0add9824820508dd7992cbebb9f13fbe8e45a30f',
    name: 'RealUnit Token (Sepolia)',
    symbol: 'REALU',
    decimals: 0,
  );

  const sender = '0x1111111111111111111111111111111111111111';
  const receiver = '0x2222222222222222222222222222222222222222';

  Transaction buildTokenTransfer({
    required String txId,
    required int height,
    DateTime? timestamp,
    int chainId = 1,
    BigInt? amount,
    Asset? asset,
    TransactionTypes type = TransactionTypes.tokenTransfer,
    String? note,
    String? data,
    String? senderOverride,
    String? receiverOverride,
  }) {
    return Transaction(
      height: height,
      txId: txId,
      chainId: chainId,
      senderAddress: senderOverride ?? sender,
      receiverAddress: receiverOverride ?? receiver,
      amount: amount ?? BigInt.from(0xff),
      asset: asset ?? tokenAssetMainnet,
      type: type,
      note: note,
      data: data,
      timestamp: timestamp ?? DateTime.utc(2025, 1, 1),
    );
  }

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    assetRepository = AssetRepository(db);
    repo = TransactionRepository(db, assetRepository);

    // Seed the assets table so the transformer's `firstWhere` path finds
    // a real Asset for every token transfer we insert. Without this it
    // would fall through to the `orElse: Unknown` branch — which we
    // cover separately below.
    await assetRepository.insertAsset(tokenAssetMainnet);
    await assetRepository.insertAsset(tokenAssetSepolia);
  });

  tearDown(() async {
    await db.close();
  });

  group('$TransactionRepository', () {
    test('getLatestHeight returns 0 on an empty database', () async {
      expect(await repo.getLatestHeight(), 0);
    });

    test('getLatestHeight returns the height of the most recent transaction', () async {
      await repo.insertTransaction(
        buildTokenTransfer(
          txId: 'tx-1',
          height: 100,
          timestamp: DateTime.utc(2025, 1, 1),
        ),
      );
      await repo.insertTransaction(
        buildTokenTransfer(
          txId: 'tx-2',
          height: 200,
          timestamp: DateTime.utc(2025, 1, 2),
        ),
      );

      expect(await repo.getLatestHeight(), 200);
    });

    test('insertTransaction hex-encodes the amount and persists the row', () async {
      final tx = buildTokenTransfer(
        txId: 'tx-1',
        height: 1,
        amount: BigInt.from(0xdead),
        note: 'hello',
        data: 'world',
      );

      final rowId = await repo.insertTransaction(tx);
      expect(rowId, greaterThan(0));

      expect(await repo.existsTransaction('tx-1'), isTrue);

      final all = await repo.allTransactions;
      expect(all, hasLength(1));
      expect(all.single.txId, 'tx-1');
      // Round-trip: amount must decode back to the original BigInt.
      expect(all.single.amount, BigInt.from(0xdead));
      expect(all.single.note, 'hello');
      expect(all.single.data, 'world');
    });

    test(
      'insertTransaction stores null note/data as empty strings (the schema is NOT NULL)',
      () async {
        // The repository explicitly maps `note ?? ''` and `data ?? ''`
        // because the schema columns are NOT NULL. If that mapping ever
        // regresses the insert would fail; this pins the contract.
        final tx = buildTokenTransfer(txId: 'tx-null', height: 1);

        await repo.insertTransaction(tx);

        final all = await repo.allTransactions;
        expect(all.single.note, '');
        expect(all.single.data, '');
      },
    );

    test(
      'insertTransaction writes a prize onto a mixed-case stored hash instead of a second row',
      () async {
        await repo.insertTransaction(
          buildTokenTransfer(txId: '0xAbC', height: 1),
        );

        expect(
          await repo.insertTransaction(
            buildTokenTransfer(
              txId: '0xabc',
              height: 1,
              type: TransactionTypes.referralPayout,
              data: '246.50',
            ),
          ),
          1,
        );

        final all = await repo.allTransactions;
        expect(all, hasLength(1));
        expect(all.single.txId, '0xAbC');
        expect(all.single.type, TransactionTypes.referralPayout);
        expect(all.single.data, '246.50');
      },
    );

    test('updateTransaction mutates the row identified by txId', () async {
      await repo.insertTransaction(
        buildTokenTransfer(txId: 'tx-1', height: 1, amount: BigInt.from(1)),
      );

      await repo.updateTransaction(
        buildTokenTransfer(
          txId: 'tx-1',
          height: 2,
          amount: BigInt.from(0x10),
          note: 'updated',
        ),
      );

      final all = await repo.allTransactions;
      expect(all, hasLength(1));
      expect(all.single.height, 2);
      expect(all.single.amount, BigInt.from(0x10));
      expect(all.single.note, 'updated');
    });

    test(
      'updateTransaction writes a prize onto a mixed-case stored hash',
      () async {
        await repo.insertTransaction(
          buildTokenTransfer(txId: '0xAbC', height: 1),
        );

        expect(
          await repo.updateTransaction(
            buildTokenTransfer(
              txId: '0xabc',
              height: 1,
              type: TransactionTypes.referralPayout,
              data: '246.50',
            ),
          ),
          1,
        );

        final all = await repo.allTransactions;
        expect(all, hasLength(1));
        expect(all.single.txId, '0xAbC');
        expect(all.single.type, TransactionTypes.referralPayout);
        expect(all.single.data, '246.50');
      },
    );

    test('existsTransaction returns false for an unknown txId', () async {
      expect(await repo.existsTransaction('nope'), isFalse);
    });

    test('findTxIdIgnoreCase returns the stored casing of a hex hash', () async {
      await repo.insertTransaction(
        buildTokenTransfer(txId: '0xAbC', height: 1),
      );

      expect(await repo.findTxIdIgnoreCase('0xabc'), '0xAbC');
      expect(await repo.findTxIdIgnoreCase('0xABC'), '0xAbC');
      expect(await repo.findTxIdIgnoreCase('0xAbC'), '0xAbC');
      expect(await repo.findTxIdIgnoreCase('0xdef'), isNull);
    });

    test('isReferralPayoutIgnoreCase is true only for stored prize rows', () async {
      await repo.insertTransaction(
        buildTokenTransfer(
          txId: '0xAbC',
          height: 1,
          type: TransactionTypes.referralPayout,
          data: '246.50',
        ),
      );
      await repo.insertTransaction(
        buildTokenTransfer(txId: '0xdef', height: 2),
      );

      expect(await repo.isReferralPayoutIgnoreCase('0xabc'), isTrue);
      expect(await repo.isReferralPayoutIgnoreCase('0xDEF'), isFalse);
      expect(await repo.isReferralPayoutIgnoreCase('0xmissing'), isFalse);
    });

    test('deleteTransaction removes the row so a hashed prize can replace it', () async {
      await repo.insertTransaction(
        buildTokenTransfer(txId: 'referral-payout-9', height: 1),
      );
      expect(await repo.existsTransaction('referral-payout-9'), isTrue);

      expect(await repo.deleteTransaction('referral-payout-9'), 1);
      expect(await repo.existsTransaction('referral-payout-9'), isFalse);
    });

    test(
      'deleteTransaction drops leftover DFX Beleg details so SQLite FK cannot block the leftover synthetic delete',
      () async {
        final dfxTx = DfxTransaction(
          dfxId: 42,
          rate: 1.38,
          height: 1,
          txId: 'referral-payout-9',
          chainId: 1,
          senderAddress: sender,
          receiverAddress: receiver,
          amount: BigInt.from(20),
          asset: tokenAssetMainnet,
          type: TransactionTypes.tokenTransfer,
          note: null,
          data: null,
          timestamp: DateTime.utc(2026, 8, 24),
        );
        await repo.insertDfxTransaction(dfxTx);

        expect(await repo.deleteTransaction('referral-payout-9'), 1);
        expect(await repo.existsTransaction('referral-payout-9'), isFalse);
        expect(await repo.allTransactions, isEmpty);
        expect(await db.allDfxTransactionDetails, isEmpty);
      },
    );

    test(
      'deleteTransaction matches a mixed-case leftover hash and drops its Beleg details',
      () async {
        final dfxTx = DfxTransaction(
          dfxId: 7,
          rate: 1.25,
          height: 1,
          txId: '0xAbC',
          chainId: 1,
          senderAddress: sender,
          receiverAddress: receiver,
          amount: BigInt.from(20),
          asset: tokenAssetMainnet,
          type: TransactionTypes.tokenTransfer,
          note: null,
          data: null,
          timestamp: DateTime.utc(2026, 8, 24),
        );
        await repo.insertDfxTransaction(dfxTx);

        expect(await repo.deleteTransaction('0xabc'), 1);
        expect(await repo.existsTransaction('0xAbC'), isFalse);
        expect(await repo.allTransactions, isEmpty);
        expect(await db.allDfxTransactionDetails, isEmpty);
      },
    );

    test('insertDfxTransaction updates the DFX details when they already exist', () async {
      DfxTransaction dfx(int dfxId, double rate) => DfxTransaction(
        dfxId: dfxId,
        rate: rate,
        inputTxId: 'in-$dfxId',
        outputTxId: 'out-$dfxId',
        height: 1,
        txId: 'tx-dfx-existing',
        chainId: 1,
        senderAddress: sender,
        receiverAddress: receiver,
        amount: BigInt.from(0x100),
        asset: tokenAssetMainnet,
        type: TransactionTypes.tokenTransfer,
        note: null,
        data: null,
        timestamp: DateTime.utc(2025, 1, 1),
      );

      await repo.insertDfxTransaction(dfx(1, 1.0));
      await repo.insertDfxTransaction(dfx(2, 2.5));

      final fetched = (await repo.allTransactions).single as DfxTransaction;
      expect(fetched.dfxId, 2);
      expect(fetched.rate, 2.5);
      expect(fetched.inputTxId, 'in-2');
      expect(fetched.outputTxId, 'out-2');
    });

    test('insertDfxTransaction writes both the transaction row and its DFX details', () async {
      final dfxTx = DfxTransaction(
        dfxId: 42,
        rate: 1.25,
        inputTxId: 'input-1',
        outputTxId: 'output-1',
        height: 1,
        txId: 'tx-dfx',
        chainId: 1,
        senderAddress: sender,
        receiverAddress: receiver,
        amount: BigInt.from(0x100),
        asset: tokenAssetMainnet,
        type: TransactionTypes.tokenTransfer,
        note: null,
        data: null,
        timestamp: DateTime.utc(2025, 1, 1),
      );

      await repo.insertDfxTransaction(dfxTx);

      expect(await repo.existsTransaction('tx-dfx'), isTrue);

      final all = await repo.allTransactions;
      expect(all, hasLength(1));
      final fetched = all.single;
      expect(fetched, isA<DfxTransaction>());
      final fetchedDfx = fetched as DfxTransaction;
      expect(fetchedDfx.dfxId, 42);
      expect(fetchedDfx.rate, 1.25);
      expect(fetchedDfx.inputTxId, 'input-1');
      expect(fetchedDfx.outputTxId, 'output-1');
    });

    test(
      'insertDfxTransaction attaches Beleg details to a mixed-case stored hash',
      () async {
        await repo.insertTransaction(
          buildTokenTransfer(txId: '0xAbC', height: 1),
        );

        await repo.insertDfxTransaction(
          DfxTransaction(
            dfxId: 42,
            rate: 1.25,
            inputTxId: 'input-1',
            outputTxId: 'output-1',
            height: 1,
            txId: '0xabc',
            chainId: 1,
            senderAddress: sender,
            receiverAddress: receiver,
            amount: BigInt.from(0x100),
            asset: tokenAssetMainnet,
            type: TransactionTypes.tokenTransfer,
            note: null,
            data: null,
            timestamp: DateTime.utc(2025, 1, 1),
          ),
        );

        final all = await repo.allTransactions;
        expect(all, hasLength(1));
        expect(all.single.txId, '0xAbC');
        expect(all.single, isA<DfxTransaction>());
        expect((all.single as DfxTransaction).dfxId, 42);
        final details = await db.allDfxTransactionDetails;
        expect(details, hasLength(1));
        expect(details.single.txId, '0xAbC');
      },
    );

    test(
      'deleteDfxTransactionDetailsIgnoreCase leaves a prize as a plain row',
      () async {
        final dfxTx = DfxTransaction(
          dfxId: 42,
          rate: 1.38,
          height: 1,
          txId: '0xAbC',
          chainId: 1,
          senderAddress: sender,
          receiverAddress: receiver,
          amount: BigInt.from(20),
          asset: tokenAssetMainnet,
          type: TransactionTypes.tokenTransfer,
          note: null,
          data: null,
          timestamp: DateTime.utc(2026, 8, 24),
        );
        await repo.insertDfxTransaction(dfxTx);
        await repo.updateTransaction(
          buildTokenTransfer(
            txId: '0xAbC',
            height: 1,
            type: TransactionTypes.referralPayout,
            data: '246.50',
          ),
        );

        expect(await repo.deleteDfxTransactionDetailsIgnoreCase('0xabc'), 1);

        final all = await repo.allTransactions;
        expect(all, hasLength(1));
        expect(all.single, isNot(isA<DfxTransaction>()));
        expect(all.single.type, TransactionTypes.referralPayout);
        expect(all.single.data, '246.50');
      },
    );

    test('updateDfxTransaction overwrites the DFX details for an existing tx', () async {
      final original = DfxTransaction(
        dfxId: 42,
        rate: 1.25,
        inputTxId: 'input-1',
        outputTxId: 'output-1',
        height: 1,
        txId: 'tx-dfx',
        chainId: 1,
        senderAddress: sender,
        receiverAddress: receiver,
        amount: BigInt.from(0x100),
        asset: tokenAssetMainnet,
        type: TransactionTypes.tokenTransfer,
        note: null,
        data: null,
        timestamp: DateTime.utc(2025, 1, 1),
      );

      await repo.insertDfxTransaction(original);

      final updated = DfxTransaction(
        dfxId: 42,
        rate: 2.5,
        inputTxId: 'input-2',
        outputTxId: 'output-2',
        height: 2,
        txId: 'tx-dfx',
        chainId: 1,
        senderAddress: sender,
        receiverAddress: receiver,
        amount: BigInt.from(0x200),
        asset: tokenAssetMainnet,
        type: TransactionTypes.tokenTransfer,
        note: 'updated',
        data: null,
        timestamp: DateTime.utc(2025, 1, 2),
      );

      await repo.updateDfxTransaction(updated);

      final all = await repo.allTransactions;
      expect(all, hasLength(1));
      final fetched = all.single as DfxTransaction;
      expect(fetched.height, 2);
      expect(fetched.amount, BigInt.from(0x200));
      expect(fetched.rate, 2.5);
      expect(fetched.inputTxId, 'input-2');
      expect(fetched.outputTxId, 'output-2');
      expect(fetched.note, 'updated');
    });

    test(
      'updateDfxTransaction matches a mixed-case leftover Beleg hash',
      () async {
        final original = DfxTransaction(
          dfxId: 42,
          rate: 1.25,
          inputTxId: 'input-1',
          outputTxId: 'output-1',
          height: 1,
          txId: '0xAbC',
          chainId: 1,
          senderAddress: sender,
          receiverAddress: receiver,
          amount: BigInt.from(0x100),
          asset: tokenAssetMainnet,
          type: TransactionTypes.tokenTransfer,
          note: null,
          data: null,
          timestamp: DateTime.utc(2025, 1, 1),
        );
        await repo.insertDfxTransaction(original);

        await repo.updateDfxTransaction(
          DfxTransaction(
            dfxId: 42,
            rate: 2.5,
            inputTxId: 'input-2',
            outputTxId: 'output-2',
            height: 2,
            txId: '0xabc',
            chainId: 1,
            senderAddress: sender,
            receiverAddress: receiver,
            amount: BigInt.from(0x200),
            asset: tokenAssetMainnet,
            type: TransactionTypes.tokenTransfer,
            note: 'updated',
            data: null,
            timestamp: DateTime.utc(2025, 1, 2),
          ),
        );

        final all = await repo.allTransactions;
        expect(all, hasLength(1));
        expect(all.single.txId, '0xAbC');
        final fetched = all.single as DfxTransaction;
        expect(fetched.rate, 2.5);
        expect(fetched.inputTxId, 'input-2');
        expect(fetched.height, 2);
      },
    );

    test('allTransactions resolves transfer-type rows to the chain native asset', () async {
      // The transformer takes the `type == transfer` branch and uses
      // `blockchain.nativeAsset` instead of the assets table.
      final transfer = buildTokenTransfer(
        txId: 'tx-eth',
        height: 1,
        type: TransactionTypes.transfer,
        asset: tokenAssetMainnet, // will be overridden by nativeAsset
      );

      await repo.insertTransaction(transfer);

      final all = await repo.allTransactions;
      expect(all, hasLength(1));
      expect(all.single.asset.symbol, Blockchain.ethereum.nativeSymbol);
      expect(all.single.asset.address, '0x0');
    });

    test(
      'allTransactions returns a synthesized "Unknown" Asset when the asset row is missing',
      () async {
        // Inserting a token transfer whose `asset` foreign key does not
        // exist in the assets table exercises the `orElse: () => Asset(..)`
        // fallback in the transformer.
        const orphanAsset = Asset(
          chainId: 1,
          address: '0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef',
          name: 'orphan',
          symbol: 'ORP',
          decimals: 18,
        );

        await repo.insertTransaction(
          buildTokenTransfer(txId: 'tx-orphan', height: 1, asset: orphanAsset),
        );

        final all = await repo.allTransactions;
        expect(all, hasLength(1));
        expect(all.single.asset.symbol, '???');
        expect(all.single.asset.name, 'Unknown');
      },
    );

    test('allTransactions orders newest-first by timestamp', () async {
      await repo.insertTransaction(
        buildTokenTransfer(
          txId: 'older',
          height: 1,
          timestamp: DateTime.utc(2025, 1, 1),
        ),
      );
      await repo.insertTransaction(
        buildTokenTransfer(
          txId: 'newer',
          height: 2,
          timestamp: DateTime.utc(2025, 1, 2),
        ),
      );

      final all = await repo.allTransactions;
      expect(all.map((t) => t.txId).toList(), ['newer', 'older']);
    });

    test('watchTransactions emits the full transformed list including DFX details', () async {
      final dfxTx = DfxTransaction(
        dfxId: 7,
        rate: 1.5,
        inputTxId: 'in-7',
        outputTxId: 'out-7',
        height: 10,
        txId: 'tx-watch-dfx',
        chainId: 1,
        senderAddress: sender,
        receiverAddress: receiver,
        amount: BigInt.from(0x100),
        asset: tokenAssetMainnet,
        type: TransactionTypes.tokenTransfer,
        note: null,
        data: null,
        timestamp: DateTime.utc(2025, 1, 1),
      );

      // Drive the stream deterministically: wait for the first emission
      // that matches the post-insert shape. expectLater pumps the event
      // queue itself, so no wall-clock delay is needed.
      final stream = repo.watchTransactions();
      final settled = expectLater(
        stream,
        emitsThrough(
          predicate<List<Transaction>>(
            (list) =>
                list.length == 1 &&
                list.single is DfxTransaction &&
                (list.single as DfxTransaction).dfxId == 7,
          ),
        ),
      );

      await repo.insertDfxTransaction(dfxTx);
      await settled;
    });

    test(
      'watchTransactions transformer resolves transfer rows to the chain native asset',
      () async {
        // The stream transformer has the same `type == transfer →
        // nativeAsset` branch as `allTransactions`; cover it here so
        // both code paths are pinned.
        await repo.insertTransaction(
          buildTokenTransfer(
            txId: 'tx-eth-stream',
            height: 1,
            type: TransactionTypes.transfer,
            asset: tokenAssetMainnet,
          ),
        );

        final first = await repo.watchTransactions().first;
        expect(first, hasLength(1));
        expect(first.single.asset.symbol, Blockchain.ethereum.nativeSymbol);
        expect(first.single.asset.address, '0x0');
      },
    );

    test('watchTransactions transformer falls back to a synthesized Unknown asset', () async {
      // Mirrors the `allTransactions` orphan-asset case in the stream
      // path so the `orElse: () => Asset(Unknown)` branch inside the
      // transformer is also covered.
      const orphanAsset = Asset(
        chainId: 1,
        address: '0xcafef00dcafef00dcafef00dcafef00dcafef00d',
        name: 'orphan',
        symbol: 'ORP',
        decimals: 18,
      );

      await repo.insertTransaction(
        buildTokenTransfer(txId: 'tx-orphan-stream', height: 1, asset: orphanAsset),
      );

      final first = await repo.watchTransactions().first;
      expect(first, hasLength(1));
      expect(first.single.asset.symbol, '???');
      expect(first.single.asset.name, 'Unknown');
    });

    test('watchTransactionsOfAssets without a limit emits matching token transfers', () async {
      // Belongs to the wallet → must show up.
      await repo.insertTransaction(
        buildTokenTransfer(
          txId: 'tx-mine',
          height: 1,
          senderOverride: 'wallet-address',
          receiverOverride: receiver,
        ),
      );
      // Same asset, but neither side equals our wallet → must NOT show.
      await repo.insertTransaction(
        buildTokenTransfer(
          txId: 'tx-other',
          height: 2,
          senderOverride: 'someone-else',
          receiverOverride: 'and-another',
        ),
      );

      final stream = repo.watchTransactionsOfAssets([tokenAssetMainnet], 'wallet-address');
      final first = await stream.first;

      expect(first.map((t) => t.txId), ['tx-mine']);
    });

    test(
      'watchTransactionsOfAssets includes referral payouts with frozen CHF',
      () async {
        await repo.insertTransaction(
          buildTokenTransfer(
            txId: 'tx-prize',
            height: 1,
            type: TransactionTypes.referralPayout,
            senderOverride: kReferralPayoutSenderAddress,
            receiverOverride: 'wallet-address',
            data: '246.50',
            timestamp: DateTime.utc(2026, 8, 24, 10),
          ),
        );
        await repo.insertTransaction(
          buildTokenTransfer(
            txId: 'tx-buy',
            height: 2,
            senderOverride: 'someone-else',
            receiverOverride: 'wallet-address',
            timestamp: DateTime.utc(2026, 8, 24, 9),
          ),
        );
        await repo.insertTransaction(
          buildTokenTransfer(
            txId: 'tx-savings',
            height: 3,
            type: TransactionTypes.savingsAdd,
            senderOverride: 'wallet-address',
            timestamp: DateTime.utc(2026, 8, 24, 11),
          ),
        );

        final history = await repo.watchTransactionsOfAssets([
          tokenAssetMainnet,
        ], 'wallet-address').first;
        expect(history.map((t) => t.txId), ['tx-prize', 'tx-buy']);
        expect(history.first.type, TransactionTypes.referralPayout);
        expect(history.first.data, '246.50');

        final dashboard = await repo
            .watchTransactionsOfAssets([tokenAssetMainnet], 'wallet-address', 3)
            .first;
        expect(dashboard.map((t) => t.txId), ['tx-prize', 'tx-buy']);
      },
    );

    test('watchTransactionsOfAssets with a limit caps the result list', () async {
      for (var i = 0; i < 3; i++) {
        await repo.insertTransaction(
          buildTokenTransfer(
            txId: 'tx-$i',
            height: i + 1,
            senderOverride: 'wallet-address',
            timestamp: DateTime.utc(2025, 1, i + 1),
          ),
        );
      }

      final stream = repo.watchTransactionsOfAssets(
        [tokenAssetMainnet],
        'wallet-address',
        2,
      );

      final first = await stream.first;
      expect(first, hasLength(2));
      // Newest first by timestamp, so tx-2 (Jan 3) and tx-1 (Jan 2).
      expect(first.map((t) => t.txId), ['tx-2', 'tx-1']);
    });

    test('watchTransactionsSavings only emits savingsAdd / savingsRemove rows', () async {
      await repo.insertTransaction(
        buildTokenTransfer(
          txId: 'tx-add',
          height: 1,
          type: TransactionTypes.savingsAdd,
          senderOverride: 'wallet-address',
        ),
      );
      await repo.insertTransaction(
        buildTokenTransfer(
          txId: 'tx-remove',
          height: 2,
          type: TransactionTypes.savingsRemove,
          senderOverride: 'wallet-address',
        ),
      );
      // tokenTransfer / referralPayout → must NOT appear in the savings stream.
      await repo.insertTransaction(
        buildTokenTransfer(
          txId: 'tx-token',
          height: 3,
          senderOverride: 'wallet-address',
        ),
      );
      await repo.insertTransaction(
        buildTokenTransfer(
          txId: 'tx-prize',
          height: 4,
          type: TransactionTypes.referralPayout,
          senderOverride: kReferralPayoutSenderAddress,
          receiverOverride: 'wallet-address',
        ),
      );

      final stream = repo.watchTransactionsSavings(
        [tokenAssetMainnet],
        'wallet-address',
        10,
      );

      final first = await stream.first;
      expect(
        first.map((t) => t.txId).toSet(),
        {'tx-add', 'tx-remove'},
      );
    });
  });
}
