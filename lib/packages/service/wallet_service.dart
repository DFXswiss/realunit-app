import 'dart:async';

import 'package:bip39/bip39.dart' as bip39;
import 'package:realunit_wallet/packages/hardware_wallet/bitbox.dart';
import 'package:realunit_wallet/packages/repository/settings_repository.dart';
import 'package:realunit_wallet/packages/repository/wallet_repository.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/bitbox_address_unavailable_exception.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';
import 'package:web3dart/web3dart.dart';

class WalletService {
  final WalletRepository _repository;
  final SettingsRepository _settingsRepository;
  final BitboxService _bitboxService;
  final AppStore _appStore;

  /// Auto-lock 60 s after each unlock, regardless of subsequent activity. The
  /// timer is armed in [ensureCurrentWalletUnlocked] and is NOT reset by user
  /// interaction — it caps the maximum lifetime of the in-memory mnemonic
  /// after an explicit unlock, not an idle window. Sized to comfortably
  /// outlast a normal sign-then-broadcast round-trip.
  static const Duration _postUnlockLockTimeout = Duration(seconds: 60);

  /// Cancellation guard for the post-unlock timer so a lock-during-test or a
  /// concurrent explicit lock doesn't double-fire.
  Timer? _postUnlockLockTimer;

  /// Active holders of the unlocked-wallet contract. Incremented on every
  /// [ensureCurrentWalletUnlocked] call, decremented on every matching
  /// [lockCurrentWallet] — the wallet only flips back to a view-wallet once
  /// the last holder has released. Closes the race where flow A locks
  /// between flow B's ensure and its sign, leaving B with a
  /// [SoftwareViewWallet] mid-flight and an [UnsupportedError] from the
  /// locked-credentials sentinel. The post-unlock timer bypasses the counter
  /// via [_forceLock] so the 60s safety net still caps the mnemonic lifetime
  /// even if a caller forgets to release.
  int _activeUnlockHolders = 0;

  /// Shared future for the currently-in-flight unlock, so two overlapping
  /// [ensureCurrentWalletUnlocked] calls reuse the same DB read + AES-GCM
  /// decrypt instead of triggering it twice. Cleared in `finally` so the
  /// next post-lock ensure starts a fresh unlock.
  Future<SoftwareWallet>? _unlockInFlight;

  WalletService(
    this._bitboxService,
    this._repository,
    this._settingsRepository,
    this._appStore,
  );

  /// Generates a fresh bip39 mnemonic and returns a [SoftwareWallet] that
  /// is **not yet persisted** — `id` is the `0` sentinel and no row has
  /// been written to `walletInfos`. Pair with [commitGeneratedWallet] once
  /// the user has confirmed the seed (e.g. via the verify-seed quiz) so the
  /// encrypted mnemonic only lands on disk for seeds the user has actually
  /// kept. Prevents N+1 encrypted-seed rows from accumulating when the
  /// onboarding cubit regenerates the mnemonic on every `hidden` cycle.
  Future<SoftwareWallet> generateUncommittedSeedWallet(String name) async {
    final mnemonic = bip39.generateMnemonic();
    return SoftwareWallet(0, name, mnemonic);
  }

  /// Persists a [draft] [SoftwareWallet] returned from
  /// [generateUncommittedSeedWallet] into `walletInfos` (encrypted seed +
  /// cached address) and returns a new [SoftwareWallet] carrying the
  /// DB-assigned id. The draft is expected to carry the `0` sentinel id; a
  /// different id indicates a misuse (commit called on an already-persisted
  /// wallet) — surfaced via [assert] in dev and tolerated in release by
  /// re-using the draft's seed.
  Future<SoftwareWallet> commitGeneratedWallet(SoftwareWallet draft) async {
    assert(draft.id == 0,
        'commitGeneratedWallet expects an uncommitted draft (id == 0); '
        'got id=${draft.id} — likely double-commit or wrong caller.');
    return _persistSoftwareWallet(draft.name, draft.seed);
  }

