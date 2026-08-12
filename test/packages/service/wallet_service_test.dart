import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/hardware_wallet/bitbox.dart';
import 'package:realunit_wallet/packages/hardware_wallet/bitbox_credentials.dart';
import 'package:realunit_wallet/packages/repository/settings_repository.dart';
import 'package:realunit_wallet/packages/repository/wallet_repository.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/bitbox_address_unavailable_exception.dart';
import 'package:realunit_wallet/packages/service/wallet_service.dart';
import 'package:realunit_wallet/packages/storage/database.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';
import 'package:web3dart/web3dart.dart';

class _MockWalletRepository extends Mock implements WalletRepository {}

class _MockSettingsRepository extends Mock implements SettingsRepository {}

class _MockBitboxService extends Mock implements BitboxService {}

class _MockAppStore extends Mock implements AppStore {}

const _testMnemonic = 'test test test test test test test test test test test junk';
const _debugAddress = '0x0000000000000000000000000000000000000001';
const _lowercaseAddress = '0x9f5713deacb8e9cab6c2d3fae1afc2715f8d2d71';
const _invalidMixedCaseAddress = '0x52908400098527886e0F7030069857D2E4169EE7';

WalletInfo _info({
  int id = 1,
  String name = 'Main',
  String seed = '',
  String address = '',
  required WalletType type,
}) => WalletInfo(id: id, name: name, seed: seed, address: address, type: type.index);

