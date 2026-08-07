// Responsive matrix gate for CreateWalletView confirm CTA.
//
// Proves the seed-backup confirm button stays fully tappable across the full
// device × text-scale matrix (see test/helper/responsive_matrix.dart).
// Regression lock for the IntrinsicHeight + Spacer collapse that pushed the
// confirm button below the viewport on first frame without a RenderFlex overflow.
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_kyc_service.dart';
import 'package:realunit_wallet/packages/service/wallet_service.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';
import 'package:realunit_wallet/packages/wallet/wallet_account.dart';
import 'package:realunit_wallet/screens/create_wallet/bloc/create_wallet_cubit.dart';
import 'package:realunit_wallet/screens/create_wallet/create_wallet_view.dart';
import 'package:realunit_wallet/setup/routing/routes/onboarding_routes.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';

import '../../helper/helper.dart';

class MockCreateWalletCubit extends MockCubit<CreateWalletState>
    implements CreateWalletCubit {}

class MockWalletService extends Mock implements WalletService {}

class MockDfxKycService extends Mock implements DfxKycService {}

class MockWallet extends Mock implements SoftwareWallet {}

class MockWalletAccount extends Mock implements WalletAccount {}

const _seed =
    'cheese trigger cannon mention judge hire snack sustain annual predict illness celery';

void main() {
  late CreateWalletCubit createWalletCubit;
  late MockWallet wallet;

  setUpAll(() {
    registerFallbackValue(MockWalletAccount());
  });

  void setupDependencyInjection() {
    final getIt = GetIt.instance;
    final walletService = MockWalletService();
    final stubbedWallet = MockWallet();
    when(() => stubbedWallet.currentAccount).thenReturn(MockWalletAccount());
    when(
      () => walletService.generateUncommittedSeedWallet(any()),
    ).thenAnswer((_) async => stubbedWallet);
    getIt.registerSingleton<WalletService>(walletService);
    final kyc = MockDfxKycService();
    when(() => kyc.ensureSignatureFor(any())).thenAnswer((_) async {});
    getIt.registerSingleton<DfxKycService>(kyc);
  }

  setUpAll(setupDependencyInjection);

  tearDownAll(() async => await GetIt.instance.reset());

  setUp(() {
    createWalletCubit = MockCreateWalletCubit();
    wallet = MockWallet();
    when(() => wallet.seed).thenReturn(_seed);
    when(
      () => createWalletCubit.state,
    ).thenReturn(CreateWalletState(wallet: wallet));
    whenListen(
      createWalletCubit,
      const Stream<CreateWalletState>.empty(),
      initialState: CreateWalletState(wallet: wallet),
    );
  });

  GoRouter buildRouter() => GoRouter(
    initialLocation: '/createWallet',
    routes: [
      GoRoute(
        name: OnboardingRoutes.createWallet,
        path: '/createWallet',
        builder: (_, _) => BlocProvider<CreateWalletCubit>.value(
          value: createWalletCubit,
          child: const CreateWalletView(),
        ),
      ),
      GoRoute(
        name: OnboardingRoutes.verifySeed,
        path: '/verifySeed',
        builder: (_, _) => const Scaffold(
          body: Text('verify-seed-destination'),
        ),
      ),
    ],
  );

  Future<void> pumpScreen(WidgetTester tester, MatrixCell cell) async {
    await tester.binding.setSurfaceSize(cell.mediaQuery.size);
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      MediaQuery(
        data: cell.mediaQuery,
        child: MaterialApp.router(
          routerConfig: buildRouter(),
          locale: const Locale('de'),
          localizationsDelegates: const [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: S.delegate.supportedLocales,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  group('CreateWalletView responsive matrix (full device × textScale)', () {
    for (final cell in kFullResponsiveMatrix) {
      testWidgets(cell.id, (tester) async {
        await withTargetPlatform(cell.device.platform, () async {
          await expectNoLayoutOverflow(
            tester,
            () async {
              await pumpScreen(tester, cell);
            },
            reason: 'overflow on ${cell.label}',
          );

          await expectFullyTappable(
            tester,
            find.byType(AppFilledButton),
            within: find.byType(CreateWalletView),
            reason: '${cell.label}: confirm CTA not tappable',
          );

          // expectFullyTappable ends with a single pump(); GoRouter page
          // transitions need settle before the destination is in the tree.
          await tester.pumpAndSettle();

          expect(
            find.text('verify-seed-destination'),
            findsOneWidget,
            reason: '${cell.label}: confirm tap did not navigate to verifySeed',
          );
        });
      });
    }
  });
}