  /// Generate-and-commit convenience for callers that persist immediately
  /// (e.g. [restoreWallet]). Onboarding callers should NOT use this — they
  /// must call [generateUncommittedSeedWallet] and defer [commitGeneratedWallet]
  /// until the user has confirmed the seed, otherwise every regenerate on
  /// `hidden` writes an undeletable encrypted-seed row to `walletInfos`.
  Future<SoftwareWallet> createSeedWallet(String name) async {
    final draft = await generateUncommittedSeedWallet(name);
    return commitGeneratedWallet(draft);
  }

  // @no-integration-test: no BitBox firmware/transport harness is wired into
  //   the repo yet; the BitboxService.getEthAddress boundary is covered by unit
  //   tests with mocked transport (see wallet_service_test.dart).
  Future<BitboxWallet> createBitboxWallet(String name) async {
    // [BitboxService.getEthAddress] already retries the transient empty read
    // the SDK produces when it coerces a native `null` into `""` (its
    // `return result ?? ''` transport boundary) and throws on a persistent
    // one. The format guard below is defence-in-depth — it also rejects the
    // rarer non-empty-but-malformed read before `EthereumAddress.fromHex`
    // would crash the dashboard build on the next launch.
    final address = await _bitboxService.getEthAddress();
    if (!_isValidEthAddress(address.toLowerCase())) {
      throw const BitboxAddressUnavailableException();
    }
    final normalizedAddress =
        EthereumAddress.fromHex(address.toLowerCase()).hexEip55;
    final walletId = await _repository.createViewWallet(
      name,
      WalletType.bitbox,
      normalizedAddress,
    );
    await setCurrentWallet(walletId);
    return BitboxWallet(walletId, name, normalizedAddress, _bitboxService);
  }

  /// Reads the ETH address from the connected BitBox and returns an
  /// UNCOMMITTED [BitboxWallet] draft — `id` is the `0` sentinel, no row is
  /// written to `walletInfos` and the current wallet is NOT switched. Pair with
  /// [persistBitboxWallet] once the new address is registered server-side,
  /// mirroring [generateUncommittedSeedWallet]/[commitGeneratedWallet] so an
  /// aborted wizard leaves no orphan wallet row behind.
  /// Throws [BitboxAddressUnavailableException] on an unusable address (same
  /// guard as [createBitboxWallet]).
  // @no-integration-test: no BitBox firmware/transport harness is wired into
  //   the repo yet; the BitboxService.getEthAddress boundary is covered by unit
  //   tests with mocked transport (see wallet_service_test.dart).
  Future<BitboxWallet> acquireUncommittedBitboxWallet(String name) async {
    final address = await _bitboxService.getEthAddress();
    if (!_isValidEthAddress(address.toLowerCase())) {
      throw const BitboxAddressUnavailableException();
    }
    final normalizedAddress =
        EthereumAddress.fromHex(address.toLowerCase()).hexEip55;
    return BitboxWallet(0, name, normalizedAddress, _bitboxService);
  }

  /// Persists a [draft] from [acquireUncommittedBitboxWallet] WITHOUT switching
  /// the current wallet. Deduplicates by address: an existing BitBox row with
  /// the same address is reused instead of inserting a second row (covers a
  /// device that was already paired once outside the wizard, and makes the call
  /// idempotent across wizard re-entries). Asserts on a non-draft id in dev
  /// (mirror of [commitGeneratedWallet]).
  ///
  /// The migration wizard calls this BEFORE any funds move (right after the new
  /// address is registered server-side), so an app death between the balance
  /// transfer and the final wallet switch still leaves a local wallet row
  /// pointing at the funded address. The final switch is a plain
  /// [setCurrentWallet] — deliberately not part of this method.
  Future<BitboxWallet> persistBitboxWallet(BitboxWallet draft) async {
    assert(
      draft.id == 0,
      'persistBitboxWallet expects an uncommitted draft (id == 0); '
      'got id=${draft.id} — likely double-commit or wrong caller.',
    );
    final address = draft.primaryAccount.primaryAddress.address.hexEip55;
    final existingId = await _repository.getBitboxWalletIdByAddress(address);
    final id = existingId ??
        await _repository.createViewWallet(draft.name, WalletType.bitbox, address);
    return BitboxWallet(id, draft.name, address, _bitboxService);
  }

