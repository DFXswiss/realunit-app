import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/balance_service.dart';
import 'package:realunit_wallet/packages/service/wallet_service.dart';
import 'package:realunit_wallet/screens/pin/bloc/auth/pin_auth_cubit.dart';
import 'package:realunit_wallet/setup/lifecycle_initializer.dart';

class _MockAppStore extends Mock implements AppStore {}

class _MockBalanceService extends Mock implements BalanceService {}

class _MockPinAuthCubit extends Mock implements PinAuthCubit {}

class _MockWalletService extends Mock implements WalletService {}

void main() {
  late _MockAppStore appStore;
  late _MockBalanceService balanceService;
  late _MockPinAuthCubit pinAuthCubit;
  late _MockWalletService walletService;

  setUp(() {
    appStore = _MockAppStore();
    balanceService = _MockBalanceService();
    pinAuthCubit = _MockPinAuthCubit();
    walletService = _MockWalletService();

    final getIt = GetIt.instance;
    getIt.registerSingleton<AppStore>(appStore);
    getIt.registerSingleton<BalanceService>(balanceService);
    getIt.registerSingleton<PinAuthCubit>(pinAuthCubit);
    getIt.registerSingleton<WalletService>(walletService);

    when(() => walletService.lockCurrentWallet()).thenAnswer((_) async {});
  });

  tearDown(() => GetIt.instance.reset());

  Future<void> pumpLifecycle(WidgetTester tester) => tester.pumpWidget(
    const LifecycleInitializer(
      child: SizedBox.shrink(),
    ),
  );

  testWidgets(
    'AppLifecycleState.hidden drops the mnemonic via WalletService.lockCurrentWallet',
    (tester) async {
      await pumpLifecycle(tester);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();

      verify(() => walletService.lockCurrentWallet()).called(1);
    },
  );

  // The architecture decision "no try/catch / catchError around the
  // unawaited lockCurrentWallet" is locked in by the source itself — see
  // the inline comment in `_onHidden`. We tried encoding it as a test, but
  // every variant (`thenThrow`, `thenAnswer((_) async => throw …)`,
  // `Future.error(...)`) routed the failure through the testWidgets
  // framework's synchronous catch rather than the Zone uncaught-error sink
  // that `tester.takeException()` reads from — the routing depends on
  // Flutter's AppLifecycleListener dispatch (changes between 3.41 and 3.44).
  // A brittle false-positive on CI is worse than relying on code review +
  // the source comment to catch a future regression at the call site.

  testWidgets(
    'AppLifecycleState.paused arms the lock (covers a skipped/coalesced hidden)',
    (tester) async {
      await pumpLifecycle(tester);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      // paused must now drop the mnemonic and arm the PIN gate too, so a
      // platform that never emits `hidden` still locks.
      verify(() => walletService.lockCurrentWallet()).called(1);
      verify(() => pinAuthCubit.onAppHidden(any())).called(1);
      // and it still cancels the balance sync it always did.
      verify(() => balanceService.cancelSync()).called(1);
    },
  );

  testWidgets(
    'hidden + paused in one background episode lock exactly once (idempotent)',
    (tester) async {
      await pumpLifecycle(tester);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      verify(() => walletService.lockCurrentWallet()).called(1);
      verify(() => pinAuthCubit.onAppHidden(any())).called(1);
    },
  );

  testWidgets(
    'paused + hidden in the reverse order also lock exactly once',
    (tester) async {
      await pumpLifecycle(tester);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();

      verify(() => walletService.lockCurrentWallet()).called(1);
      verify(() => pinAuthCubit.onAppHidden(any())).called(1);
    },
  );

  testWidgets(
    'AppLifecycleState.inactive does NOT lock (biometric/permission prompts raise it)',
    (tester) async {
      await pumpLifecycle(tester);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();

      verifyNever(() => walletService.lockCurrentWallet());
      verifyNever(() => pinAuthCubit.onAppHidden(any()));
    },
  );

  testWidgets(
    'AppLifecycleState.resumed does NOT lock and re-arms for the next background',
    (tester) async {
      when(() => appStore.primaryAddress).thenReturn('0xabc');
      when(() => balanceService.updateBalance(any())).thenAnswer((_) async {});
      when(() => pinAuthCubit.onAppResumed()).thenAnswer((_) {});

      await pumpLifecycle(tester);

      // The lifecycle machine only permits single-step moves along
      // detached ↔ paused ↔ hidden ↔ inactive ↔ resumed, and the binding's
      // state carries across tests in this file. Step along the chain from the
      // current state so every transition is valid.
      const chain = <AppLifecycleState>[
        AppLifecycleState.detached,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ];
      void driveTo(AppLifecycleState target) {
        if (tester.binding.lifecycleState == null) {
          tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        }
        var index = chain.indexOf(tester.binding.lifecycleState!);
        final targetIndex = chain.indexOf(target);
        while (index != targetIndex) {
          index += index < targetIndex ? 1 : -1;
          tester.binding.handleAppLifecycleStateChanged(chain[index]);
        }
      }

      // Known foreground baseline.
      driveTo(AppLifecycleState.resumed);
      await tester.pump();

      // First background episode locks once.
      driveTo(AppLifecycleState.hidden);
      await tester.pump();
      verify(() => walletService.lockCurrentWallet()).called(1);

      // Resume clears the arm guard and must not itself lock.
      driveTo(AppLifecycleState.resumed);
      await tester.pump();

      // Second background episode locks again — only possible because resume
      // reset the guard; without the reset the handler would be a no-op.
      driveTo(AppLifecycleState.hidden);
      await tester.pump();
      verify(() => walletService.lockCurrentWallet()).called(1);
    },
  );
}
