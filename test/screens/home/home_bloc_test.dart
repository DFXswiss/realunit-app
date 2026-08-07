import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/hardware_wallet/bitbox.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/balance_service.dart';
import 'package:realunit_wallet/packages/service/session_cache.dart';
import 'package:realunit_wallet/packages/service/settings_service.dart';
import 'package:realunit_wallet/packages/service/transaction_history_service.dart';
import 'package:realunit_wallet/packages/service/wallet_service.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';
import 'package:realunit_wallet/screens/home/bloc/home_bloc.dart';
import 'package:realunit_wallet/setup/routing/boot_navigation.dart';

class _MockWalletService extends Mock implements WalletService {}

class _MockBalanceService extends Mock implements BalanceService {}

class _MockTransactionHistoryService extends Mock implements TransactionHistoryService {}

class _MockSettingsService extends Mock implements SettingsService {}

class _MockAppStore extends Mock implements AppStore {}

class _MockBitboxService extends Mock implements BitboxService {}

class _MockSessionCache extends Mock implements SessionCache {}

class _FakeWallet extends Fake implements AWallet {}

const _debugAddress = '0x0000000000000000000000000000000000000001';
const _primary = '0x00000000000000000000000000000000deadbeef';

void main() {
  late _MockWalletService walletService;
  late _MockBalanceService balanceService;
  late _MockTransactionHistoryService transactionHistoryService;
  late _MockSettingsService settingsService;
  late _MockAppStore appStore;
  late _MockBitboxService bitboxService;
  late _MockSessionCache sessionCache;

  setUpAll(() {
    registerFallbackValue(_FakeWallet());
  });

  setUp(() {
    walletService = _MockWalletService();
    balanceService = _MockBalanceService();
    transactionHistoryService = _MockTransactionHistoryService();
    settingsService = _MockSettingsService();
    appStore = _MockAppStore();
    bitboxService = _MockBitboxService();
    sessionCache = _MockSessionCache();

    // Sensible defaults so the auto-fired CheckWalletExistsEvent doesn't crash
    // and the AppStore-driven side effects (`primaryAddress`, `sessionCache`,
    // `wallet =`) all resolve without throwing.
    when(() => walletService.hasWallet()).thenReturn(false);
    // Default: a healthy wallet does not need address recovery, so
    // LoadCurrentWalletEvent falls through to the normal load path.
    when(() => walletService.currentWalletNeedsAddressRecovery()).thenAnswer((_) async => false);
    when(() => settingsService.isSoftwareTermsAccepted).thenReturn(false);
    when(() => settingsService.isTermsAccepted).thenReturn(false);
    when(() => settingsService.setTermsAccepted(any())).thenReturn(null);
    when(() => settingsService.setSoftwareTermsAccepted(any())).thenReturn(null);
    when(() => appStore.primaryAddress).thenReturn(_primary);
    when(() => appStore.sessionCache).thenReturn(sessionCache);
    when(() => sessionCache.clear()).thenAnswer((_) async {});
    when(() => balanceService.updateBalance(any())).thenAnswer((_) async {});
    when(() => balanceService.startSync(any())).thenReturn(null);
    when(() => transactionHistoryService.apiBasedSync()).thenAnswer((_) async {});
    when(() => bitboxService.stopConnectionStatusObserver()).thenReturn(null);
  });

  HomeBloc build() => HomeBloc(
    walletService,
    balanceService,
    transactionHistoryService,
    settingsService,
    appStore,
    bitboxService,
  );

  group('$HomeBloc', () {
    group('initial CheckWalletExistsEvent', () {
      test('no wallet present → hasWallet=false, onboardingCompleted=false', () async {
        when(() => walletService.hasWallet()).thenReturn(false);
        when(() => settingsService.isSoftwareTermsAccepted).thenReturn(true);
        when(() => settingsService.isTermsAccepted).thenReturn(true);

        final bloc = build();
        await bloc.stream.firstWhere(
          (s) => s.softwareTermsAccepted == true && s.hasWallet == false,
        );

        expect(bloc.state.hasWallet, isFalse);
        // Without a wallet, onboardingCompleted is forced false regardless of
        // the persisted termsAccepted flag.
        expect(bloc.state.onboardingCompleted, isFalse);
        expect(bloc.state.softwareTermsAccepted, isTrue);
      });

      test('wallet present + terms accepted → onboardingCompleted=true', () async {
        when(() => walletService.hasWallet()).thenReturn(true);
        when(() => settingsService.isSoftwareTermsAccepted).thenReturn(true);
        when(() => settingsService.isTermsAccepted).thenReturn(true);

        final bloc = build();
        await bloc.stream.firstWhere((s) => s.hasWallet);

        expect(bloc.state.hasWallet, isTrue);
        expect(bloc.state.onboardingCompleted, isTrue);
        expect(bloc.state.softwareTermsAccepted, isTrue);
      });

      test('wallet present + terms NOT yet accepted → onboardingCompleted=false', () async {
        when(() => walletService.hasWallet()).thenReturn(true);
        when(() => settingsService.isSoftwareTermsAccepted).thenReturn(true);
        when(() => settingsService.isTermsAccepted).thenReturn(false);

        final bloc = build();
        await bloc.stream.firstWhere((s) => s.hasWallet);

        expect(bloc.state.hasWallet, isTrue);
        expect(bloc.state.onboardingCompleted, isFalse);
      });
    });

    group('LoadCurrentWalletEvent', () {
      test('no wallet persisted → early return, no service calls', () async {
        when(() => walletService.hasWallet()).thenReturn(false);

        final bloc = build();
        await bloc.stream.firstWhere((s) => true); // drain initial check
        clearInteractions(walletService);

        bloc.add(const LoadCurrentWalletEvent());
        await Future<void>.delayed(Duration.zero);

        verifyNever(() => walletService.getCurrentWallet());
        verifyNever(() => balanceService.updateBalance(any()));
        verifyNever(() => balanceService.startSync(any()));
        verifyNever(() => transactionHistoryService.apiBasedSync());
        expect(bloc.state.isLoadingWallet, isFalse);
        expect(bloc.state.openWallet, isNull);
      });

      test(
        'wallet exists → populates openWallet, sets appStore.wallet, kicks balance + history sync',
        () async {
          final wallet = DebugWallet(1, 'Test', _debugAddress);
          when(() => walletService.hasWallet()).thenReturn(true);
          when(() => walletService.getCurrentWallet()).thenAnswer((_) async => wallet);

          final bloc = build();
          // Drain initial CheckWalletExistsEvent.
          await bloc.stream.firstWhere((s) => s.hasWallet);

          bloc.add(const LoadCurrentWalletEvent());
          await bloc.stream.firstWhere(
            (s) => s.openWallet == wallet && !s.isLoadingWallet,
          );

          expect(bloc.state.openWallet, same(wallet));
          expect(bloc.state.isLoadingWallet, isFalse);
          verify(() => appStore.wallet = wallet).called(1);
          verify(() => balanceService.updateBalance(_primary)).called(1);
          verify(() => balanceService.startSync(_primary)).called(1);
          verify(() => transactionHistoryService.apiBasedSync()).called(1);
        },
      );

      test('openWallet already set → early return, no second fetch', () async {
        final wallet = DebugWallet(1, 'Test', _debugAddress);
        when(() => walletService.hasWallet()).thenReturn(true);
        when(() => walletService.getCurrentWallet()).thenAnswer((_) async => wallet);

        final bloc = build();
        bloc.add(const LoadCurrentWalletEvent());
        await bloc.stream.firstWhere((s) => s.openWallet == wallet);
        clearInteractions(walletService);
        clearInteractions(balanceService);
        clearInteractions(transactionHistoryService);

        bloc.add(const LoadCurrentWalletEvent());
        await Future<void>.delayed(Duration.zero);

        verifyNever(() => walletService.getCurrentWallet());
        verifyNever(() => balanceService.updateBalance(any()));
        verifyNever(() => transactionHistoryService.apiBasedSync());
      });

      test(
        'BitBox address recovery needed → emits bitboxAddressRecoveryNeeded, does NOT load wallet',
        () async {
          when(() => walletService.hasWallet()).thenReturn(true);
          when(
            () => walletService.currentWalletNeedsAddressRecovery(),
          ).thenAnswer((_) async => true);

          final bloc = build();
          await bloc.stream.firstWhere((s) => s.hasWallet);

          bloc.add(const LoadCurrentWalletEvent());
          await bloc.stream.firstWhere(
            (s) => s.bitboxAddressRecoveryNeeded && !s.isLoadingWallet,
          );

          expect(bloc.state.bitboxAddressRecoveryNeeded, isTrue);
          expect(bloc.state.isLoadingWallet, isFalse);
          expect(bloc.state.openWallet, isNull);
          // The corrupt wallet must never be loaded into the AppStore — that is
          // the exact path that crashes the dashboard build.
          verifyNever(() => walletService.getCurrentWallet());
          verifyNever(() => balanceService.updateBalance(any()));
          verifyNever(() => transactionHistoryService.apiBasedSync());
        },
      );

      test(
        'getCurrentWallet throws → isLoadingWallet flips back to false, no sync side effects',
        () async {
          when(() => walletService.hasWallet()).thenReturn(true);
          when(() => walletService.getCurrentWallet()).thenThrow(Exception('boom'));

          final bloc = build();
          await bloc.stream.firstWhere((s) => s.hasWallet);

          bloc.add(const LoadCurrentWalletEvent());
          // The handler emits isLoadingWallet=true then false on the catch branch.
          await bloc.stream.firstWhere(
            (s) => s.isLoadingWallet == false && s.openWallet == null,
          );

          expect(bloc.state.openWallet, isNull);
          expect(bloc.state.isLoadingWallet, isFalse);
          verifyNever(() => balanceService.updateBalance(any()));
          verifyNever(() => balanceService.startSync(any()));
          verifyNever(() => transactionHistoryService.apiBasedSync());
        },
      );

      test(
        'recovery gate throws → caught as load failure, spinner cleared, recovery flag stays off',
        () async {
          when(() => walletService.hasWallet()).thenReturn(true);
          // The gate runs inside the load try/catch, so an unexpected throw
          // (e.g. a corrupt wallet-type index) is handled as a load failure
          // instead of leaving isLoadingWallet stuck true — and must NOT divert
          // the app into the recovery flow.
          when(
            () => walletService.currentWalletNeedsAddressRecovery(),
          ).thenThrow(Exception('gate boom'));

          final bloc = build();
          await bloc.stream.firstWhere((s) => s.hasWallet);

          bloc.add(const LoadCurrentWalletEvent());
          await bloc.stream.firstWhere(
            (s) => s.isLoadingWallet == false && s.openWallet == null,
          );

          expect(bloc.state.isLoadingWallet, isFalse);
          expect(bloc.state.bitboxAddressRecoveryNeeded, isFalse);
          expect(bloc.state.openWallet, isNull);
          verifyNever(() => walletService.getCurrentWallet());
          verifyNever(() => balanceService.updateBalance(any()));
          verifyNever(() => transactionHistoryService.apiBasedSync());
        },
      );
    });

    group('LoadWalletEvent', () {
      test('updates appStore.wallet, triggers sync side effects, emits openWallet', () async {
        final wallet = DebugWallet(1, 'Restored', _debugAddress);
        when(() => appStore.wallet).thenReturn(wallet);

        final bloc = build();
        await bloc.stream.firstWhere((s) => true);

        bloc.add(LoadWalletEvent(wallet));
        await bloc.stream.firstWhere(
          (s) => s.openWallet == wallet && s.hasWallet,
        );

        expect(bloc.state.hasWallet, isTrue);
        expect(bloc.state.openWallet, same(wallet));
        expect(bloc.state.isLoadingWallet, isFalse);
        verify(() => appStore.wallet = wallet).called(1);
        verify(() => balanceService.updateBalance(_primary)).called(1);
        verify(() => balanceService.startSync(_primary)).called(1);
        verify(() => transactionHistoryService.apiBasedSync()).called(1);
      });

      test('clears bitboxAddressRecoveryNeeded once a wallet loads cleanly', () async {
        // Drive the bloc into the recovery state first, then prove that loading
        // the healed wallet via LoadWalletEvent flips the flag back off so
        // `_navigate` routes to the dashboard instead of back to recovery.
        final wallet = DebugWallet(1, 'Healed', _debugAddress);
        when(() => appStore.wallet).thenReturn(wallet);
        when(() => walletService.hasWallet()).thenReturn(true);
        when(
          () => walletService.currentWalletNeedsAddressRecovery(),
        ).thenAnswer((_) async => true);

        final bloc = build();
        await bloc.stream.firstWhere((s) => s.hasWallet);
        bloc.add(const LoadCurrentWalletEvent());
        await bloc.stream.firstWhere((s) => s.bitboxAddressRecoveryNeeded);

        bloc.add(LoadWalletEvent(wallet));
        await bloc.stream.firstWhere((s) => s.openWallet == wallet);

        expect(bloc.state.bitboxAddressRecoveryNeeded, isFalse);
      });
    });

    group('SyncWalletServicesEvent', () {
      test(
        'triggers _updateWallet side effects but does not emit a new state',
        () async {
          final wallet = DebugWallet(1, 'Sync', _debugAddress);
          final bloc = build();
          await bloc.stream.firstWhere((s) => true);
          final before = bloc.state;

          // Subscribe so we can assert that no new state lands.
          final emitted = <HomeState>[];
          final sub = bloc.stream.listen(emitted.add);

          bloc.add(SyncWalletServicesEvent(wallet));
          await Future<void>.delayed(Duration.zero);
          await sub.cancel();

          verify(() => appStore.wallet = wallet).called(1);
          verify(() => balanceService.updateBalance(_primary)).called(1);
          verify(() => balanceService.startSync(_primary)).called(1);
          verify(() => transactionHistoryService.apiBasedSync()).called(1);
          // The handler is the arrow-form `_onSyncWalletServices` that does
          // not call `emit`. Documented contract: no state change.
          expect(emitted, isEmpty);
          expect(bloc.state, same(before));
        },
      );
    });

    group('DeleteCurrentWalletEvent', () {
      test('with wallet present → clears wallet, terms, session cache', () async {
        when(() => walletService.hasWallet()).thenReturn(true);
        when(() => walletService.deleteCurrentWallet()).thenAnswer((_) async {});

        final bloc = build();
        await bloc.stream.firstWhere((s) => s.hasWallet);

        bloc.add(const DeleteCurrentWalletEvent());
        await bloc.stream.firstWhere(
          (s) => s.isLoadingWallet == false && s.hasWallet == false,
        );

        expect(bloc.state.hasWallet, isFalse);
        expect(bloc.state.openWallet, isNull);
        expect(bloc.state.isLoadingWallet, isFalse);
        verify(() => bitboxService.stopConnectionStatusObserver()).called(1);
        verify(() => sessionCache.clear()).called(1);
        verify(() => walletService.deleteCurrentWallet()).called(1);
        verify(() => settingsService.setTermsAccepted(false)).called(1);
      });

      test('with no wallet → still clears session, does NOT call deleteCurrentWallet', () async {
        when(() => walletService.hasWallet()).thenReturn(false);

        final bloc = build();
        await bloc.stream.firstWhere((s) => true);

        bloc.add(const DeleteCurrentWalletEvent());
        await bloc.stream.firstWhere(
          (s) => s.isLoadingWallet == false && s.hasWallet == false,
        );

        verify(() => bitboxService.stopConnectionStatusObserver()).called(1);
        verify(() => sessionCache.clear()).called(1);
        // hasWallet() was false on entry → the delete branch is skipped, and
        // termsAccepted is NOT cleared again (it was never true to begin with).
        verifyNever(() => walletService.deleteCurrentWallet());
        verifyNever(() => settingsService.setTermsAccepted(false));
      });

      test('preserves softwareTermsAccepted in the final HomeState', () async {
        when(() => settingsService.isSoftwareTermsAccepted).thenReturn(true);

        final bloc = build();
        await bloc.stream.firstWhere((s) => s.softwareTermsAccepted);

        bloc.add(const DeleteCurrentWalletEvent());
        await bloc.stream.firstWhere(
          (s) => s.isLoadingWallet == false && s.hasWallet == false,
        );

        // The handler builds a fresh HomeState(...) but explicitly carries
        // softwareTermsAccepted forward — the user already accepted the
        // disclaimer, deleting the wallet must not force them to accept it
        // again.
        expect(bloc.state.softwareTermsAccepted, isTrue);
      });

      test('clears a stashed payment deeplink so it cannot replay into a re-onboarded wallet', () async {
        addTearDown(clearPendingPaymentDeeplink);
        stashPendingPaymentDeeplink('lightning:LNURL1DP68GURN8GHJ7VF3XGENJVE5UMD');

        final bloc = build();
        await bloc.stream.firstWhere((s) => true);

        bloc.add(const DeleteCurrentWalletEvent());
        await bloc.stream.firstWhere(
          (s) => s.isLoadingWallet == false && s.hasWallet == false,
        );

        expect(peekPendingPaymentDeeplink(), isNull);
      });
    });

    group('CompleteOnboardingEvent', () {
      test('writes termsAccepted=true and emits onboardingCompleted=true', () async {
        final bloc = build();
        await bloc.stream.firstWhere((s) => s.hasWallet == false);

        bloc.add(const CompleteOnboardingEvent());
        await bloc.stream.firstWhere((s) => s.onboardingCompleted);

        expect(bloc.state.onboardingCompleted, isTrue);
        verify(() => settingsService.setTermsAccepted(true)).called(1);
      });
    });

    group('AcceptSoftwareTermsEvent', () {
      test('writes softwareTermsAccepted=true and emits the new state', () async {
        final bloc = build();
        await bloc.stream.firstWhere((s) => s.hasWallet == false);

        bloc.add(const AcceptSoftwareTermsEvent());
        await bloc.stream.firstWhere((s) => s.softwareTermsAccepted);

        expect(bloc.state.softwareTermsAccepted, isTrue);
        verify(() => settingsService.setSoftwareTermsAccepted(true)).called(1);
      });
    });

    group('DebugAuthCompleteEvent', () {
      test(
        'creates debug wallet, sets appStore.wallet, emits hasWallet=true with openWallet',
        () async {
          final wallet = DebugWallet(7, 'Debug', _debugAddress);
          when(
            () => walletService.createDebugWallet(_debugAddress),
          ).thenAnswer((_) async => wallet);

          final bloc = build();
          await bloc.stream.firstWhere((s) => true);

          bloc.add(const DebugAuthCompleteEvent(address: _debugAddress));
          await bloc.stream.firstWhere(
            (s) => s.openWallet == wallet && s.hasWallet,
          );

          expect(bloc.state.hasWallet, isTrue);
          expect(bloc.state.openWallet, same(wallet));
          verify(() => walletService.createDebugWallet(_debugAddress)).called(1);
          verify(() => appStore.wallet = wallet).called(1);
          // Unlike LoadCurrentWalletEvent / LoadWalletEvent, the debug-auth
          // handler does not kick balance/history sync. Pinned because the
          // debug build path is for offline/dev use and must not touch the
          // network.
          verifyNever(() => balanceService.updateBalance(any()));
          verifyNever(() => balanceService.startSync(any()));
          verifyNever(() => transactionHistoryService.apiBasedSync());
        },
      );
    });
  });

  group('HomeEvent equality (sealed class props)', () {
    test('parameterless events are const-equal to themselves', () {
      expect(const CheckWalletExistsEvent(), const CheckWalletExistsEvent());
      expect(const LoadCurrentWalletEvent(), const LoadCurrentWalletEvent());
      expect(const DeleteCurrentWalletEvent(), const DeleteCurrentWalletEvent());
      expect(const CompleteOnboardingEvent(), const CompleteOnboardingEvent());
      expect(const AcceptSoftwareTermsEvent(), const AcceptSoftwareTermsEvent());
      // Default props from the sealed base class.
      expect(const CheckWalletExistsEvent().props, isEmpty);
    });

    test('LoadWalletEvent equality keys on the wallet payload', () {
      final w = DebugWallet(1, 'A', _debugAddress);
      expect(LoadWalletEvent(w), LoadWalletEvent(w));
      expect(LoadWalletEvent(w).props, [w]);
    });

    test('SyncWalletServicesEvent equality keys on the wallet payload', () {
      final w = DebugWallet(1, 'A', _debugAddress);
      expect(SyncWalletServicesEvent(w), SyncWalletServicesEvent(w));
      expect(SyncWalletServicesEvent(w).props, [w]);
    });

    test('DebugAuthCompleteEvent equality keys on the address string', () {
      expect(
        const DebugAuthCompleteEvent(address: _debugAddress),
        const DebugAuthCompleteEvent(address: _debugAddress),
      );
      expect(
        const DebugAuthCompleteEvent(address: _debugAddress).props,
        [_debugAddress],
      );
      expect(
        const DebugAuthCompleteEvent(address: 'a'),
        isNot(const DebugAuthCompleteEvent(address: 'b')),
      );
    });
  });
}
