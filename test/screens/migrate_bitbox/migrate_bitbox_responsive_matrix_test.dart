import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/models/balance.dart';
import 'package:realunit_wallet/packages/config/api_config.dart';
import 'package:realunit_wallet/packages/repository/balance_repository.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/models/registration/kyc/kyc_personal_data.dart';
import 'package:realunit_wallet/packages/service/dfx/models/user/dto/real_unit_user_data_dto.dart';
import 'package:realunit_wallet/packages/utils/default_assets.dart';
import 'package:realunit_wallet/screens/migrate_bitbox/cubits/migrate_bitbox/migrate_bitbox_cubit.dart';
import 'package:realunit_wallet/screens/migrate_bitbox/widgets/migrate_intro_view.dart';
import 'package:realunit_wallet/screens/migrate_bitbox/widgets/migrate_register_view.dart';
import 'package:realunit_wallet/screens/migrate_bitbox/widgets/migrate_result_views.dart';
import 'package:realunit_wallet/screens/migrate_bitbox/widgets/migrate_transfer_view.dart';
import 'package:realunit_wallet/setup/routing/routes/app_routes.dart';
import 'package:realunit_wallet/styles/themes.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';

import '../../helper/helper.dart';

class _MockMigrateBitboxCubit extends MockCubit<MigrateBitboxState>
    implements MigrateBitboxCubit {}

class _MockBalanceRepository extends Mock implements BalanceRepository {}

class _MockAppStore extends Mock implements AppStore {}

class _MockApiConfig extends Mock implements ApiConfig {}

const _userData = RealUnitUserDataDto(
  email: 'ada@example.com',
  name: 'Ada Lovelace with an intentionally long accessibility name',
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
  const address = '0x0000000000000000000000000000000000000001';

  Balance fixtureBalance() => Balance(
    chainId: realUnitAsset.chainId,
    contractAddress: realUnitAsset.address,
    walletAddress: address,
    balance: BigInt.from(999999999),
    asset: realUnitAsset,
  );

  setUpAll(() {
    registerFallbackValue(fixtureBalance());
    final appStore = _MockAppStore();
    final apiConfig = _MockApiConfig();
    final balanceRepository = _MockBalanceRepository();
    when(() => appStore.apiConfig).thenReturn(apiConfig);
    when(() => appStore.primaryAddress).thenReturn(address);
    when(() => apiConfig.asset).thenReturn(realUnitAsset);
    when(
      () => balanceRepository.watchBalance(any()),
    ).thenAnswer((_) => Stream.value(fixtureBalance()));
    GetIt.instance.registerSingleton<AppStore>(appStore);
    GetIt.instance.registerSingleton<BalanceRepository>(balanceRepository);
  });

  tearDownAll(() async => GetIt.instance.reset());

  _MockMigrateBitboxCubit buildCubit() {
    final cubit = _MockMigrateBitboxCubit();
    when(() => cubit.state).thenReturn(const MigrateBitboxIntro());
    whenListen(
      cubit,
      const Stream<MigrateBitboxState>.empty(),
      initialState: const MigrateBitboxIntro(),
    );
    when(() => cubit.startPairing()).thenAnswer((_) async {});
    when(() => cubit.register()).thenAnswer((_) async {});
    when(() => cubit.startTransfer()).thenReturn(null);
    when(() => cubit.retry()).thenAnswer((_) async {});
    return cubit;
  }

  Future<void> pumpSurface(
    WidgetTester tester,
    MatrixCell cell,
    Widget surface,
    _MockMigrateBitboxCubit cubit,
  ) async {
    await tester.binding.setSurfaceSize(cell.mediaQuery.size);
    addTearDown(() async => tester.binding.setSurfaceSize(null));
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('matrix-host')),
        ),
        GoRoute(
          path: '/surface',
          builder: (_, _) => BlocProvider<MigrateBitboxCubit>.value(
            value: cubit,
            child: surface,
          ),
        ),
        GoRoute(
          name: AppRoutes.dashboard,
          path: '/dashboard',
          builder: (_, _) => const Scaffold(body: Text('dashboard')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MediaQuery(
        data: cell.mediaQuery,
        child: MaterialApp.router(
          routerConfig: router,
          theme: realUnitTheme,
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
    router.push('/surface');
    await tester.pumpAndSettle();
  }

  final surfaces = <(String, Widget Function(), Type)>[
    ('intro', () => const MigrateIntroView(), MigrateIntroView),
    (
      'register',
      () => const MigrateRegisterView(
        userData: _userData,
        bitboxAddress: '0x1234567890abcdef1234567890abcdef12345678',
      ),
      MigrateRegisterView,
    ),
    (
      'transfer-ready',
      () => const MigrateTransferReadyView(
        fromAddress: '0x1234567890abcdef1234567890abcdef12345678',
        toAddress: '0xabcdef1234567890abcdef1234567890abcdef12',
        amount: 999999999,
      ),
      MigrateTransferReadyView,
    ),
    (
      'registration-pending',
      () => const MigrateBitboxRegistrationPendingPage(),
      MigrateBitboxRegistrationPendingPage,
    ),
    (
      'success',
      () => const MigrateBitboxSuccessPage(),
      MigrateBitboxSuccessPage,
    ),
    (
      'failure-retryable',
      () => const MigrateBitboxFailurePage(
        reason: MigrateBitboxFailureReason.registrationMissing,
        canRetry: true,
      ),
      MigrateBitboxFailurePage,
    ),
    (
      'failure-terminal',
      () => const MigrateBitboxFailurePage(
        reason: MigrateBitboxFailureReason.addressAlreadyLinked,
        canRetry: false,
      ),
      MigrateBitboxFailurePage,
    ),
  ];

  for (final (surfaceId, buildSurface, surfaceType) in surfaces) {
    group('$surfaceId responsive matrix (full device × textScale)', () {
      for (final cell in kFullResponsiveMatrix) {
        testWidgets(cell.id, (tester) async {
          await withTargetPlatform(cell.device.platform, () async {
            final cubit = buildCubit();
            await expectNoLayoutOverflow(
              tester,
              () => pumpSurface(tester, cell, buildSurface(), cubit),
              reason: '$surfaceId overflow on ${cell.label}',
            );

            await expectFullyTappable(
              tester,
              find.byType(AppFilledButton).first,
              within: find.byType(surfaceType),
              reason: '$surfaceId primary CTA not tappable on ${cell.label}',
            );
            await tester.pumpAndSettle();
          });
        });
      }
    });
  }
}
