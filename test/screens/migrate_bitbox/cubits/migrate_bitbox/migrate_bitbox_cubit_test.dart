import 'dart:async';

import 'package:fake_async/fake_async.dart';
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
  const refreshedJwt = 'refreshed-jwt';
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

    when(() => authService.refreshAuthToken()).thenAnswer((_) async => refreshedJwt);
    when(
      () => authService.authenticateLinkedAccount(any(), any()),
    ).thenAnswer((_) async => newJwt);
    when(
      () => registrationService.getRegistrationInfo(),
    ).thenAnswer((_) async => info(RealUnitRegistrationState.alreadyRegistered));
    when(
      () => registrationService.getRegistrationInfoWith(any()),
    ).thenAnswer((_) async => info(RealUnitRegistrationState.alreadyRegistered));
    when(() => walletService.persistBitboxWallet(any())).thenAnswer((_) async => persisted);
    when(() => walletService.setCurrentWallet(any())).thenAnswer((_) async {});
    when(
      () => balanceService.fetchBalance(any()),
    ).thenAnswer((_) async => balance(5));
  });

  MigrateBitboxCubit buildCubit({bool addCloseTearDown = true}) {
    final cubit = MigrateBitboxCubit(
      walletService,
      authService,
      registrationService,
      balanceService,
      appStore,
    );
    if (addCloseTearDown) addTearDown(cubit.close);
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

  void drain(FakeAsync async) {
    for (var i = 0; i < 10; i++) {
      async.flushMicrotasks();
    }
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
        () => authService.authenticateLinkedAccount(draftAccount, refreshedJwt),
      ).called(1);
      verify(() => authService.refreshAuthToken()).called(1);
      verifyNever(() => authService.getAuthToken());
      verify(() => registrationService.getRegistrationInfoWith(newJwt)).called(1);
    });

    for (final sourceState in [
      RealUnitRegistrationState.addWallet,
      RealUnitRegistrationState.newRegistration,
    ]) {
      test('$sourceState precheck aborts before refreshing or linking', () async {
        when(
          () => registrationService.getRegistrationInfo(),
        ).thenAnswer((_) async => info(sourceState));
        final cubit = buildCubit();

        await cubit.onDevicePaired(draft);

        expect(
          cubit.state,
          const MigrateBitboxFailure(
            MigrateBitboxFailureReason.registrationMissing,
          ),
        );
        verifyNever(() => authService.refreshAuthToken());
        verifyNever(() => authService.authenticateLinkedAccount(any(), any()));
        verifyNever(() => registrationService.getRegistrationInfoWith(any()));
      });
    }

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
      verify(() => authService.refreshAuthToken()).called(1);
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

    test('alreadyRegistered persists before the fresh balance read and emits TransferReady', () async {
      final cubit = buildCubit();

      await cubit.onDevicePaired(draft);

      final state = cubit.state as MigrateBitboxTransferReady;
      expect(state.fromAddress, softwareAddress);
      expect(state.toAddress, persistedAddress);
      expect(state.amount, 5);
      verifyInOrder([
        () => walletService.persistBitboxWallet(draft),
        () => balanceService.fetchBalance(softwareAddress),
      ]);
    });

    test('newRegistration after linking is retryable and retries the precheck', () async {
      when(
        () => registrationService.getRegistrationInfoWith(any()),
      ).thenAnswer((_) async => info(RealUnitRegistrationState.newRegistration));
      final cubit = buildCubit();

      await cubit.onDevicePaired(draft);

      expect(
        cubit.state,
        const MigrateBitboxFailure(
          MigrateBitboxFailureReason.generic,
          message: 'wallet link did not attach to the account',
          canRetry: true,
        ),
      );
      await cubit.retry();
      verify(() => registrationService.getRegistrationInfo()).called(2);
    });

    test('missing refreshed JWT emits generic failure with no pending retry', () async {
      when(() => authService.refreshAuthToken()).thenAnswer((_) async => null);
      final cubit = buildCubit();

      await cubit.onDevicePaired(draft);
      await cubit.retry();

      expect(
        cubit.state,
        const MigrateBitboxFailure(MigrateBitboxFailureReason.generic),
      );
      verify(() => authService.refreshAuthToken()).called(1);
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
      verify(() => authService.refreshAuthToken()).called(1);
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

      verify(() => authService.refreshAuthToken()).called(2);
      verify(
        () => authService.authenticateLinkedAccount(draftAccount, refreshedJwt),
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

      verify(() => authService.refreshAuthToken()).called(2);
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

      verify(() => authService.refreshAuthToken()).called(2);
    });
  });

  group('$MigrateBitboxCubit registration handoff', () {
    test('draftAccount and linkedJwt fail loud before pairing', () {
      final cubit = buildCubit();

      expect(() => cubit.draftAccount, throwsStateError);
      expect(() => cubit.linkedJwt, throwsStateError);
    });

    test('draftAccount and linkedJwt expose the freshly linked values', () async {
      final cubit = buildCubit();
      await reachRegisterReady(cubit);

      expect(cubit.draftAccount, same(draftAccount));
      expect(cubit.linkedJwt, newJwt);
    });

    test('onRegisterCompleted is a no-op outside RegisterReady', () async {
      final cubit = buildCubit();

      await cubit.onRegisterCompleted();

      verifyNever(() => walletService.persistBitboxWallet(any()));
    });

    test('onRegisterCompleted prepares the transfer from RegisterReady', () async {
      final cubit = buildCubit();
      await reachRegisterReady(cubit);

      await cubit.onRegisterCompleted();

      expect(cubit.state, isA<MigrateBitboxTransferReady>());
      verify(() => walletService.persistBitboxWallet(draft)).called(1);
    });

    test('registration handoff failure stays retryable and a later retry succeeds', () async {
      final cubit = buildCubit();
      await reachRegisterReady(cubit);
      var persistCalls = 0;
      when(() => walletService.persistBitboxWallet(draft)).thenAnswer((_) async {
        persistCalls++;
        if (persistCalls < 3) throw Exception('persist failed');
        return persisted;
      });

      await cubit.onRegisterCompleted();
      expect(
        cubit.state,
        const MigrateBitboxFailure(
          MigrateBitboxFailureReason.generic,
          message: 'Exception: persist failed',
          canRetry: true,
        ),
      );

      await cubit.retry();
      expect(cubit.state, isA<MigrateBitboxFailure>());
      await cubit.retry();

      expect(cubit.state, isA<MigrateBitboxTransferReady>());
      expect(persistCalls, 3);
    });

    test('onRegisterPending is a no-op outside RegisterReady', () {
      final cubit = buildCubit();
      final initial = cubit.state;

      cubit.onRegisterPending();

      expect(cubit.state, same(initial));
    });

    test('onRegisterPending emits RegistrationPending from RegisterReady', () async {
      final cubit = buildCubit();
      await reachRegisterReady(cubit);

      cubit.onRegisterPending();

      expect(cubit.state, const MigrateBitboxRegistrationPending());
    });
  });

  group('$MigrateBitboxCubit transfer preparation', () {
    test('fetch failure fails loud despite an implicit zero cache and never switches', () async {
      when(
        () => balanceService.fetchBalance(any()),
      ).thenThrow(Exception('network unavailable'));
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
      verify(() => balanceService.fetchBalance(softwareAddress)).called(2);
      verifyNever(() => balanceService.updateBalance(any()));
      verifyNever(() => balanceService.getBalance(any(), any()));
      verifyNever(() => walletService.setCurrentWallet(any()));
      verifyNever(() => sessionCache.setAuthToken(any(), any()));
    });

    test('zero balance completes without emitting TransferReady', () async {
      when(
        () => balanceService.fetchBalance(any()),
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
        () => balanceService.fetchBalance(any()),
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

    test('close during the fresh balance fetch prevents completion and later effects', () async {
      final cubit = buildCubit(addCloseTearDown: false);
      await reachRegisterReady(cubit);
      final fetchStarted = Completer<void>();
      final pendingBalance = Completer<Balance>();
      when(() => balanceService.fetchBalance(any())).thenAnswer((_) {
        fetchStarted.complete();
        return pendingBalance.future;
      });

      final preparation = cubit.onRegisterCompleted();
      await fetchStarted.future;
      await cubit.close();
      pendingBalance.complete(balance(0));
      await preparation;

      verifyNever(() => walletService.setCurrentWallet(any()));
      verifyNever(() => sessionCache.saveSignature(any(), any()));
      verifyNever(() => sessionCache.setAuthToken(any(), any()));
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

      verify(() => balanceService.fetchBalance(softwareAddress)).called(2);
      expect(cubit.state, isA<MigrateBitboxTransferReady>());
    });

    test('retry is single-flight while the linking precheck is pending', () async {
      when(
        () => authService.authenticateLinkedAccount(any(), any()),
      ).thenThrow(Exception('link failed'));
      final cubit = buildCubit();
      await cubit.onDevicePaired(draft);

      final precheck = Completer<RealUnitRegistrationInfoDto>();
      when(
        () => registrationService.getRegistrationInfo(),
      ).thenAnswer((_) => precheck.future);
      when(
        () => authService.authenticateLinkedAccount(any(), any()),
      ).thenAnswer((_) async => newJwt);
      clearInteractions(registrationService);

      final first = cubit.retry();
      final second = cubit.retry();
      await second;

      expect(cubit.state, const MigrateBitboxLinking());
      verify(() => registrationService.getRegistrationInfo()).called(1);

      precheck.complete(info(RealUnitRegistrationState.alreadyRegistered));
      await first;
    });

    test('matching signature is persisted before the new auth token', () async {
      when(
        () => balanceService.fetchBalance(any()),
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
        () => balanceService.fetchBalance(any()),
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

    test('close during signature persistence prevents the auth-token commit', () {
      fakeAsync((async) {
        final pendingSignatureSave = Completer<void>();
        when(
          () => balanceService.fetchBalance(any()),
        ).thenAnswer((_) async => balance(0));
        when(
          () => sessionCache.saveSignature(any(), any()),
        ).thenAnswer((_) => pendingSignatureSave.future);
        final cubit = buildCubit(addCloseTearDown: false);

        cubit.onDevicePaired(draft);
        drain(async);
        expect(cubit.state, const MigrateBitboxCompleting());

        cubit.close();
        pendingSignatureSave.complete();
        drain(async);

        verifyNever(() => sessionCache.setAuthToken(any(), any()));
        async.flushTimers();
      });
    });

    test('finishMigration is a no-op after close', () {
      fakeAsync((async) {
        final cubit = buildCubit(addCloseTearDown: false);

        cubit.close();
        cubit.finishMigration();
        drain(async);

        verifyNever(() => walletService.setCurrentWallet(any()));
        verifyNever(() => sessionCache.saveSignature(any(), any()));
        verifyNever(() => sessionCache.setAuthToken(any(), any()));
      });
    });
  });

  group('$MigrateBitboxCubit settling', () {
    test('onTransferBroadcast is a no-op outside Transferring', () async {
      final cubit = buildCubit();
      final initial = cubit.state;

      await cubit.onTransferBroadcast();

      expect(cubit.state, same(initial));
      verifyNever(() => balanceService.fetchBalance(any()));
    });

    test('zero balance on the first tick finishes the migration', () {
      fakeAsync((async) {
        var calls = 0;
        when(
          () => balanceService.fetchBalance(any()),
        ).thenAnswer((_) async => balance(calls++ == 0 ? 5 : 0));
        final cubit = buildCubit(addCloseTearDown: false);
        cubit.onDevicePaired(draft);
        drain(async);
        cubit.startTransfer();

        cubit.onTransferBroadcast();
        drain(async);
        expect(cubit.state, const MigrateBitboxSettling());
        async.elapse(const Duration(seconds: 3));
        drain(async);

        expect(cubit.state, MigrateBitboxSuccess(persisted));
        verify(() => walletService.setCurrentWallet(42)).called(1);
        cubit.close();
        async.flushTimers();
      });
    });

    test('a lower positive balance prepares a transfer for the remainder', () {
      fakeAsync((async) {
        var balanceReads = 0;
        when(
          () => balanceService.fetchBalance(any()),
        ).thenAnswer((_) async {
          balanceReads++;
          return balance(balanceReads == 1 ? 5 : 3);
        });
        final cubit = buildCubit(addCloseTearDown: false);
        cubit.onDevicePaired(draft);
        drain(async);
        cubit.startTransfer();
        cubit.onTransferBroadcast();
        drain(async);

        async.elapse(const Duration(seconds: 3));
        drain(async);

        expect(
          cubit.state,
          MigrateBitboxTransferReady(
            fromAddress: softwareAddress,
            toAddress: persistedAddress,
            amount: 3,
          ),
        );
        cubit.close();
        async.flushTimers();
      });
    });

    test('an unchanged balance times out after 20 attempts without switching wallets', () {
      fakeAsync((async) {
        final cubit = buildCubit(addCloseTearDown: false);
        cubit.onDevicePaired(draft);
        drain(async);
        cubit.startTransfer();
        cubit.onTransferBroadcast();
        drain(async);
        clearInteractions(balanceService);

        for (var i = 0; i < 20; i++) {
          async.elapse(const Duration(seconds: 3));
          drain(async);
        }

        expect(cubit.state, const MigrateBitboxSettlingTimeout());
        verifyNever(() => walletService.setCurrentWallet(any()));
        verify(() => balanceService.fetchBalance(softwareAddress)).called(20);
        cubit.close();
        async.flushTimers();
      });
    });

    test('a failed poll counts as an attempt and a later zero balance succeeds', () {
      fakeAsync((async) {
        var calls = 0;
        when(() => balanceService.fetchBalance(any())).thenAnswer((_) async {
          calls++;
          if (calls == 1) return balance(5);
          if (calls == 2) throw Exception('balance unavailable');
          return balance(0);
        });
        final cubit = buildCubit(addCloseTearDown: false);
        cubit.onDevicePaired(draft);
        drain(async);
        cubit.startTransfer();
        cubit.onTransferBroadcast();
        drain(async);

        async.elapse(const Duration(seconds: 3));
        drain(async);
        expect(cubit.state, const MigrateBitboxSettling());
        async.elapse(const Duration(seconds: 3));
        drain(async);

        expect(cubit.state, MigrateBitboxSuccess(persisted));
        expect(calls, 3);
        cubit.close();
        async.flushTimers();
      });
    });

    test('overlapping timer ticks do not start a second balance request', () {
      fakeAsync((async) {
        final pendingBalance = Completer<Balance>();
        var calls = 0;
        when(
          () => balanceService.fetchBalance(any()),
        ).thenAnswer((_) {
          calls++;
          if (calls == 1) return Future.value(balance(5));
          return pendingBalance.future;
        });
        final cubit = buildCubit(addCloseTearDown: false);
        cubit.onDevicePaired(draft);
        drain(async);
        cubit.startTransfer();
        cubit.onTransferBroadcast();
        drain(async);

        async.elapse(const Duration(seconds: 6));
        drain(async);

        expect(calls, 2);
        pendingBalance.complete(balance(0));
        drain(async);
        expect(cubit.state, MigrateBitboxSuccess(persisted));
        cubit.close();
        async.flushTimers();
      });
    });

    test('zero-balance finish failure becomes retryable instead of hanging', () {
      fakeAsync((async) {
        var balanceCalls = 0;
        when(() => balanceService.fetchBalance(any())).thenAnswer(
          (_) async => balance(balanceCalls++ == 0 ? 5 : 0),
        );
        when(
          () => walletService.setCurrentWallet(any()),
        ).thenThrow(Exception('wallet switch failed'));
        final cubit = buildCubit(addCloseTearDown: false);
        cubit.onDevicePaired(draft);
        drain(async);
        cubit.startTransfer();
        cubit.onTransferBroadcast();
        drain(async);

        async.elapse(const Duration(seconds: 3));
        drain(async);

        expect(
          cubit.state,
          const MigrateBitboxFailure(
            MigrateBitboxFailureReason.generic,
            message: 'Exception: wallet switch failed',
            canRetry: true,
          ),
        );
        async.elapse(const Duration(seconds: 6));
        drain(async);
        expect(balanceCalls, 2);
        expect(cubit.state, isA<MigrateBitboxFailure>());
        cubit.close();
        async.flushTimers();
      });
    });

    test('lower balance with a persistence failure becomes retryable', () {
      fakeAsync((async) {
        var balanceCalls = 0;
        when(() => balanceService.fetchBalance(any())).thenAnswer((_) async {
          balanceCalls++;
          return balance(balanceCalls == 1 ? 5 : 3);
        });
        var persistCalls = 0;
        when(() => walletService.persistBitboxWallet(any())).thenAnswer((_) async {
          persistCalls++;
          if (persistCalls == 2) throw Exception('persist failed');
          return persisted;
        });
        final cubit = buildCubit(addCloseTearDown: false);
        cubit.onDevicePaired(draft);
        drain(async);
        cubit.startTransfer();
        cubit.onTransferBroadcast();
        drain(async);

        async.elapse(const Duration(seconds: 3));
        drain(async);

        expect(
          cubit.state,
          const MigrateBitboxFailure(
            MigrateBitboxFailureReason.generic,
            message: 'Exception: persist failed',
            canRetry: true,
          ),
        );
        async.elapse(const Duration(seconds: 6));
        drain(async);
        expect(balanceCalls, 2);
        expect(cubit.state, isA<MigrateBitboxFailure>());
        cubit.close();
        async.flushTimers();
      });
    });

    test('close during a pending settling balance prevents all finish side effects', () {
      fakeAsync((async) {
        final pendingBalance = Completer<Balance>();
        var balanceCalls = 0;
        when(() => balanceService.fetchBalance(any())).thenAnswer((_) {
          balanceCalls++;
          if (balanceCalls == 1) return Future.value(balance(5));
          return pendingBalance.future;
        });
        final cubit = buildCubit(addCloseTearDown: false);
        cubit.onDevicePaired(draft);
        drain(async);
        cubit.startTransfer();
        cubit.onTransferBroadcast();
        drain(async);
        async.elapse(const Duration(seconds: 3));
        drain(async);

        cubit.close();
        pendingBalance.complete(balance(0));
        drain(async);

        verifyNever(() => walletService.setCurrentWallet(any()));
        verifyNever(() => sessionCache.saveSignature(any(), any()));
        verifyNever(() => sessionCache.setAuthToken(any(), any()));
        async.flushTimers();
      });
    });

    test('close during setCurrentWallet prevents signature, token, and success emission', () {
      fakeAsync((async) {
        final pendingSwitch = Completer<void>();
        var balanceCalls = 0;
        when(() => balanceService.fetchBalance(any())).thenAnswer(
          (_) async => balance(balanceCalls++ == 0 ? 5 : 0),
        );
        when(
          () => walletService.setCurrentWallet(any()),
        ).thenAnswer((_) => pendingSwitch.future);
        final cubit = buildCubit(addCloseTearDown: false);
        final emitted = <MigrateBitboxState>[];
        final subscription = cubit.stream.listen(emitted.add);
        cubit.onDevicePaired(draft);
        drain(async);
        cubit.startTransfer();
        cubit.onTransferBroadcast();
        drain(async);
        async.elapse(const Duration(seconds: 3));
        drain(async);
        expect(cubit.state, const MigrateBitboxCompleting());

        cubit.close();
        final emissionCountAtClose = emitted.length;
        pendingSwitch.complete();
        drain(async);

        expect(emitted, hasLength(emissionCountAtClose));
        expect(emitted.whereType<MigrateBitboxSuccess>(), isEmpty);
        verifyNever(() => sessionCache.saveSignature(any(), any()));
        verifyNever(() => sessionCache.setAuthToken(any(), any()));
        subscription.cancel();
        async.flushTimers();
      });
    });
  });
}
