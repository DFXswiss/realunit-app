import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/models/balance.dart';
import 'package:realunit_wallet/packages/config/api_config.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/balance_service.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_kyc_service.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/address_already_linked_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/bitbox_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/models/registration/kyc/kyc_personal_data.dart';
import 'package:realunit_wallet/packages/service/dfx/models/registration/registration_status.dart';
import 'package:realunit_wallet/packages/service/dfx/models/user/dto/real_unit_user_data_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/wallet/real_unit_registration_info_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/wallet/real_unit_registration_state.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_registration_service.dart';
import 'package:realunit_wallet/packages/service/session_cache.dart';
import 'package:realunit_wallet/packages/service/wallet_service.dart';
import 'package:realunit_wallet/packages/utils/default_assets.dart';
import 'package:realunit_wallet/packages/wallet/exceptions/signing_cancelled_exception.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';
import 'package:realunit_wallet/packages/wallet/wallet_account.dart';
import 'package:realunit_wallet/screens/migrate_bitbox/cubits/migrate_bitbox/migrate_bitbox_cubit.dart';
import 'package:web3dart/web3dart.dart';

class _MockWalletService extends Mock implements WalletService {}

class _MockDfxKycService extends Mock implements DfxKycService {}

class _MockRegistrationService extends Mock implements RealUnitRegistrationService {}

class _MockBalanceService extends Mock implements BalanceService {}

class _MockAppStore extends Mock implements AppStore {}

class _MockSessionCache extends Mock implements SessionCache {}

class _MockApiConfig extends Mock implements ApiConfig {}

class _MockBitboxWallet extends Mock implements BitboxWallet {}

class _MockBitboxWalletAccount extends Mock implements BitboxWalletAccount {}

const _userData = RealUnitUserDataDto(
  email: 'ada@example.com',
  name: 'Ada Lovelace',
  type: 'HUMAN',
  phoneNumber: '+41 79 000 00 00',
  birthday: '1815-12-10',
  nationality: 'CH',
  addressStreet: 'Bahnhofstrasse 1',
  addressPostalCode: '8000',
  addressCity: 'Zurich',
  addressCountry: 'CH',
  swissTaxResidence: true,
  lang: 'de',
  kycData: KycPersonalData(
    accountType: KycAccountType.personal,
    firstName: 'Ada',
    lastName: 'Lovelace',
    phone: '+41 79 000 00 00',
    address: KycAddress(
      street: 'Bahnhofstrasse',
      zip: '8000',
      city: 'Zurich',
      country: 41,
    ),
  ),
);