void main() {
  late _MockWalletRepository repo;
  late _MockSettingsRepository settings;
  late _MockBitboxService bitbox;
  late _MockAppStore appStore;
  late WalletService service;

  setUpAll(() {
    // mocktail needs a default for non-primitive types used with `any()`.
    registerFallbackValue(WalletType.software);
    registerFallbackValue(SoftwareViewWallet(0, '_fallback', _debugAddress) as AWallet);
  });

  setUp(() {
    repo = _MockWalletRepository();
    settings = _MockSettingsRepository();
    bitbox = _MockBitboxService();
    appStore = _MockAppStore();
    service = WalletService(bitbox, repo, settings, appStore);

    when(() => settings.saveCurrentWalletId(any())).thenAnswer((_) async => true);
    when(() => settings.removeCurrentWalletId()).thenAnswer((_) async => true);
    when(() => repo.deleteWallet(any())).thenAnswer((_) async {});
    when(() => repo.purgeWallet(any())).thenAnswer((_) async {});
    when(() => repo.updateAddress(any(), any())).thenAnswer((_) async {});
  });

  group('$WalletService', () {
    group('generateUncommittedSeedWallet', () {
      test(
        'returns an in-memory SoftwareWallet with the id=0 sentinel and a valid bip39 mnemonic',
        () async {
          final draft = await service.generateUncommittedSeedWallet('Main');

          expect(draft, isA<SoftwareWallet>());
          expect(
            draft.id,
            0,
            reason:
                'uncommitted drafts use the 0 sentinel until commitGeneratedWallet lands the row',
          );
          expect(draft.name, 'Main');
          expect(service.validateSeed(draft.seed), isTrue);
        },
      );

      test('does NOT write to the repository — the encrypted seed must not land on disk', () async {
        await service.generateUncommittedSeedWallet('Main');

        // Pin the disk-side guarantee: nothing flows into `walletInfos` until
        // a separate `commitGeneratedWallet` call. Without this, every
        // `_dropMnemonic` regenerate in `CreateWalletCubit` would persist a
        // fresh encrypted-seed row, and `WalletStorage.deleteWallet` only
        // touches `walletAccountInfos`, so those rows would accumulate
        // undeletable.
        verifyNever(() => repo.createWallet(any(), any(), any(), any()));
        verifyNever(() => settings.saveCurrentWalletId(any()));
      });

      test(
        'two consecutive calls produce distinct mnemonics (entropy not pinned by the API)',
        () async {
          final a = await service.generateUncommittedSeedWallet('Main');
          final b = await service.generateUncommittedSeedWallet('Main');

          expect(
            a.seed,
            isNot(equals(b.seed)),
            reason:
                'each call must produce a fresh mnemonic — pinning entropy would '
                'silently break the "regenerate on hidden" contract',
          );
        },
      );
    });

    group('commitGeneratedWallet', () {
      test(
        'persists the draft seed and returns a SoftwareWallet carrying the DB-assigned id',
        () async {
          when(() => repo.createWallet(any(), any(), any(), any())).thenAnswer((_) async => 42);

          final draft = await service.generateUncommittedSeedWallet('Main');
          final committed = await service.commitGeneratedWallet(draft);

          expect(committed.id, 42);
          expect(committed.name, 'Main');
          expect(
            committed.seed,
            draft.seed,
            reason: 'commit must preserve the draft mnemonic — no silent re-generation',
          );
          final expectedAddress = committed.currentAccount.primaryAddress.address.hexEip55;
          verify(
            () => repo.createWallet('Main', WalletType.software, draft.seed, expectedAddress),
          ).called(1);
        },
      );

      test('writes exactly one row per call (no implicit dedup at this layer)', () async {
        // Pin the disk-side contract: each commit call is one row. The dedup
        // lives at the cubit layer (`VerifySeedCubit.verify` is invoked once
        // per successful quiz). Surfaces a regression where commit silently
        // dedups and a follow-up caller assumes idempotence.
        when(() => repo.createWallet(any(), any(), any(), any())).thenAnswer((_) async => 1);

        final draft = await service.generateUncommittedSeedWallet('Main');
        await service.commitGeneratedWallet(draft);

        verify(() => repo.createWallet(any(), any(), any(), any())).called(1);
      });

      test('does not set the wallet as current (caller is responsible)', () async {
        when(() => repo.createWallet(any(), any(), any(), any())).thenAnswer((_) async => 7);

        final draft = await service.generateUncommittedSeedWallet('Main');
        await service.commitGeneratedWallet(draft);

        verifyNever(() => settings.saveCurrentWalletId(any()));
      });

      // The `assert(draft.id == 0)` is a dev-only invariant guarding against
      // double-commit / wrong-caller — surfaces loudly in tests so a future
      // refactor can't silently regress the precondition. In release the
      // assert is stripped and the draft's seed is re-used; this test pins
      // the dev behaviour, not the release behaviour.
      test('asserts that the draft carries the id=0 sentinel', () async {
        final draft = SoftwareWallet(99, 'Main', _testMnemonic);

        expect(
          () => service.commitGeneratedWallet(draft),
          throwsA(isA<AssertionError>()),
          reason:
              'committing a draft that already carries a non-zero id is a '
              'programmer error (double-commit / wrong caller)',
        );
      });
    });

    group('createSeedWallet', () {
      test(
        'generate+commit convenience — persists a freshly generated mnemonic in one call',
        () async {
          when(() => repo.createWallet(any(), any(), any(), any())).thenAnswer((_) async => 42);

          final wallet = await service.createSeedWallet('Main');

          expect(wallet, isA<SoftwareWallet>());
          expect(wallet.id, 42);
          expect(wallet.name, 'Main');
          // Generated mnemonic must be valid bip39.
          expect(service.validateSeed(wallet.seed), isTrue);
          // Address from the wallet must match what was stored in the repo.
          final expectedAddress = wallet.currentAccount.primaryAddress.address.hexEip55;
          verify(
            () => repo.createWallet('Main', WalletType.software, wallet.seed, expectedAddress),
          ).called(1);
        },
      );

      test('does not set the wallet as current (caller is responsible)', () async {
        when(() => repo.createWallet(any(), any(), any(), any())).thenAnswer((_) async => 42);

        await service.createSeedWallet('Main');

        verifyNever(() => settings.saveCurrentWalletId(any()));
      });
    });

    group('restoreWallet', () {
      test('persists the provided seed and marks the wallet as current', () async {
        when(() => repo.createWallet(any(), any(), any(), any())).thenAnswer((_) async => 7);

        final wallet = await service.restoreWallet('Restored', _testMnemonic);

        expect(wallet.id, 7);
        expect(wallet.name, 'Restored');
        expect(wallet.seed, _testMnemonic);
        final expectedAddress = wallet.currentAccount.primaryAddress.address.hexEip55;
        verify(
          () => repo.createWallet('Restored', WalletType.software, _testMnemonic, expectedAddress),
        ).called(1);
        verify(() => settings.saveCurrentWalletId(7)).called(1);
      });
    });

    group('createBitboxWallet', () {
      // Drives the BitBox-pairing happy path end-to-end at this layer: fetch
      // the EIP-55 address from the device via the retry boundary, persist a
      // view-row in `walletInfos` (encrypted-seed column is `null` for hardware
      // wallets), mark the row current, and return a typed BitboxWallet so the
      // caller can immediately request a signature in the same flow.

      test('fetches the ETH address via the service boundary and persists a view row', () async {
        when(() => bitbox.getEthAddress()).thenAnswer((_) async => _debugAddress);
        when(() => repo.createViewWallet(any(), any(), any())).thenAnswer((_) async => 11);
        // BitboxWallet ctor pulls credentials from the service — return a
        // fake handle so the test exercises the WalletService logic and not
        // the credentials-cache plumbing (covered by the bitbox suite).
        when(() => bitbox.getCredentials(any())).thenReturn(BitboxCredentials(_debugAddress));

        final wallet = await service.createBitboxWallet('Hardware');

        expect(wallet, isA<BitboxWallet>());
        expect(wallet.id, 11);
        expect(wallet.name, 'Hardware');
        // The address fetch goes through the centralised retry boundary, not a
        // raw manager call — that's where the empty-read self-heal lives.
        verify(() => bitbox.getEthAddress()).called(1);
        verify(
          () => repo.createViewWallet('Hardware', WalletType.bitbox, _debugAddress),
        ).called(1);
        // BitBox flow must persist the wallet as current so the next reload
        // lands on the dashboard rather than the onboarding chooser.
        verify(() => settings.saveCurrentWalletId(11)).called(1);
      });

      test('normalizes the device address before persisting and returning it', () async {
        final normalized = EthereumAddress.fromHex(_lowercaseAddress).hexEip55;
        when(() => bitbox.getEthAddress()).thenAnswer((_) async => _lowercaseAddress);
        when(() => repo.createViewWallet(any(), any(), any())).thenAnswer((_) async => 12);
        when(
          () => bitbox.getCredentials(any()),
        ).thenReturn(BitboxCredentials(_lowercaseAddress));

        final wallet = await service.createBitboxWallet('Hardware');

        expect(wallet.currentAccount.primaryAddress.address.hexEip55, normalized);
        verify(
          () => repo.createViewWallet('Hardware', WalletType.bitbox, normalized),
        ).called(1);
      });

      test('accepts a checksum-invalid mixed-case device address', () async {
        final normalized = EthereumAddress.fromHex(
          _invalidMixedCaseAddress.toLowerCase(),
        ).hexEip55;
        when(
          () => bitbox.getEthAddress(),
        ).thenAnswer((_) async => _invalidMixedCaseAddress);
        when(() => repo.createViewWallet(any(), any(), any())).thenAnswer((_) async => 13);
        when(
          () => bitbox.getCredentials(any()),
        ).thenReturn(BitboxCredentials(normalized));

        final wallet = await service.createBitboxWallet('Hardware');

        expect(wallet.currentAccount.primaryAddress.address.hexEip55, normalized);
        verify(
          () => repo.createViewWallet('Hardware', WalletType.bitbox, normalized),
        ).called(1);
      });

      test('propagates a BitBox derivation failure without writing to the repo', () async {
        when(() => bitbox.getEthAddress()).thenThrow(Exception('USB transport dropped'));

        expect(
          () => service.createBitboxWallet('Hardware'),
          throwsA(isA<Exception>()),
        );
        verifyNever(() => repo.createViewWallet(any(), any(), any()));
        verifyNever(() => settings.saveCurrentWalletId(any()));
      });

      // The retry boundary throws on a persistent empty read; createBitboxWallet
      // must propagate it so nothing lands on disk and the pairing flow's retry
      // path takes over.
      test('propagates BitboxAddressUnavailableException from the boundary — nothing persisted',
          () async {
        when(() => bitbox.getEthAddress()).thenThrow(const BitboxAddressUnavailableException());

        await expectLater(
          () => service.createBitboxWallet('Hardware'),
          throwsA(isA<BitboxAddressUnavailableException>()),
        );
        verifyNever(() => repo.createViewWallet(any(), any(), any()));
        verifyNever(() => settings.saveCurrentWalletId(any()));
      });

      // Defence-in-depth: the boundary can't be empty, but a non-empty yet
      // malformed read still has to be rejected by the format guard before
      // `EthereumAddress.fromHex` would crash the dashboard build.
      test('throws BitboxAddressUnavailableException on a malformed address', () async {
        when(() => bitbox.getEthAddress()).thenAnswer((_) async => 'not-a-hex-address');

        await expectLater(
          () => service.createBitboxWallet('Hardware'),
          throwsA(isA<BitboxAddressUnavailableException>()),
        );
        verifyNever(() => repo.createViewWallet(any(), any(), any()));
        verifyNever(() => settings.saveCurrentWalletId(any()));
      });
    });

    group('acquireUncommittedBitboxWallet', () {
      test(
        'returns a draft BitboxWallet with id=0 and does NOT insert or switch',
        () async {
          when(() => bitbox.getEthAddress()).thenAnswer((_) async => _debugAddress);
          when(() => bitbox.getCredentials(any())).thenReturn(BitboxCredentials(_debugAddress));

          final draft = await service.acquireUncommittedBitboxWallet('Migration');

          expect(draft, isA<BitboxWallet>());
          expect(
            draft.id,
            0,
            reason:
                'uncommitted drafts use the 0 sentinel until persistBitboxWallet lands the row',
          );
          expect(draft.name, 'Migration');
          expect(
            draft.primaryAccount.primaryAddress.address.hexEip55,
            BitboxCredentials(_debugAddress).address.hexEip55,
          );
          verify(() => bitbox.getEthAddress()).called(1);
          verifyNever(() => repo.createViewWallet(any(), any(), any()));
          verifyNever(() => settings.saveCurrentWalletId(any()));
        },
      );

      test('normalizes the device address in the uncommitted draft', () async {
        final normalized = EthereumAddress.fromHex(_lowercaseAddress).hexEip55;
        when(() => bitbox.getEthAddress()).thenAnswer((_) async => _lowercaseAddress);
        when(
          () => bitbox.getCredentials(any()),
        ).thenReturn(BitboxCredentials(_lowercaseAddress));

        final draft = await service.acquireUncommittedBitboxWallet('Migration');

        expect(draft.currentAccount.primaryAddress.address.hexEip55, normalized);
      });

      test('accepts a checksum-invalid mixed-case address in the draft', () async {
        final normalized = EthereumAddress.fromHex(
          _invalidMixedCaseAddress.toLowerCase(),
        ).hexEip55;
        when(
          () => bitbox.getEthAddress(),
        ).thenAnswer((_) async => _invalidMixedCaseAddress);
        when(
          () => bitbox.getCredentials(any()),
        ).thenReturn(BitboxCredentials(normalized));

        final draft = await service.acquireUncommittedBitboxWallet('Migration');

        expect(draft.currentAccount.primaryAddress.address.hexEip55, normalized);
        verifyNever(() => repo.createViewWallet(any(), any(), any()));
        verifyNever(() => settings.saveCurrentWalletId(any()));
      });

      test('throws BitboxAddressUnavailableException on a malformed address', () async {
        when(() => bitbox.getEthAddress()).thenAnswer((_) async => 'not-a-hex-address');

        await expectLater(
          () => service.acquireUncommittedBitboxWallet('Migration'),
          throwsA(isA<BitboxAddressUnavailableException>()),
        );
        verifyNever(() => repo.createViewWallet(any(), any(), any()));
        verifyNever(() => settings.saveCurrentWalletId(any()));
      });

      test('throws BitboxAddressUnavailableException on an empty address', () async {
        when(() => bitbox.getEthAddress()).thenAnswer((_) async => '');

        await expectLater(
          () => service.acquireUncommittedBitboxWallet('Migration'),
          throwsA(isA<BitboxAddressUnavailableException>()),
        );
        verifyNever(() => repo.createViewWallet(any(), any(), any()));
        verifyNever(() => settings.saveCurrentWalletId(any()));
      });
    });

    group('persistBitboxWallet', () {
      setUp(() {
        when(() => bitbox.getCredentials(any())).thenReturn(BitboxCredentials(_debugAddress));
      });

      test('inserts a new BitBox view row when no existing row matches the address', () async {
        when(() => repo.getBitboxWalletIdByAddress(any())).thenAnswer((_) async => null);
        when(() => repo.createViewWallet(any(), any(), any())).thenAnswer((_) async => 33);

        final draft = BitboxWallet(0, 'Migration', _debugAddress, bitbox);
        final persisted = await service.persistBitboxWallet(draft);

        expect(persisted.id, 33);
        expect(persisted.name, 'Migration');
        verify(() => repo.getBitboxWalletIdByAddress(any())).called(1);
        verify(
          () => repo.createViewWallet('Migration', WalletType.bitbox, any()),
        ).called(1);
        // Migration commits the row WITHOUT switching current wallet — the
        // wizard switches only after the funds move completes.
        verifyNever(() => settings.saveCurrentWalletId(any()));
      });

      test(
        'reuses a legacy lowercase BitBox row for the normalized incoming address',
        () async {
          final normalized = EthereumAddress.fromHex(_lowercaseAddress).hexEip55;
          when(
            () => bitbox.getCredentials(any()),
          ).thenReturn(BitboxCredentials(_lowercaseAddress));
          when(
            () => repo.getBitboxWalletIdByAddress(normalized),
          ).thenAnswer((_) async => 17);

          final draft = BitboxWallet(0, 'Migration', _lowercaseAddress, bitbox);
          final persisted = await service.persistBitboxWallet(draft);

          expect(persisted.id, 17);
          expect(persisted.name, 'Migration');
          verify(() => repo.getBitboxWalletIdByAddress(normalized)).called(1);
          verifyNever(() => repo.createViewWallet(any(), any(), any()));
          verifyNever(() => settings.saveCurrentWalletId(any()));
        },
      );

      test('asserts that the draft carries the id=0 sentinel', () async {
        final alreadyPersisted = BitboxWallet(99, 'Migration', _debugAddress, bitbox);

        await expectLater(
          () => service.persistBitboxWallet(alreadyPersisted),
          throwsA(isA<AssertionError>()),
        );
      });
    });

    group('currentWalletNeedsAddressRecovery', () {
      test('true for a BitBox row persisted with an empty address', () async {
        when(() => settings.currentWalletId).thenReturn(5);
        when(() => repo.getWalletInfo(5)).thenAnswer(
          (_) async => _info(id: 5, name: 'Hardware', address: '', type: WalletType.bitbox),
        );

        expect(await service.currentWalletNeedsAddressRecovery(), isTrue);
      });

      test('true for a BitBox row persisted with a malformed address', () async {
        when(() => settings.currentWalletId).thenReturn(5);
        when(() => repo.getWalletInfo(5)).thenAnswer(
          (_) async => _info(id: 5, name: 'Hardware', address: 'garbage', type: WalletType.bitbox),
        );

        expect(await service.currentWalletNeedsAddressRecovery(), isTrue);
      });

      test('false for a BitBox row with a valid address', () async {
        when(() => settings.currentWalletId).thenReturn(5);
        when(() => repo.getWalletInfo(5)).thenAnswer(
          (_) async =>
              _info(id: 5, name: 'Hardware', address: _debugAddress, type: WalletType.bitbox),
        );

        expect(await service.currentWalletNeedsAddressRecovery(), isFalse);
      });

      test('false for a software wallet even with an empty address', () async {
        when(() => settings.currentWalletId).thenReturn(5);
        when(() => repo.getWalletInfo(5)).thenAnswer(
          (_) async => _info(id: 5, name: 'Main', address: '', type: WalletType.software),
        );

        expect(await service.currentWalletNeedsAddressRecovery(), isFalse);
      });

      test('false when no current wallet id is set', () async {
        when(() => settings.currentWalletId).thenReturn(null);

        expect(await service.currentWalletNeedsAddressRecovery(), isFalse);
        verifyNever(() => repo.getWalletInfo(any()));
      });

      test('false when the row is missing', () async {
        when(() => settings.currentWalletId).thenReturn(5);
        when(() => repo.getWalletInfo(5)).thenAnswer((_) async => null);

        expect(await service.currentWalletNeedsAddressRecovery(), isFalse);
      });
    });

    group('healCurrentBitboxAddress', () {
      setUp(() {
        when(() => bitbox.getCredentials(any())).thenReturn(BitboxCredentials(_debugAddress));
      });

      test('re-derives the address, backfills the row, and returns a BitboxWallet', () async {
        when(() => settings.currentWalletId).thenReturn(5);
        when(() => repo.getWalletInfo(5)).thenAnswer(
          (_) async => _info(id: 5, name: 'Hardware', address: '', type: WalletType.bitbox),
        );
        when(() => bitbox.getEthAddress()).thenAnswer((_) async => _debugAddress);

        final wallet = await service.healCurrentBitboxAddress();

        expect(wallet, isA<BitboxWallet>());
        expect(wallet.id, 5);
        expect(wallet.name, 'Hardware');
        verify(() => bitbox.getEthAddress()).called(1);
        verify(() => repo.updateAddress(5, _debugAddress)).called(1);
      });

      test('normalizes a lowercase device address to EIP-55 before persisting', () async {
        const lowercase = '0xbc6a215909b7c412eea434389c34cd2600aa1260';
        final checksummed = EthereumAddress.fromHex(lowercase).hexEip55;
        when(() => settings.currentWalletId).thenReturn(5);
        when(() => repo.getWalletInfo(5)).thenAnswer(
          (_) async => _info(id: 5, name: 'Hardware', address: '', type: WalletType.bitbox),
        );
        when(() => bitbox.getEthAddress()).thenAnswer((_) async => lowercase);
        when(() => bitbox.getCredentials(any())).thenReturn(BitboxCredentials(checksummed));

        final wallet = await service.healCurrentBitboxAddress();

        expect(wallet.currentAccount.primaryAddress.address.hexEip55, checksummed);
        verify(() => repo.updateAddress(5, checksummed)).called(1);
      });

      test('accepts a checksum-invalid mixed-case address when healing', () async {
        final normalized = EthereumAddress.fromHex(
          _invalidMixedCaseAddress.toLowerCase(),
        ).hexEip55;
        when(() => settings.currentWalletId).thenReturn(5);
        when(() => repo.getWalletInfo(5)).thenAnswer(
          (_) async => _info(id: 5, name: 'Hardware', address: '', type: WalletType.bitbox),
        );
        when(
          () => bitbox.getEthAddress(),
        ).thenAnswer((_) async => _invalidMixedCaseAddress);
        when(
          () => bitbox.getCredentials(any()),
        ).thenReturn(BitboxCredentials(normalized));

        final wallet = await service.healCurrentBitboxAddress();

        expect(wallet.currentAccount.primaryAddress.address.hexEip55, normalized);
        verify(() => repo.updateAddress(5, normalized)).called(1);
      });

      test('propagates BitboxAddressUnavailableException and does NOT persist', () async {
        when(() => settings.currentWalletId).thenReturn(5);
        when(() => repo.getWalletInfo(5)).thenAnswer(
          (_) async => _info(id: 5, name: 'Hardware', address: '', type: WalletType.bitbox),
        );
        when(() => bitbox.getEthAddress()).thenThrow(const BitboxAddressUnavailableException());

        await expectLater(
          () => service.healCurrentBitboxAddress(),
          throwsA(isA<BitboxAddressUnavailableException>()),
        );
        verifyNever(() => repo.updateAddress(any(), any()));
      });
    });

    group('createDebugWallet', () {
      test('persists a view wallet and marks it current', () async {
        when(() => repo.createViewWallet(any(), any(), any())).thenAnswer((_) async => 99);

        final wallet = await service.createDebugWallet(_debugAddress);

        expect(wallet, isA<DebugWallet>());
        expect(wallet.id, 99);
        expect(wallet.address, _debugAddress);
        verify(() => repo.createViewWallet('Debug', WalletType.debug, _debugAddress)).called(1);
        verify(() => settings.saveCurrentWalletId(99)).called(1);
      });
    });

    group('getWalletById', () {
      test('returns SoftwareViewWallet (address only) for cached-address software rows', () async {
        when(() => repo.getWalletInfo(1)).thenAnswer(
          (_) async => _info(
            id: 1,
            name: 'Main',
            address: _debugAddress,
            type: WalletType.software,
          ),
        );

        final wallet = await service.getWalletById(1);

        expect(wallet, isA<SoftwareViewWallet>());
        verifyNever(() => repo.getUnlockedWalletById(any()));
      });

      test(
        'falls back to unlocked SoftwareWallet for legacy rows and backfills the address',
        () async {
          when(() => repo.getWalletInfo(1)).thenAnswer(
            (_) async => _info(id: 1, name: 'Main', type: WalletType.software),
          );
          when(() => repo.getUnlockedWalletById(1)).thenAnswer(
            (_) async => _info(id: 1, name: 'Main', seed: _testMnemonic, type: WalletType.software),
          );

          final wallet = await service.getWalletById(1);

          expect(wallet, isA<SoftwareWallet>());
          expect((wallet as SoftwareWallet).seed, _testMnemonic);
          // The next load takes the fast path because the address has been
          // backfilled into the row.
          verify(
            () => repo.updateAddress(1, wallet.currentAccount.primaryAddress.address.hexEip55),
          ).called(1);
        },
      );

      test('returns a BitboxWallet for bitbox type — never decrypts a seed', () async {
        when(() => repo.getWalletInfo(3)).thenAnswer(
          (_) async => _info(
            id: 3,
            name: 'Hardware',
            address: _debugAddress,
            type: WalletType.bitbox,
          ),
        );
        when(() => bitbox.getCredentials(any())).thenReturn(BitboxCredentials(_debugAddress));
        // Pin the contract: a hardware-wallet row never goes through the
        // mnemonic-decrypt path. If a future refactor accidentally routes
        // a bitbox row through `getUnlockedWalletById`, this verifyNever
        // catches it.
        final wallet = await service.getWalletById(3);

        expect(wallet, isA<BitboxWallet>());
        expect(wallet.id, 3);
        expect(wallet.name, 'Hardware');
        verifyNever(() => repo.getUnlockedWalletById(any()));
      });

      test('returns DebugWallet for debug type', () async {
        when(() => repo.getWalletInfo(2)).thenAnswer(
          (_) async => _info(id: 2, name: 'Debug', address: _debugAddress, type: WalletType.debug),
        );

        final wallet = await service.getWalletById(2);

        expect(wallet, isA<DebugWallet>());
        expect((wallet as DebugWallet).address, _debugAddress);
      });

      test('throws when the repository returns null (no such id)', () async {
        when(() => repo.getWalletInfo(404)).thenAnswer((_) async => null);

        expect(() => service.getWalletById(404), throwsA(isA<TypeError>()));
      });
    });

    group('unlockWalletById', () {
      test('returns a fully unlocked SoftwareWallet', () async {
        when(() => repo.getUnlockedWalletById(1)).thenAnswer(
          (_) async => _info(id: 1, name: 'Main', seed: _testMnemonic, type: WalletType.software),
        );

        final wallet = await service.unlockWalletById(1);

        expect(wallet, isA<SoftwareWallet>());
        expect(wallet.seed, _testMnemonic);
      });

      test('throws for non-software wallet types', () async {
        when(() => repo.getUnlockedWalletById(2)).thenAnswer(
          (_) async => _info(id: 2, name: 'BBox', address: _debugAddress, type: WalletType.bitbox),
        );

        expect(() => service.unlockWalletById(2), throwsA(isA<StateError>()));
      });
    });

    group('setCurrentWallet', () {
      test('delegates to SettingsRepository.saveCurrentWalletId', () async {
        await service.setCurrentWallet(5);

        verify(() => settings.saveCurrentWalletId(5)).called(1);
      });
    });

    group('getCurrentWallet', () {
      test('reads the current id and resolves it through getWalletById', () async {
        when(() => settings.currentWalletId).thenReturn(3);
        when(() => repo.getWalletInfo(3)).thenAnswer(
          (_) async => _info(
            id: 3,
            name: 'Saved',
            address: _debugAddress,
            type: WalletType.software,
          ),
        );

        final wallet = await service.getCurrentWallet();

        expect(wallet.id, 3);
        expect(wallet.name, 'Saved');
      });

      test('throws when no current id is set', () async {
        when(() => settings.currentWalletId).thenReturn(null);

        expect(() => service.getCurrentWallet(), throwsA(isA<TypeError>()));
      });
    });

    group('unlockCurrentWallet', () {
      test('reads the current id and resolves it through unlockWalletById', () async {
        when(() => settings.currentWalletId).thenReturn(3);
        when(() => repo.getUnlockedWalletById(3)).thenAnswer(
          (_) async => _info(id: 3, name: 'Saved', seed: _testMnemonic, type: WalletType.software),
        );

        final wallet = await service.unlockCurrentWallet();

        expect(wallet, isA<SoftwareWallet>());
        expect(wallet.seed, _testMnemonic);
      });
    });

    group('deleteCurrentWallet', () {
      test('deletes the wallet and clears the current-id setting', () async {
        when(() => settings.currentWalletId).thenReturn(8);

        await service.deleteCurrentWallet();

        // User-facing delete must fully purge (seed row + mnemonic key), not
        // the account-only delete.
        verify(() => repo.purgeWallet(8)).called(1);
        verifyNever(() => repo.deleteWallet(any()));
        verify(() => settings.removeCurrentWalletId()).called(1);
      });
    });

    group('hasWallet', () {
      test('returns true when a current id is set', () {
        when(() => settings.currentWalletId).thenReturn(1);

        expect(service.hasWallet(), isTrue);
      });

      test('returns false when no current id is set', () {
        when(() => settings.currentWalletId).thenReturn(null);

        expect(service.hasWallet(), isFalse);
      });
    });

    group('validateSeed', () {
      test('accepts a valid bip39 mnemonic', () {
        expect(service.validateSeed(_testMnemonic), isTrue);
      });

      test('rejects an obviously invalid mnemonic', () {
        expect(service.validateSeed('not a valid seed phrase at all'), isFalse);
      });

      test('rejects an empty string', () {
        expect(service.validateSeed(''), isFalse);
      });

      test('rejects a mnemonic with a wrong checksum word', () {
        // Replace the final checksum word with a different valid bip39 word.
        const broken = 'test test test test test test test test test test test ability';
        expect(service.validateSeed(broken), isFalse);
      });
    });

    group('ensureCurrentWalletUnlocked', () {
      test('promotes a SoftwareViewWallet to a SoftwareWallet', () async {
        final view = SoftwareViewWallet(7, 'Main', _debugAddress);
        final stored = <AWallet>[view];
        when(() => appStore.wallet).thenAnswer((_) => stored.last);
        when(() => appStore.wallet = any(that: isA<AWallet>())).thenAnswer((inv) {
          final newWallet = inv.positionalArguments.single as AWallet;
          stored.add(newWallet);
          return newWallet;
        });
        when(() => settings.currentWalletId).thenReturn(7);
        when(() => repo.getUnlockedWalletById(7)).thenAnswer(
          (_) async => _info(id: 7, name: 'Main', seed: _testMnemonic, type: WalletType.software),
        );

        await service.ensureCurrentWalletUnlocked();

        expect(stored.last, isA<SoftwareWallet>());
        expect((stored.last as SoftwareWallet).seed, _testMnemonic);
      });

      test('is a no-op when the current wallet is not a SoftwareViewWallet', () async {
        final unlocked = SoftwareWallet(7, 'Main', _testMnemonic);
        when(() => appStore.wallet).thenReturn(unlocked);

        await service.ensureCurrentWalletUnlocked();

        verifyNever(() => repo.getUnlockedWalletById(any()));
      });
    });

    group('lockCurrentWallet', () {
      // Tests in this group assume a loaded wallet — the "no wallet loaded
      // yet" path is explicitly tested below by overriding to false.
      setUp(() {
        when(() => appStore.isWalletLoaded).thenReturn(true);
      });

      test('replaces an unlocked SoftwareWallet with its SoftwareViewWallet counterpart', () async {
        final unlocked = SoftwareWallet(9, 'Main', _testMnemonic);
        AWallet? written;
        when(() => appStore.wallet).thenReturn(unlocked);
        when(() => appStore.wallet = any(that: isA<AWallet>())).thenAnswer((inv) {
          final newWallet = inv.positionalArguments.single as AWallet;
          written = newWallet;
          return newWallet;
        });

        await service.lockCurrentWallet();

        expect(written, isA<SoftwareViewWallet>());
        expect(written!.id, 9);
        expect(written!.name, 'Main');
      });

      test('is a no-op when the wallet is already locked / not software', () async {
        when(() => appStore.wallet).thenReturn(
          SoftwareViewWallet(9, 'Main', _debugAddress),
        );

        await service.lockCurrentWallet();

        // No write happened.
        verifyNever(() => appStore.wallet = any(that: isA<AWallet>()));
      });

      // Pre-load guard: the app-lifecycle `hidden` hook fires the first time
      // the user backgrounds the app, which can happen during onboarding
      // before HomeBloc has populated AppStore.wallet. The early-return on
      // !isWalletLoaded keeps the lifecycle caller a one-liner — no try/catch
      // around an "expected" Exception('No Wallet set') from appStore.wallet.
      test('is a no-op when no wallet has been loaded yet', () async {
        when(() => appStore.isWalletLoaded).thenReturn(false);

        await service.lockCurrentWallet();

        // Never even reaches the wallet getter — no MissingStubError, no
        // write, no exception leaking to the unawaited caller.
        verifyNever(() => appStore.wallet);
        verifyNever(() => appStore.wallet = any(that: isA<AWallet>()));
      });
    });

    group('ensure/lock reentrancy', () {
      // Tests in this group exercise lockCurrentWallet end-to-end, so the
      // pre-load guard expects a positive isWalletLoaded.
      setUp(() {
        when(() => appStore.isWalletLoaded).thenReturn(true);
      });

      // App-lifecycle hidden fires an unpaired lockCurrentWallet — i.e. one
      // without a matching prior ensureCurrentWalletUnlocked. Sequence:
      //   flow X ensure → counter 1, wallet unlocked
      //   _onHidden lock → counter 0, wallet flipped to view
      //   flow X finally lock → counter still 0 (underflow guard), _lockWalletInPlace
      //     no-ops because the wallet is already the view form.
      // The 1:1 ensure↔lock invariant is technically broken by the unpaired
      // lifecycle call, but the underflow guard + `is! SoftwareWallet` guard
      // keep the state consistent. This test pins that contract.
      test('unpaired lock from lifecycle leaves the holder counter at 0, never below', () async {
        final stored = <AWallet>[SoftwareViewWallet(7, 'Main', _debugAddress)];
        when(() => appStore.wallet).thenAnswer((_) => stored.last);
        when(() => appStore.wallet = any(that: isA<AWallet>())).thenAnswer((inv) {
          final newWallet = inv.positionalArguments.single as AWallet;
          stored.add(newWallet);
          return newWallet;
        });
        when(() => settings.currentWalletId).thenReturn(7);
        when(() => repo.getUnlockedWalletById(7)).thenAnswer(
          (_) async => _info(id: 7, name: 'Main', seed: _testMnemonic, type: WalletType.software),
        );

        // Sign flow opens the contract.
        await service.ensureCurrentWalletUnlocked();
        expect(stored.last, isA<SoftwareWallet>(), reason: 'sign flow unlocked the wallet');

        // App-lifecycle hidden fires concurrently — drops to view wallet.
        await service.lockCurrentWallet();
        expect(
          stored.last,
          isA<SoftwareViewWallet>(),
          reason: 'lifecycle lock flipped the wallet to its view form',
        );

        // Sign flow finally — counter is already 0, must NOT underflow and
        // must NOT crash on _lockWalletInPlace reading the (now view) wallet.
        await service.lockCurrentWallet();
        expect(
          stored.last,
          isA<SoftwareViewWallet>(),
          reason: 'finally lock is idempotent — counter stays at 0',
        );

        // A subsequent ensure must still produce a usable unlocked wallet —
        // i.e. the counter didn't drift negative and break the next cycle.
        await service.ensureCurrentWalletUnlocked();
        expect(
          stored.last,
          isA<SoftwareWallet>(),
          reason: 'next ensure starts cleanly from counter == 0',
        );
      });

      // Race: flow A and flow B both call ensureCurrentWalletUnlocked while
      // the wallet is locked. A finishes its sign + lock first; B is still
      // mid-sign and must see an unlocked wallet. Without the holder counter
      // A's lock would tear the mnemonic out from under B and the next
      // sign call would hit _LockedCredentials → UnsupportedError.
      test('two parallel ensures + one lock leave the wallet unlocked', () async {
        final stored = <AWallet>[SoftwareViewWallet(7, 'Main', _debugAddress)];
        when(() => appStore.wallet).thenAnswer((_) => stored.last);
        when(() => appStore.wallet = any(that: isA<AWallet>())).thenAnswer((inv) {
          final newWallet = inv.positionalArguments.single as AWallet;
          stored.add(newWallet);
          return newWallet;
        });
        when(() => settings.currentWalletId).thenReturn(7);
        when(() => repo.getUnlockedWalletById(7)).thenAnswer(
          (_) async => _info(id: 7, name: 'Main', seed: _testMnemonic, type: WalletType.software),
        );

        // Flow A: ensure + lock (e.g. confirmPayment finishing first).
        await service.ensureCurrentWalletUnlocked();
        // Flow B enters its ensure while A is still holding the contract.
        await service.ensureCurrentWalletUnlocked();
        // Flow A releases — B still holds, so the wallet must stay unlocked.
        await service.lockCurrentWallet();

        expect(
          stored.last,
          isA<SoftwareWallet>(),
          reason: 'second holder must keep the wallet unlocked',
        );

        // Flow B releases — now the wallet locks back to the view form.
        await service.lockCurrentWallet();
        expect(
          stored.last,
          isA<SoftwareViewWallet>(),
          reason: 'last holder release flips back to view wallet',
        );
      });

      // Genuine concurrency race: both ensures are pending on the DB read
      // when the lock fires between them. Without the holder counter the
      // lock would observe the (mid-unlock) view wallet, no-op, and the
      // second ensure would then complete and write the unlocked wallet —
      // which then never gets locked back because lockCurrentWallet
      // already returned. With the counter, the lock decrements but does
      // not flip the wallet because two ensures are still in flight.
      test('lock between two in-flight ensures preserves the unlocked wallet', () async {
        final stored = <AWallet>[SoftwareViewWallet(7, 'Main', _debugAddress)];
        when(() => appStore.wallet).thenAnswer((_) => stored.last);
        when(() => appStore.wallet = any(that: isA<AWallet>())).thenAnswer((inv) {
          final newWallet = inv.positionalArguments.single as AWallet;
          stored.add(newWallet);
          return newWallet;
        });
        when(() => settings.currentWalletId).thenReturn(7);

        // Gate the repository read so we can interleave concurrent calls.
        final gate = Completer<WalletInfo>();
        when(() => repo.getUnlockedWalletById(7)).thenAnswer((_) => gate.future);

        // Fire two ensures without awaiting — both block on the gated read.
        final ensureA = service.ensureCurrentWalletUnlocked();
        final ensureB = service.ensureCurrentWalletUnlocked();

        // Flow A releases its hold while both unlocks are still pending.
        // The counter must keep the wallet from being flipped back to a
        // view wallet because flow B is still holding the contract.
        await service.lockCurrentWallet();

        // Release the gated read so both ensures can complete.
        gate.complete(
          _info(id: 7, name: 'Main', seed: _testMnemonic, type: WalletType.software),
        );
        await Future.wait([ensureA, ensureB]);

        expect(
          stored.last,
          isA<SoftwareWallet>(),
          reason: 'lock fired mid-unlock must not shadow the in-flight unlock',
        );

        // Drain the remaining holders. Two more locks: one to match the
        // second ensure's release, one to confirm the counter clamps at 0
        // and doesn't go negative.
        await service.lockCurrentWallet();
        await service.lockCurrentWallet();
        expect(
          stored.last,
          isA<SoftwareViewWallet>(),
          reason: 'final holder release flips back to view wallet',
        );
      });

      // The `_onHidden` race: a single sign-flow ensure is still mid-unlock
      // when `lockCurrentWallet` fires from the app-lifecycle hidden hook.
      // Without invalidating the in-flight unlock, its resolution would
      // write the unlocked [SoftwareWallet] back to [AppStore.wallet]
      // AFTER the lock — resurfacing the mnemonic in memory until either
      // the 60s safety net or the sign-flow `finally lock` clears it
      // again. The 60s window is best-effort under iOS isolate suspension
      // (the gap #485 set out to close in the first place), so the fix
      // closes it at the source: the lock invalidates `_unlockInFlight`
      // and the ensure skips its write.
      test('lock during a single in-flight unlock does not resurface the mnemonic', () async {
        final stored = <AWallet>[SoftwareViewWallet(7, 'Main', _debugAddress)];
        when(() => appStore.wallet).thenAnswer((_) => stored.last);
        when(() => appStore.wallet = any(that: isA<AWallet>())).thenAnswer((inv) {
          final newWallet = inv.positionalArguments.single as AWallet;
          stored.add(newWallet);
          return newWallet;
        });
        when(() => settings.currentWalletId).thenReturn(7);

        // Pin the unlock mid-flight so we can fire `lockCurrentWallet`
        // exactly between the ensure starting and its DB read resolving.
        final gate = Completer<WalletInfo>();
        when(() => repo.getUnlockedWalletById(7)).thenAnswer((_) => gate.future);

        // Sign-flow ensure starts, counter=1, blocks on gated read.
        final ensure = service.ensureCurrentWalletUnlocked();

        // App-lifecycle hidden fires — counter goes to 0, lock would
        // normally no-op (wallet still SoftwareViewWallet) and let the
        // pending unlock leak through.
        await service.lockCurrentWallet();
        expect(
          stored.last,
          isA<SoftwareViewWallet>(),
          reason: 'lock observed the still-view wallet — nothing to flip',
        );

        // Release the gated DB read so the in-flight ensure resolves.
        gate.complete(
          _info(id: 7, name: 'Main', seed: _testMnemonic, type: WalletType.software),
        );
        await ensure;

        // The fix: the post-resolve write is gated on the in-flight token
        // still matching, which the lock invalidated. So the mnemonic
        // never lands in [AppStore.wallet] after the user covered the app.
        expect(
          stored.last,
          isA<SoftwareViewWallet>(),
          reason:
              'in-flight unlock invalidated by intervening lock must not '
              'resurface the mnemonic',
        );
        // Pin the mechanism, not just the outcome: the `_unlockInFlight`
        // gate must suppress the post-resolve write — never let a future
        // refactor pass this test by tolerating the write and clearing it
        // again from somewhere else (which would still expose the mnemonic
        // to any code path observing `AppStore.wallet` between the writes).
        verifyNever(() => appStore.wallet = any(that: isA<SoftwareWallet>()));
      });

      // The 60s safety net is the hard cap on the in-memory mnemonic
      // lifetime — it bypasses [_activeUnlockHolders] so a stuck holder
      // can't keep the key resident past the safety window. fake_async
      // drives the wall-clock so we don't actually wait 60s; no
      // Future.delayed in the test.
      test('post-unlock timer force-locks after 60s even with a holder still open', () {
        fakeAsync((async) {
          final stored = <AWallet>[SoftwareViewWallet(7, 'Main', _debugAddress)];
          when(() => appStore.wallet).thenAnswer((_) => stored.last);
          when(() => appStore.wallet = any(that: isA<AWallet>())).thenAnswer((inv) {
            final newWallet = inv.positionalArguments.single as AWallet;
            stored.add(newWallet);
            return newWallet;
          });
          when(() => settings.currentWalletId).thenReturn(7);
          when(() => repo.getUnlockedWalletById(7)).thenAnswer(
            (_) async => _info(id: 7, name: 'Main', seed: _testMnemonic, type: WalletType.software),
          );

          // Open a holder — no matching lockCurrentWallet, so the counter
          // stays at 1. Only the 60s timer can flip back to view-wallet.
          service.ensureCurrentWalletUnlocked();
          async.flushMicrotasks();
          expect(
            stored.last,
            isA<SoftwareWallet>(),
            reason: 'sign-flow ensure must land an unlocked wallet first',
          );

          // Just shy of the timeout — still unlocked.
          async.elapse(const Duration(seconds: 59));
          expect(
            stored.last,
            isA<SoftwareWallet>(),
            reason: 'safety net must not fire before its window elapses',
          );

          // Cross the timeout — _forceLock bypasses the counter and flips
          // the wallet back to view form regardless of the open holder.
          async.elapse(const Duration(seconds: 2));
          expect(
            stored.last,
            isA<SoftwareViewWallet>(),
            reason: '_forceLock must zero the holder counter and drop the mnemonic',
          );

          // After the force-lock, the next ensure must still work — the
          // counter was reset to 0, not left dangling at some intermediate
          // value that would break the next cycle.
          service.ensureCurrentWalletUnlocked();
          async.flushMicrotasks();
          expect(
            stored.last,
            isA<SoftwareWallet>(),
            reason:
                'force-lock must leave the holder counter at 0 so the next '
                'unlock cycle starts cleanly',
          );

          // Drain the safety-net timer that the second ensure armed —
          // otherwise the fakeAsync `pendingTimers` assertion below would
          // flag a leak.
          async.elapse(const Duration(seconds: 61));
        });
      });

      // Each ensure re-arms the safety-net timer; the timeout window
      // extends to "60s after the latest ensure" rather than "60s after
      // the first ensure". Without re-arming, a long-running sign that
      // briefly re-checks the wallet would be cut off mid-flight.
      test('a second ensure re-arms the post-unlock timer', () {
        fakeAsync((async) {
          final stored = <AWallet>[SoftwareViewWallet(7, 'Main', _debugAddress)];
          when(() => appStore.wallet).thenAnswer((_) => stored.last);
          when(() => appStore.wallet = any(that: isA<AWallet>())).thenAnswer((inv) {
            final newWallet = inv.positionalArguments.single as AWallet;
            stored.add(newWallet);
            return newWallet;
          });
          when(() => settings.currentWalletId).thenReturn(7);
          when(() => repo.getUnlockedWalletById(7)).thenAnswer(
            (_) async => _info(id: 7, name: 'Main', seed: _testMnemonic, type: WalletType.software),
          );

          // First ensure arms the timer at t=0.
          service.ensureCurrentWalletUnlocked();
          async.flushMicrotasks();
          expect(stored.last, isA<SoftwareWallet>());

          // At t=40s, a second ensure must re-arm the timer to fire at t=100s.
          async.elapse(const Duration(seconds: 40));
          service.ensureCurrentWalletUnlocked();
          async.flushMicrotasks();

          // At t=80s the original timer would have fired (40s+60s=100s for
          // the rearmed one; original would have fired at t=60s). Verify the
          // wallet is still unlocked, i.e. the original timer was cancelled.
          async.elapse(const Duration(seconds: 40));
          expect(
            stored.last,
            isA<SoftwareWallet>(),
            reason:
                'second ensure must cancel the original timer and re-arm '
                'for another 60s — otherwise long-running signs would be cut off',
          );

          // At t=110s the re-armed timer (set at t=40s) has fired.
          async.elapse(const Duration(seconds: 30));
          expect(
            stored.last,
            isA<SoftwareViewWallet>(),
            reason:
                'the re-armed timer eventually fires at +60s from the '
                'most-recent ensure',
          );
        });
      });

      // Two overlapping ensures must coalesce onto a single DB read +
      // AES-GCM decrypt, not trigger the repository twice. Functionally
      // both versions would land on the same SoftwareWallet, but the
      // extra decrypt is wasteful.
      test('two parallel ensures dedupe the repository decrypt', () async {
        final stored = <AWallet>[SoftwareViewWallet(7, 'Main', _debugAddress)];
        when(() => appStore.wallet).thenAnswer((_) => stored.last);
        when(() => appStore.wallet = any(that: isA<AWallet>())).thenAnswer((inv) {
          final newWallet = inv.positionalArguments.single as AWallet;
          stored.add(newWallet);
          return newWallet;
        });
        when(() => settings.currentWalletId).thenReturn(7);

        final gate = Completer<WalletInfo>();
        when(() => repo.getUnlockedWalletById(7)).thenAnswer((_) => gate.future);

        final ensureA = service.ensureCurrentWalletUnlocked();
        final ensureB = service.ensureCurrentWalletUnlocked();

        gate.complete(
          _info(id: 7, name: 'Main', seed: _testMnemonic, type: WalletType.software),
        );
        await Future.wait([ensureA, ensureB]);

        verify(() => repo.getUnlockedWalletById(7)).called(1);
        expect(stored.last, isA<SoftwareWallet>());
      });
    });

    group('persistence failure resilience', () {
      test('commitGeneratedWallet propagates repository exception', () async {
        when(() => repo.createWallet(any(), any(), any(), any())).thenThrow(Exception('disk full'));

        final draft = await service.generateUncommittedSeedWallet('Main');

        expect(
          () => service.commitGeneratedWallet(draft),
          throwsA(isA<Exception>()),
        );
        verifyNever(() => settings.saveCurrentWalletId(any()));
      });

      test('restoreWallet propagates repository exception without setting current', () async {
        when(() => repo.createWallet(any(), any(), any(), any())).thenThrow(Exception('disk full'));

        expect(
          () => service.restoreWallet('Restored', _testMnemonic),
          throwsA(isA<Exception>()),
        );
        verifyNever(() => settings.saveCurrentWalletId(any()));
      });
    });
  });
}
