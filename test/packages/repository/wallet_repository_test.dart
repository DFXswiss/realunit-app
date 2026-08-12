import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/repository/wallet_repository.dart';
import 'package:realunit_wallet/packages/storage/database.dart';
import 'package:realunit_wallet/packages/storage/secure_storage.dart';
import 'package:realunit_wallet/packages/storage/wallet_storage.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';
import 'package:web3dart/web3dart.dart';

class _MockSecureStorage extends Mock implements SecureStorage {}

void main() {
  late AppDatabase db;
  late _MockSecureStorage secureStorage;
  late WalletRepository repo;

  // Deterministic 256-bit AES-GCM key — content is irrelevant for the
  // round-trip assertions, only that the encrypt/decrypt static helpers
  // get the same bytes both ways.
  final mnemonicKey = Uint8List.fromList(List<int>.generate(32, (i) => i));

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    secureStorage = _MockSecureStorage();
    repo = WalletRepository(db, secureStorage);

    when(() => secureStorage.getOrCreateMnemonicKey()).thenAnswer((_) async => mnemonicKey);
  });

  tearDown(() async {
    await db.close();
  });

  const seed = 'test mnemonic words go here twelve total for a real bip39';
  const walletName = 'Primary';
  const address = '0xabCDeF0123456789abCDeF0123456789aBCDeF01';

  group('$WalletRepository', () {
    test('createWallet encrypts the seed before persisting it', () async {
      final id = await repo.createWallet(walletName, WalletType.software, seed, address);

      expect(id, greaterThan(0));

      final row = await db.getWalletById(id);
      expect(row, isNotNull);
      expect(row!.name, walletName);
      expect(row.address, address);
      expect(row.type, WalletType.software.index);
      // The stored seed must not be the plaintext: the whole point of
      // the encrypt step is that a leaked DB row doesn't equal the
      // mnemonic.
      expect(row.seed, isNot(equals(seed)));
      expect(row.seed, isNotEmpty);

      verify(() => secureStorage.getOrCreateMnemonicKey()).called(1);
    });

    test('createViewWallet stores an empty seed and bypasses the secure storage', () async {
      final id = await repo.createViewWallet(walletName, WalletType.software, address);

      expect(id, greaterThan(0));

      final row = await db.getWalletById(id);
      expect(row, isNotNull);
      expect(row!.name, walletName);
      expect(row.address, address);
      expect(row.seed, isEmpty);
      // No encryption key is fetched for a view wallet because there
      // is no seed material to wrap.
      verifyNever(() => secureStorage.getOrCreateMnemonicKey());
    });

    test(
      'getBitboxWalletIdByAddress normalizes legacy rows and ignores malformed candidates',
      () async {
        await repo.createViewWallet('MalformedHardware', WalletType.bitbox, '');
        // The file-wide fixture is deliberately case-mangled (not EIP-55
        // conformant), which fromHex rejects for mixed case — lowercase it
        // first; uniform-case input skips the checksum validation.
        final normalizedAddress = EthereumAddress.fromHex(address.toLowerCase()).hexEip55;
        final bitboxId = await repo.createViewWallet(
          'Hardware',
          WalletType.bitbox,
          normalizedAddress.toLowerCase(),
        );
        // Same address, different type — must NOT match the BitBox lookup.
        await repo.createViewWallet(
          'SoftwareView',
          WalletType.software,
          normalizedAddress,
        );

        expect(
          await repo.getBitboxWalletIdByAddress(normalizedAddress),
          bitboxId,
        );
        expect(
          await repo.getBitboxWalletIdByAddress(
            '0x3333333333333333333333333333333333333333',
          ),
          isNull,
        );
        expect(await repo.getBitboxWalletIdByAddress(''), isNull);
        expect(await repo.getBitboxWalletIdByAddress('0xNoSuchAddress000000000000000000000001'), isNull);
      },
    );

    test('getWalletInfo returns the row with the seed still encrypted', () async {
      final id = await repo.createWallet(walletName, WalletType.software, seed, address);

      final info = await repo.getWalletInfo(id);
      expect(info, isNotNull);
      expect(info!.name, walletName);
      // getWalletInfo must NOT decrypt — that is the whole reason
      // the fast-path exists.
      expect(info.seed, isNot(equals(seed)));
      expect(info.seed, isNotEmpty);
    });

    test('getWalletInfo returns null for an unknown id', () async {
      expect(await repo.getWalletInfo(99999), isNull);
    });

    test('updateAddress backfills the address column', () async {
      final id = await repo.createViewWallet(walletName, WalletType.software, '');

      const newAddress = '0xfedCBA9876543210fedCBA9876543210fEdCbA98';
      await repo.updateAddress(id, newAddress);

      final info = await repo.getWalletInfo(id);
      expect(info, isNotNull);
      expect(info!.address, newAddress);
    });

    test('getUnlockedWalletById decrypts the seed back to the plaintext', () async {
      final id = await repo.createWallet(walletName, WalletType.software, seed, address);

      final unlocked = await repo.getUnlockedWalletById(id);

      expect(unlocked, isNotNull);
      expect(unlocked!.seed, seed);
      expect(unlocked.name, walletName);
      expect(unlocked.address, address);
    });

    test('getUnlockedWalletById returns null for an unknown id', () async {
      expect(await repo.getUnlockedWalletById(99999), isNull);
    });

    test('getUnlockedWalletById short-circuits when the seed column is empty', () async {
      // View wallets have an empty seed string. The decrypt branch is
      // guarded by `if (info.seed.isEmpty) return info`; without that
      // short-circuit the GCM cipher would be handed an empty cipher
      // text and throw — so this test pins the early-return behaviour
      // and verifies the secure storage is never reached.
      final id = await repo.createViewWallet(walletName, WalletType.software, address);

      final unlocked = await repo.getUnlockedWalletById(id);

      expect(unlocked, isNotNull);
      expect(unlocked!.seed, isEmpty);
      verifyNever(() => secureStorage.getOrCreateMnemonicKey());
    });

    test('deleteWallet removes the wallet-account-info rows for the wallet', () async {
      // `WalletStorage.deleteWallet` (today) deletes from
      // wallet_account_infos, not from wallet_infos itself. Pin the
      // observable behaviour: a previously-created account row is gone
      // afterwards.
      final walletId = await repo.createWallet(walletName, WalletType.software, seed, address);
      await db.insertWalletAccount(walletId, 'acc-0', 0);

      final beforeAccounts = await db.getWalletAccounts(walletId);
      expect(beforeAccounts, hasLength(1));

      await repo.deleteWallet(walletId);

      final afterAccounts = await db.getWalletAccounts(walletId);
      expect(afterAccounts, isEmpty);
    });

    test('purgeWallet removes the walletInfos seed row AND the mnemonic key', () async {
      // The user-facing delete must leave no recoverable seed material —
      // neither the encrypted row nor the AES key.
      when(() => secureStorage.deleteMnemonicKey()).thenAnswer((_) async {});

      final walletId = await repo.createWallet(walletName, WalletType.software, seed, address);
      await db.insertWalletAccount(walletId, 'acc-0', 0);
      expect(await db.getWalletById(walletId), isNotNull);

      await repo.purgeWallet(walletId);

      expect(await db.getWalletById(walletId), isNull); // encrypted seed row gone
      expect(await db.getWalletAccounts(walletId), isEmpty); // accounts gone
      verify(() => secureStorage.deleteMnemonicKey()).called(1); // AES key removed
    });

    test('deleteWallet (account-only) leaves the seed row and mnemonic key intact', () async {
      // Onboarding-regenerate contract: the account-only primitive must NOT
      // wipe the seed row or the AES key.
      final walletId = await repo.createWallet(walletName, WalletType.software, seed, address);
      await db.insertWalletAccount(walletId, 'acc-0', 0);

      await repo.deleteWallet(walletId);

      expect(await db.getWalletById(walletId), isNotNull); // row survives
      expect(await db.getWalletAccounts(walletId), isEmpty); // accounts gone
      verifyNever(() => secureStorage.deleteMnemonicKey()); // key untouched
    });
  });
}