void main() {
  const softwareAddress = '0x0000000000000000000000000000000000000001';
  const oldJwt = 'old-jwt';
  const newJwt = 'new-jwt';
  const signature = '0xsigned';

  late String draftAddress;
  late String persistedAddress;

  late _MockWalletService walletService;
  late _MockDfxKycService authService;
  late _MockRegistrationService registrationService;
  late _MockBalanceService balanceService;
  late _MockAppStore appStore;
  late _MockSessionCache sessionCache;
  late _MockApiConfig apiConfig;
  late _MockBitboxWallet draft;
  late _MockBitboxWallet persisted;
  late _MockBitboxWalletAccount draftAccount;
  late _MockBitboxWalletAccount persistedAccount;

  Balance balance(int amount) => Balance(
    chainId: realUnitAsset.chainId,
    contractAddress: realUnitAsset.address,
    walletAddress: softwareAddress,
    balance: BigInt.from(amount),
    asset: realUnitAsset,
  );

  RealUnitRegistrationInfoDto info(
    RealUnitRegistrationState state, {
    RealUnitUserDataDto? userData,
    bool? manualReview,
  }) => RealUnitRegistrationInfoDto(
    state: state,
    realUnitUserDataDto: userData,
    manualReview: manualReview,
  );

  setUpAll(() {
    registerFallbackValue(_MockBitboxWallet());
    registerFallbackValue(_MockBitboxWalletAccount());
    registerFallbackValue(_userData);
    registerFallbackValue(realUnitAsset);
  });

  setUp(() {
    walletService = _MockWalletService();
    authService = _MockDfxKycService();
    registrationService = _MockRegistrationService();
    balanceService = _MockBalanceService();
    appStore = _MockAppStore();
    sessionCache = _MockSessionCache();
    apiConfig = _MockApiConfig();
    draft = _MockBitboxWallet();
    persisted = _MockBitboxWallet();
    draftAccount = _MockBitboxWalletAccount();
    persistedAccount = _MockBitboxWalletAccount();

    final draftCredentials = EthPrivateKey.fromHex(
      'fb1ace12f9801e85f3db1b3935dd47d9f064f98152466f47c701b5e12680e612',
    );
    final persistedCredentials = EthPrivateKey.fromHex(
      '7d1d0f68f145b214e49c1a5c6c31a5570358ec80025c5d25f6a56f21fbe6342f',
    );
    draftAddress = draftCredentials.address.hexEip55;
    persistedAddress = persistedCredentials.address.hexEip55;
    when(() => draft.id).thenReturn(0);
    when(() => draft.currentAccount).thenReturn(draftAccount);
    when(() => draftAccount.primaryAddress).thenReturn(draftCredentials);
    when(() => persisted.id).thenReturn(42);
    when(() => persisted.currentAccount).thenReturn(persistedAccount);
    when(() => persistedAccount.primaryAddress).thenReturn(persistedCredentials);

    when(() => appStore.primaryAddress).thenReturn(softwareAddress);
    when(() => appStore.apiConfig).thenReturn(apiConfig);
    when(() => appStore.sessionCache).thenReturn(sessionCache);
    when(() => apiConfig.asset).thenReturn(realUnitAsset);
    when(() => sessionCache.signatureAddress).thenReturn(draftAddress);
    when(() => sessionCache.signature).thenReturn(signature);
    when(() => sessionCache.saveSignature(any(), any())).thenAnswer((_) async {});
    when(() => sessionCache.setAuthToken(any(), any())).thenReturn(null);

    when(() => authService.getAuthToken()).thenAnswer((_) async => oldJwt);
    when(
      () => authService.authenticateLinkedAccount(any(), any()),
    ).thenAnswer((_) async => newJwt);
    when(
      () => registrationService.getRegistrationInfoWith(any()),
    ).thenAnswer((_) async => info(RealUnitRegistrationState.alreadyRegistered));
    when(
      () => registrationService.registerWalletFor(any(), any(), any()),
    ).thenAnswer((_) async => RegistrationStatus.completed);
    when(() => walletService.persistBitboxWallet(any())).thenAnswer((_) async => persisted);
    when(() => walletService.setCurrentWallet(any())).thenAnswer((_) async {});
    when(() => balanceService.updateBalance(any())).thenAnswer((_) async {});
    when(
      () => balanceService.getBalance(any(), any()),
    ).thenAnswer((_) async => balance(5));
  });

  MigrateBitboxCubit buildCubit() {
    final cubit = MigrateBitboxCubit(
      walletService,
      authService,
      registrationService,
      balanceService,
      appStore,
    );
    addTearDown(cubit.close);
    return cubit;
  }

  Future<void> reachRegisterReady(MigrateBitboxCubit cubit) async {
    when(
      () => registrationService.getRegistrationInfoWith(any()),
    ).thenAnswer(
      (_) async => info(
        RealUnitRegistrationState.addWallet,
        userData: _userData,
      ),
    );
    await cubit.onDevicePaired(draft);
    expect(cubit.state, isA<MigrateBitboxRegisterReady>());
  }

  Future<void> reachTransferReady(MigrateBitboxCubit cubit) async {
    await cubit.onDevicePaired(draft);
    expect(cubit.state, isA<MigrateBitboxTransferReady>());
  }

  group('$MigrateBitboxCubit pairing', () {
    test('starts in Intro and startPairing emits AwaitingDevice', () async {
      final cubit = buildCubit();

      expect(cubit.state, const MigrateBitboxIntro());
      await cubit.startPairing();

      expect(cubit.state, const MigrateBitboxAwaitingDevice());
    });

    test('cancelPairing is effective only from AwaitingDevice', () async {
      final cubit = buildCubit();
      final emissions = <MigrateBitboxState>[];
      final subscription = cubit.stream.listen(emissions.add);
      addTearDown(subscription.cancel);

      cubit.cancelPairing();
      expect(emissions, isEmpty);

      await cubit.startPairing();
      cubit.cancelPairing();
      // Stream listeners are serviced on the microtask queue — flush it so
      // both emissions have reached the collector before asserting.
      await Future<void>.delayed(Duration.zero);

      expect(emissions, [const MigrateBitboxAwaitingDevice(), const MigrateBitboxIntro()]);
    });
  });

  group('$MigrateBitboxCubit onDevicePaired', () {
    test('matching cached signature and addWallet userData emit RegisterReady', () async {
      when(
        () => registrationService.getRegistrationInfoWith(newJwt),
      ).thenAnswer(
        (_) async => info(
          RealUnitRegistrationState.addWallet,
          userData: _userData,
        ),
      );
      final cubit = buildCubit();

      await cubit.onDevicePaired(draft);

      expect(
        cubit.state,
        MigrateBitboxRegisterReady(_userData, draftAddress),
      );
      verify(
        () => authService.authenticateLinkedAccount(draftAccount, oldJwt),
      ).called(1);
      verify(() => registrationService.getRegistrationInfoWith(newJwt)).called(1);
    });

    test('addWallet without userData fails loud and retry is a no-op', () async {
      when(
        () => registrationService.getRegistrationInfoWith(any()),
      ).thenAnswer((_) async => info(RealUnitRegistrationState.addWallet));
      final cubit = buildCubit();

      await cubit.onDevicePaired(draft);

      expect(
        cubit.state,
        const MigrateBitboxFailure(
          MigrateBitboxFailureReason.generic,
          message: 'API returned addWallet without userData',
        ),
      );
      await cubit.retry();
      verify(() => authService.getAuthToken()).called(1);
    });

    test('alreadyRegistered with manual review emits RegistrationPending', () async {
      when(
        () => registrationService.getRegistrationInfoWith(any()),
      ).thenAnswer(
        (_) async => info(
          RealUnitRegistrationState.alreadyRegistered,
          manualReview: true,
        ),
      );
      final cubit = buildCubit();

      await cubit.onDevicePaired(draft);

      expect(cubit.state, const MigrateBitboxRegistrationPending());
      verifyNever(() => walletService.persistBitboxWallet(any()));
    });

    test('alreadyRegistered persists before balance refresh and emits TransferReady', () async {
      final cubit = buildCubit();

      await cubit.onDevicePaired(draft);

      final state = cubit.state as MigrateBitboxTransferReady;
      expect(state.fromAddress, softwareAddress);
      expect(state.toAddress, persistedAddress);
      expect(state.amount, 5);
      verifyInOrder([
        () => walletService.persistBitboxWallet(draft),
        () => balanceService.updateBalance(softwareAddress),
      ]);
    });

    test('newRegistration emits registrationMissing', () async {
      when(
        () => registrationService.getRegistrationInfoWith(any()),
      ).thenAnswer((_) async => info(RealUnitRegistrationState.newRegistration));
      final cubit = buildCubit();

      await cubit.onDevicePaired(draft);

      expect(
        cubit.state,
        const MigrateBitboxFailure(MigrateBitboxFailureReason.registrationMissing),
      );
    });

    test('missing old JWT emits generic failure with no pending retry', () async {
      when(() => authService.getAuthToken()).thenAnswer((_) async => null);
      final cubit = buildCubit();

      await cubit.onDevicePaired(draft);
      await cubit.retry();

      expect(
        cubit.state,
        const MigrateBitboxFailure(MigrateBitboxFailureReason.generic),
      );
      verify(() => authService.getAuthToken()).called(1);
      verifyNever(() => authService.authenticateLinkedAccount(any(), any()));
    });

    test('AddressAlreadyLinkedException is terminal', () async {
      when(
        () => authService.authenticateLinkedAccount(any(), any()),
      ).thenThrow(const AddressAlreadyLinkedException());
      final cubit = buildCubit();

      await cubit.onDevicePaired(draft);
      await cubit.retry();

      expect(
        cubit.state,
        const MigrateBitboxFailure(MigrateBitboxFailureReason.addressAlreadyLinked),
      );
      verify(() => authService.getAuthToken()).called(1);
    });

    test('SigningCancelledException is retryable with the same draft', () async {
      var attempts = 0;
      when(
        () => authService.authenticateLinkedAccount(any(), any()),
      ).thenAnswer((_) async {
        attempts++;
        if (attempts == 1) throw const SigningCancelledException();
        return newJwt;
      });
      final cubit = buildCubit();

      await cubit.onDevicePaired(draft);
      expect(
        cubit.state,
        const MigrateBitboxFailure(
          MigrateBitboxFailureReason.signatureCancelled,
          canRetry: true,
        ),
      );
      await cubit.retry();

      verify(() => authService.getAuthToken()).called(2);
      verify(
        () => authService.authenticateLinkedAccount(draftAccount, oldJwt),
      ).called(2);
    });

    test('BitboxNotConnectedException is retryable with the same draft', () async {
      var attempts = 0;
      when(
        () => authService.authenticateLinkedAccount(any(), any()),
      ).thenAnswer((_) async {
        attempts++;
        if (attempts == 1) throw const BitboxNotConnectedException();
        return newJwt;
      });
      final cubit = buildCubit();

      await cubit.onDevicePaired(draft);
      expect(
        cubit.state,
        const MigrateBitboxFailure(
          MigrateBitboxFailureReason.bitboxNotConnected,
          canRetry: true,
        ),
      );
      await cubit.retry();

      verify(() => authService.getAuthToken()).called(2);
    });

    test('unexpected exception keeps its message and retries the same draft', () async {
      var attempts = 0;
      when(
        () => authService.authenticateLinkedAccount(any(), any()),
      ).thenAnswer((_) async {
        attempts++;
        if (attempts == 1) throw Exception('link failed');
        return newJwt;
      });
      final cubit = buildCubit();

      await cubit.onDevicePaired(draft);
      expect(
        cubit.state,
        const MigrateBitboxFailure(
          MigrateBitboxFailureReason.generic,
          message: 'Exception: link failed',
          canRetry: true,
        ),
      );
      await cubit.retry();

      verify(() => authService.getAuthToken()).called(2);
    });
  });

  group('$MigrateBitboxCubit register', () {
    test('is a no-op outside RegisterReady', () async {
      final cubit = buildCubit();
      final initial = cubit.state;

      await cubit.register();

      expect(cubit.state, same(initial));
      verifyNever(() => registrationService.registerWalletFor(any(), any(), any()));
    });

    for (final status in [
      RegistrationStatus.completed,
      RegistrationStatus.alreadyRegistered,
    ]) {
      test('$status persists and prepares transfer', () async {
        final cubit = buildCubit();
        await reachRegisterReady(cubit);
        when(
          () => registrationService.registerWalletFor(any(), any(), any()),
        ).thenAnswer((_) async => status);

        await cubit.register();

        expect(cubit.state, isA<MigrateBitboxTransferReady>());
        verify(
          () => registrationService.registerWalletFor(draftAccount, _userData, newJwt),
        ).called(1);
        verify(() => walletService.persistBitboxWallet(draft)).called(1);
      });
    }

    for (final status in [
      RegistrationStatus.pendingReview,
      RegistrationStatus.forwardingFailed,
    ]) {
      test('$status emits RegistrationPending', () async {
        final cubit = buildCubit();
        await reachRegisterReady(cubit);
        when(
          () => registrationService.registerWalletFor(any(), any(), any()),
        ).thenAnswer((_) async => status);

        await cubit.register();

        expect(cubit.state, const MigrateBitboxRegistrationPending());
      });
    }

    final retryableErrors = <(Exception, MigrateBitboxFailureReason)>[
      (const SigningCancelledException(), MigrateBitboxFailureReason.signatureCancelled),
      (const BitboxNotConnectedException(), MigrateBitboxFailureReason.bitboxNotConnected),
      (Exception('registration failed'), MigrateBitboxFailureReason.generic),
    ];
    for (final (error, reason) in retryableErrors) {
      test('$error is retryable and retry invokes registerWalletFor again', () async {
        final cubit = buildCubit();
        await reachRegisterReady(cubit);
        var attempts = 0;
        when(
          () => registrationService.registerWalletFor(any(), any(), any()),
        ).thenAnswer((_) async {
          attempts++;
          if (attempts == 1) throw error;
          return RegistrationStatus.completed;
        });

        await cubit.register();

        final failure = cubit.state as MigrateBitboxFailure;
        expect(failure.reason, reason);
        expect(failure.canRetry, isTrue);
        if (reason == MigrateBitboxFailureReason.generic) {
          expect(failure.message, 'Exception: registration failed');
        }

        await cubit.retry();

        verify(
          () => registrationService.registerWalletFor(draftAccount, _userData, newJwt),
        ).called(2);
      });
    }
  });

  group('$MigrateBitboxCubit transfer preparation', () {
    test('missing balance fails loud and retry repeats persistence and balance read', () async {
      when(
        () => balanceService.getBalance(any(), any()),
      ).thenAnswer((_) async => null);
      final cubit = buildCubit();

      await cubit.onDevicePaired(draft);
      expect(
        cubit.state,
        const MigrateBitboxFailure(
          MigrateBitboxFailureReason.generic,
          message: 'balance unavailable',
          canRetry: true,
        ),
      );

      await cubit.retry();

      verify(() => walletService.persistBitboxWallet(draft)).called(2);
      verify(() => balanceService.updateBalance(softwareAddress)).called(2);
      verify(() => balanceService.getBalance(realUnitAsset, softwareAddress)).called(2);
    });

    test('zero balance completes without emitting TransferReady', () async {
      when(
        () => balanceService.getBalance(any(), any()),
      ).thenAnswer((_) async => balance(0));
      final cubit = buildCubit();
      final emitted = <MigrateBitboxState>[];
      final subscription = cubit.stream.listen(emitted.add);
      addTearDown(subscription.cancel);

      await cubit.onDevicePaired(draft);

      expect(cubit.state, MigrateBitboxSuccess(persisted));
      expect(emitted.whereType<MigrateBitboxTransferReady>(), isEmpty);
    });

    test('positive balance truncates to an integer amount', () async {
      when(
        () => balanceService.getBalance(any(), any()),
      ).thenAnswer((_) async => balance(37));
      final cubit = buildCubit();

      await cubit.onDevicePaired(draft);

      expect(
        cubit.state,
        MigrateBitboxTransferReady(
          fromAddress: softwareAddress,
          toAddress: persistedAddress,
          amount: 37,
        ),
      );
    });
  });

  group('$MigrateBitboxCubit transfer and completion', () {
    test('startTransfer is a no-op outside TransferReady', () {
      final cubit = buildCubit();
      final initial = cubit.state;

      cubit.startTransfer();

      expect(cubit.state, same(initial));
    });

    test('startTransfer preserves recipient and amount', () async {
      final cubit = buildCubit();
      await reachTransferReady(cubit);

      cubit.startTransfer();

      expect(
        cubit.state,
        MigrateBitboxTransferring(toAddress: persistedAddress, amount: 5),
      );
    });

    test('terminal transfer failure is a no-op outside Transferring', () {
      final cubit = buildCubit();
      final initial = cubit.state;

      cubit.onTransferFailedTerminally('definitive');

      expect(cubit.state, same(initial));
    });

    test('terminal transfer failure retries with a fresh balance read', () async {
      final cubit = buildCubit();
      await reachTransferReady(cubit);
      cubit.startTransfer();

      cubit.onTransferFailedTerminally('definitive failure');

      expect(
        cubit.state,
        const MigrateBitboxFailure(
          MigrateBitboxFailureReason.generic,
          message: 'definitive failure',
          canRetry: true,
        ),
      );
      await cubit.retry();

      verify(() => balanceService.updateBalance(softwareAddress)).called(2);
      verify(() => balanceService.getBalance(realUnitAsset, softwareAddress)).called(2);
      expect(cubit.state, isA<MigrateBitboxTransferReady>());
    });

    test('matching signature is persisted before the new auth token', () async {
      when(
        () => balanceService.getBalance(any(), any()),
      ).thenAnswer((_) async => balance(0));
      final cubit = buildCubit();

      await cubit.onDevicePaired(draft);

      verifyInOrder([
        () => walletService.setCurrentWallet(42),
        () => sessionCache.saveSignature(persistedAddress, signature),
        () => sessionCache.setAuthToken(newJwt, persistedAddress),
      ]);
      expect(cubit.state, MigrateBitboxSuccess(persisted));
    });

    test('signature-address mismatch skips signature persistence', () async {
      when(() => sessionCache.signatureAddress).thenReturn(softwareAddress);
      when(
        () => balanceService.getBalance(any(), any()),
      ).thenAnswer((_) async => balance(0));
      final cubit = buildCubit();

      await cubit.onDevicePaired(draft);

      verifyInOrder([
        () => walletService.setCurrentWallet(42),
        () => sessionCache.setAuthToken(newJwt, persistedAddress),
      ]);
      verifyNever(() => sessionCache.saveSignature(any(), any()));
      expect(cubit.state, MigrateBitboxSuccess(persisted));
    });
  });
}