  /// True when [address] parses as a canonical 20-byte Ethereum address.
  ///
  /// Uses the same web3dart parser that every wallet credential class relies on
  /// so the validity boundary here matches exactly the one that would otherwise
  /// throw deep in the dashboard build. An empty string fails fast through the
  /// [FormatException]/[ArgumentError] catch — no need to special-case it.
  /// Callers lowercase SDK addresses before validation and normalization so
  /// mixed-case values without a valid EIP-55 checksum are not rejected early.
  static bool _isValidEthAddress(String address) {
    try {
      EthereumAddress.fromHex(address);
      return true;
    } on FormatException {
      return false;
    } on ArgumentError {
      return false;
    }
  }

  /// Non-throwing probe used at app load to decide whether the current wallet
  /// is a BitBox row that was persisted with an empty/invalid address (the
  /// pre-fix data corruption). Returns false for software/debug wallets, for a
  /// missing current id, for an absent row, and for a BitBox row whose address
  /// parses cleanly — i.e. it only flags the rows that would crash the
  /// dashboard build, leaving every healthy wallet on the normal load path.
  Future<bool> currentWalletNeedsAddressRecovery() async {
    final id = _settingsRepository.currentWalletId;
    if (id == null) return false;
    final info = await _repository.getWalletInfo(id);
    if (info == null) return false;
    if (WalletType.values[info.type] != WalletType.bitbox) return false;
    return !_isValidEthAddress(info.address);
  }

  /// Re-derives the ETH address from a freshly re-paired BitBox and backfills it
  /// onto the current wallet row, replacing the empty/invalid one. This is local
  /// crypto/device recovery — the address is a deterministic function of the
  /// device, not account state owned by the API — so it does not belong behind a
  /// network round-trip. Throws [BitboxAddressUnavailableException] if the device
  /// still returns an unusable address so the recovery UI can retry rather than
  /// re-persist the corruption.
  Future<BitboxWallet> healCurrentBitboxAddress() async {
    final id = _settingsRepository.currentWalletId!;
    final info = (await _repository.getWalletInfo(id))!;
    // Shares the retry + empty-guard boundary with createBitboxWallet; the
    // format check stays as defence-in-depth (see that method).
    final rawAddress = await _bitboxService.getEthAddress();
    if (!_isValidEthAddress(rawAddress.toLowerCase())) {
      throw const BitboxAddressUnavailableException();
    }
    // Same EIP-55 normalization as the create/acquire paths — the SDK's
    // address casing is not guaranteed consistent across reads.
    final address = EthereumAddress.fromHex(rawAddress.toLowerCase()).hexEip55;
    await _repository.updateAddress(id, address);
    return BitboxWallet(id, info.name, address, _bitboxService);
  }

  /// Persists a user-supplied seed phrase immediately — the user typed an
  /// existing mnemonic, so there is no verify-seed quiz to gate the write
  /// behind. Deferring would not help: the seed is already known and the
  /// user expects to land on the dashboard on `restore` success.
  Future<SoftwareWallet> restoreWallet(String name, String seed) async {
    final wallet = await _persistSoftwareWallet(name, seed);
    await _settingsRepository.saveCurrentWalletId(wallet.id);
    return wallet;
  }

  /// Builds the BIP32 wallet once to derive the public address, then persists
  /// `(encryptedSeed, address)` so app-start can render the dashboard from the
  /// cached address without re-running the derivation.
  Future<SoftwareWallet> _persistSoftwareWallet(String name, String seed) async {
    final fullWallet = SoftwareWallet(0, name, seed);
    final address = fullWallet.currentAccount.primaryAddress.address.hexEip55;
    final id = await _repository.createWallet(name, WalletType.software, seed, address);
    return SoftwareWallet(id, name, seed);
  }

