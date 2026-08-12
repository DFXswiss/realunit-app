import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/packages/storage/database.dart';
import 'package:realunit_wallet/packages/storage/wallet_storage.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('WalletStorage extension', () {
    test('hasWallet is false on an empty database', () async {
      expect(await db.hasWallet, isFalse);
    });

    test('hasWallet flips to true after the first insertWallet', () async {
      await db.insertWallet('Test', 'seed', '0xA', 0);
      expect(await db.hasWallet, isTrue);
    });

    test('insertWallet returns the rowid and getWalletById round-trips the row', () async {
      final id = await db.insertWallet('Main', 'enc-seed', '0xMain', 1);
      expect(id, greaterThan(0));

      final fetched = await db.getWalletById(id);
      expect(fetched, isNotNull);
      expect(fetched!.id, id);
      expect(fetched.name, 'Main');
      expect(fetched.seed, 'enc-seed');
      expect(fetched.address, '0xMain');
      expect(fetched.type, 1);
    });

    test('getWalletById returns null for an unknown id', () async {
      expect(await db.getWalletById(9999), isNull);
    });

    test(
      'getWalletByTypeAndAddress returns the matching row and null when type or address differs',
      () async {
        final bitboxId = await db.insertWallet('Hardware', '', '0xBitBox', 1);
        await db.insertWallet('Software', 'seed', '0xBitBox', 0);
        await db.insertWallet('OtherHw', '', '0xOther', 1);

        final hit = await db.getWalletByTypeAndAddress(1, '0xBitBox');
        expect(hit, isNotNull);
        expect(hit!.id, bitboxId);
        expect(hit.type, 1);
        expect(hit.address, '0xBitBox');

        expect(await db.getWalletByTypeAndAddress(0, '0xBitBox'), isNotNull);
        expect(await db.getWalletByTypeAndAddress(1, '0xMissing'), isNull);
      },
    );

    test('updateWalletAddress mutates only the address column', () async {
      final id = await db.insertWallet('Main', 'enc-seed', '0xOld', 0);

      final affected = await db.updateWalletAddress(id, '0xNew');
      expect(affected, 1);

      final fetched = await db.getWalletById(id);
      expect(fetched!.address, '0xNew');
      // The other columns must be untouched.
      expect(fetched.name, 'Main');
      expect(fetched.seed, 'enc-seed');
    });

    test('insertWalletAccount + getWalletAccounts round-trip the rows', () async {
      final walletId = await db.insertWallet('Main', 'seed', '0xMain', 0);

      await db.insertWalletAccount(walletId, 'acc-0', 0);
      await db.insertWalletAccount(walletId, 'acc-1', 1);

      final accounts = await db.getWalletAccounts(walletId);
      expect(accounts, hasLength(2));
      expect(accounts.map((a) => a.name).toSet(), {'acc-0', 'acc-1'});
      expect(accounts.map((a) => a.accountIndex).toSet(), {0, 1});
    });

    test('getWalletAccounts returns an empty list when no accounts are linked', () async {
      final walletId = await db.insertWallet('Empty', 'seed', '0xEmpty', 0);
      expect(await db.getWalletAccounts(walletId), isEmpty);
    });

    test('deleteWallet removes all accounts of the given wallet', () async {
      // `deleteWallet` only deletes from wallet_account_infos today (see
      // its body). This test pins that contract: after the call the
      // accounts are gone, but the wallet_infos row remains.
      final walletId = await db.insertWallet('Main', 'seed', '0xMain', 0);
      await db.insertWalletAccount(walletId, 'acc-0', 0);
      await db.insertWalletAccount(walletId, 'acc-1', 1);

      final removed = await db.deleteWallet(walletId);
      expect(removed, 2);

      expect(await db.getWalletAccounts(walletId), isEmpty);
      // The wallet itself is still present.
      expect(await db.getWalletById(walletId), isNotNull);
    });
  });
}
