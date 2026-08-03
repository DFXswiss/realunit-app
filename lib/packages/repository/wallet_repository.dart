import 'package:realunit_wallet/packages/storage/database.dart';
import 'package:realunit_wallet/packages/storage/secure_storage.dart';
import 'package:realunit_wallet/packages/storage/wallet_storage.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';

class WalletRepository {
  final AppDatabase _appDatabase;
  final SecureStorage _secureStorage;

  const WalletRepository(this._appDatabase, this._secureStorage);

  Future<int> createWallet(
    String name,
    WalletType type,
    String seed,
    String address,
  ) async {
    final encryptedSeed = await _encryptSeed(seed);
    return _appDatabase.insertWallet(name, encryptedSeed, address, type.index);
  }

  Future<int> createViewWallet(String name, WalletType type, String address) =>
      _appDatabase.insertWallet(name, '', address, type.index);

  /// Returns the row id of an existing BitBox wallet with [address], or null.
  /// Used by the migration wizard to make committing a paired device idempotent.
  Future<int?> getBitboxWalletIdByAddress(String address) async {
    final info = await _appDatabase.getWalletByTypeAndAddress(
      WalletType.bitbox.index,
      address,
    );
    return info?.id;
  }

  /// Returns the wallet row with the encrypted seed *still encrypted*. Use this
  /// at app startup so we don't pay the mnemonic-decrypt / BIP32-derivation
  /// cost just to render the dashboard — the cached address is enough.
  Future<WalletInfo?> getWalletInfo(int id) => _appDatabase.getWalletById(id);

  /// Backfills the address column for legacy software-wallet rows that were
  /// created before address-caching landed. After this runs once, subsequent
  /// loads of the same row stay on the fast view-wallet path.
  Future<void> updateAddress(int id, String address) =>
      _appDatabase.updateWalletAddress(id, address);

  /// Returns the wallet row with the seed decrypted. Only call this when the
  /// private key is actually needed (signing a sell, revealing the seed).
  Future<WalletInfo?> getUnlockedWalletById(int id) async {
    final info = await _appDatabase.getWalletById(id);
    if (info == null) return null;
    if (info.seed.isEmpty) return info;
    return _decryptWalletInfo(info);
  }

  Future<void> deleteWallet(int id) => _appDatabase.deleteWallet(id);

  /// Full purge for the user-facing delete: removes the encrypted-seed row AND
  /// the AES-GCM mnemonic key, so no recoverable seed material remains on
  /// device.
  Future<void> purgeWallet(int id) async {
    await _appDatabase.deleteWalletCompletely(id);
    await _secureStorage.deleteMnemonicKey();
  }

  Future<WalletInfo> _decryptWalletInfo(WalletInfo info) async {
    final key = await _secureStorage.getOrCreateMnemonicKey();
    final decryptedSeed = SecureStorage.decryptSeed(key, info.seed);
    return info.copyWith(seed: decryptedSeed);
  }

  Future<String> _encryptSeed(String seed) async {
    final key = await _secureStorage.getOrCreateMnemonicKey();
    return SecureStorage.encryptSeed(key, seed);
  }
}