  Future<DebugWallet> createDebugWallet(String address) async {
    final walletId = await _repository.createViewWallet('Debug', WalletType.debug, address);
    await _settingsRepository.saveCurrentWalletId(walletId);
    return DebugWallet(walletId, 'Debug', address);
  }

  /// Loads a wallet using only what's persisted in clear text — for software
  /// wallets this means a [SoftwareViewWallet] (address only, no mnemonic in
  /// memory). Use [unlockWalletById] when the private key is actually needed.
  Future<AWallet> getWalletById(int id) async {
    final info = (await _repository.getWalletInfo(id))!;
    final walletType = WalletType.values[info.type];
    switch (walletType) {
      case WalletType.software:
        // Legacy rows created before address-caching landed have an empty
        // address column — decrypt the mnemonic this one time, persist the
        // derived address back to the row, then keep using the fast path on
        // subsequent loads.
        if (info.address.isEmpty) {
          final unlocked = (await _repository.getUnlockedWalletById(id))!;
          final wallet = SoftwareWallet(unlocked.id, unlocked.name, unlocked.seed);
          await _repository.updateAddress(
            id,
            wallet.currentAccount.primaryAddress.address.hexEip55,
          );
          return wallet;
        }
        return SoftwareViewWallet(info.id, info.name, info.address);
      case WalletType.bitbox:
        return BitboxWallet(info.id, info.name, info.address, _bitboxService);
      case WalletType.debug:
        return DebugWallet(info.id, info.name, info.address);
    }
  }

  /// Decrypts the mnemonic and returns a [SoftwareWallet] ready to sign.
  /// Throws if the wallet type is not software.
  Future<SoftwareWallet> unlockWalletById(int id) async {
    final info = (await _repository.getUnlockedWalletById(id))!;
    if (WalletType.values[info.type] != WalletType.software) {
      throw StateError('unlockWalletById called for non-software wallet');
    }
    return SoftwareWallet(info.id, info.name, info.seed);
  }

  Future<void> setCurrentWallet(int walletId) async =>
      await _settingsRepository.saveCurrentWalletId(walletId);

  Future<AWallet> getCurrentWallet() async {
    final id = _settingsRepository.currentWalletId!;
    return getWalletById(id);
  }

  Future<SoftwareWallet> unlockCurrentWallet() async {
    final id = _settingsRepository.currentWalletId!;
    return unlockWalletById(id);
  }

  /// Promotes the currently loaded wallet from [SoftwareViewWallet] (address
  /// only) to a fully unlocked [SoftwareWallet] (mnemonic in memory) so the
  /// next sign operation can run. No-op for wallets that aren't locked.
  ///
  /// Owning the lifecycle here — instead of behind a callback wired onto
  /// [AppStore] — keeps the latter as a pure state container.
  ///
  /// Every call increments [_activeUnlockHolders]; callers must pair with
  /// exactly one [lockCurrentWallet] in a finally so concurrent sign flows
  /// don't tear the unlocked state out from under each other.
  Future<void> ensureCurrentWalletUnlocked() async {
    _activeUnlockHolders++;
    // Tracks whether THIS call's unlock landed in [AppStore.wallet]. When
    // the lock-during-flight invalidates the slot, the write is skipped and
    // arming the post-unlock timer would just point at a [SoftwareViewWallet]
    // — `_lockWalletInPlace` would safely no-op via `is! SoftwareWallet`, so
    // it's dead work, not a correctness bug. Skip the arm in that case.
    var landedInStore = false;
    if (_appStore.wallet is SoftwareViewWallet) {
      // Coalesce overlapping unlocks onto a single in-flight future so we
      // don't hammer the DB and re-run AES-GCM for every concurrent caller.
      final inFlight = _unlockInFlight ??= unlockCurrentWallet();
      try {
        final unlocked = await inFlight;
        // If [lockCurrentWallet] fired while this unlock was in flight, it
        // invalidates the slot (`_unlockInFlight = null`). Skip the write
        // so the mnemonic doesn't resurface in [AppStore.wallet] after the
        // user has already covered the app — closes the `_onHidden` race.
        if (identical(_unlockInFlight, inFlight)) {
          _appStore.wallet = unlocked;
          landedInStore = true;
        }
      } finally {
        // Only the caller that started the unlock clears the slot; later
        // joiners observe the field already nulled and skip the clear.
        if (identical(_unlockInFlight, inFlight)) _unlockInFlight = null;
      }
    } else {
      // Wallet was already unlocked (a previous holder's write is still in
      // place). Re-arming the safety net is the right call — extends the
      // 60 s window for the joining holder.
      landedInStore = true;
    }
    // Safety net: if a caller forgets to call lockCurrentWallet() after the
    // sign, drop the mnemonic anyway once the post-unlock window elapses. The
    // reviewer flagged "user signs once then leaves the app foregrounded" —
    // that path now caps at [_postUnlockLockTimeout]. Skip the arm when the
    // intervening lock invalidated our write: the timer would just fire
    // against a view-wallet (no-op) and we'd be doing dead work.
    if (landedInStore) _schedulePostUnlockLock();
  }

  /// Replaces the in-memory [SoftwareWallet] with its lock-screen-safe
  /// [SoftwareViewWallet] counterpart, dropping the mnemonic. Called after a
  /// sign operation completes so the private key isn't kept resident for the
  /// rest of the foreground session. No-op for wallet types that don't hold
  /// a mnemonic, and no-op when no wallet has been loaded yet.
  ///
  /// Respects [_activeUnlockHolders] — a second concurrent caller still
  /// holding the unlocked contract keeps the wallet unlocked. The 60s safety
  /// net runs through [_forceLock] instead so it can bypass the counter.
  Future<void> lockCurrentWallet() async {
    // Onboarding / pre-load guard. The app-lifecycle `hidden` hook can fire
    // before [HomeBloc] populates [AppStore.wallet] — making the precondition
    // explicit here keeps the lifecycle caller a one-liner and means a future
    // lockCurrentWallet extension (DB write, etc.) won't get its errors
    // silently caught at the call site.
    if (!_appStore.isWalletLoaded) return;

    if (_activeUnlockHolders > 0) _activeUnlockHolders--;
    if (_activeUnlockHolders > 0) return;
    // Invalidate any in-flight unlock so its resolution doesn't write the
    // unlocked [SoftwareWallet] back into [AppStore.wallet] after this lock —
    // the race the 60s safety net used to catch as defence-in-depth, now
    // closed at the source.
    _unlockInFlight?.ignore();
    _unlockInFlight = null;
    _postUnlockLockTimer?.cancel();
    _postUnlockLockTimer = null;
    _lockWalletInPlace();
  }

  void _schedulePostUnlockLock() {
    _postUnlockLockTimer?.cancel();
    _postUnlockLockTimer = Timer(_postUnlockLockTimeout, _forceLock);
  }

  /// Hard cap on the in-memory mnemonic lifetime. Bypasses
  /// [_activeUnlockHolders] so a stuck holder can't keep the key resident
  /// past the safety window.
  void _forceLock() {
    _activeUnlockHolders = 0;
    _postUnlockLockTimer = null;
    _lockWalletInPlace();
  }

  void _lockWalletInPlace() {
    final current = _appStore.wallet;
    if (current is! SoftwareWallet) return;
    final address = current.currentAccount.primaryAddress.address.hexEip55;
    _appStore.wallet = SoftwareViewWallet(current.id, current.name, address);
  }

  Future<void> deleteCurrentWallet() async {
    final id = _settingsRepository.currentWalletId!;
    // Full purge (seed row + mnemonic key), not an account-only delete — so no
    // recoverable seed survives delete.
    await _repository.purgeWallet(id);
    await _settingsRepository.removeCurrentWalletId();
  }

  bool hasWallet() => _settingsRepository.currentWalletId != null;

  bool validateSeed(String seed) => bip39.validateMnemonic(seed);
}
