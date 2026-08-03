import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/cupertino.dart';
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
import 'package:realunit_wallet/packages/hardware_wallet/bitbox.dart';
import 'package:realunit_wallet/packages/repository/balance_repository.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/balance_service.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_kyc_service.dart';
import 'package:realunit_wallet/packages/service/dfx/models/registration/kyc/kyc_personal_data.dart';
import 'package:realunit_wallet/packages/service/dfx/models/user/dto/real_unit_user_data_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_registration_service.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_transfer_service.dart';
import 'package:realunit_wallet/packages/service/wallet_service.dart';
import 'package:realunit_wallet/packages/utils/default_assets.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';
import 'package:realunit_wallet/packages/wallet/wallet_account.dart';
import 'package:realunit_wallet/screens/hardware_connect_bitbox/connect_bitbox_page.dart';
import 'package:realunit_wallet/screens/home/bloc/home_bloc.dart';
import 'package:realunit_wallet/screens/migrate_bitbox/cubits/migrate_bitbox/migrate_bitbox_cubit.dart';
import 'package:realunit_wallet/screens/migrate_bitbox/migrate_bitbox_page.dart';
import 'package:realunit_wallet/screens/migrate_bitbox/widgets/migrate_intro_view.dart';
import 'package:realunit_wallet/screens/migrate_bitbox/widgets/migrate_register_view.dart';
import 'package:realunit_wallet/screens/migrate_bitbox/widgets/migrate_result_views.dart';
import 'package:realunit_wallet/screens/migrate_bitbox/widgets/migrate_transfer_view.dart';

import '../../helper/pump_app.dart';

class _MockMigrateBitboxCubit extends MockCubit<MigrateBitboxState>
    implements MigrateBitboxCubit {}

class _MockHomeBloc extends MockBloc<HomeEvent, HomeState> implements HomeBloc {}

class _MockWalletService extends Mock implements WalletService {}

class _MockDfxKycService extends Mock implements DfxKycService {}

class _MockRegistrationService extends Mock implements RealUnitRegistrationService {}

class _MockBalanceService extends Mock implements BalanceService {}

class _MockBalanceRepository extends Mock implements BalanceRepository {}

class _MockTransferService extends Mock implements RealUnitTransferService {}

class _MockAppStore extends Mock implements AppStore {}

class _MockApiConfig extends Mock implements ApiConfig {}

class _MockBitboxService extends Mock implements BitboxService {}

class _MockBitboxWallet extends Mock implements BitboxWallet {}

class _MockDebugWallet extends Mock implements DebugWallet {}

class _MockWalletAccount extends Mock implements AWalletAccount {}

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
  final mappingWallet = _MockBitboxWallet();
  late _MockMigrateBitboxCubit cubit;
  late _MockHomeBloc homeBloc;
  late _MockBitboxWallet bitboxWallet;
  late _MockWalletService walletService;
  late _MockWalletAccount draftAccount;

  Balance fixtureBalance() => Balance(
    chainId: realUnitAsset.chainId,
    contractAddress: realUnitAsset.address,
    walletAddress: softwareAddress,
    balance: BigInt.zero,
    asset: realUnitAsset,
  );

  setUpAll(() {
    registerFallbackValue(fixtureBalance());
    registerFallbackValue(_MockBitboxWallet());
    registerFallbackValue(_MockWalletAccount());
    registerFallbackValue(const LoadCurrentWalletEvent());

    walletService = _MockWalletService();
    final authService = _MockDfxKycService();
    final registrationService = _MockRegistrationService();
    final balanceService = _MockBalanceService();
    final balanceRepository = _MockBalanceRepository();
    final transferService = _MockTransferService();
    final appStore = _MockAppStore();
    final apiConfig = _MockApiConfig();
    final bitboxService = _MockBitboxService();
    final debugWallet = _MockDebugWallet();

    when(() => appStore.apiConfig).thenReturn(apiConfig);
    when(() => appStore.primaryAddress).thenReturn(softwareAddress);
    when(() => appStore.wallet).thenReturn(debugWallet);
    when(() => apiConfig.asset).thenReturn(realUnitAsset);
    when(() => debugWallet.walletType).thenReturn(WalletType.debug);
    when(
      () => balanceRepository.watchBalance(any()),
    ).thenAnswer((_) => Stream.value(fixtureBalance()));
    when(() => bitboxService.startScan()).thenAnswer((_) async => true);
    when(() => bitboxService.getAllUsbDevices()).thenAnswer((_) async => []);

    GetIt.instance.registerSingleton<WalletService>(walletService);
    GetIt.instance.registerSingleton<DfxKycService>(authService);
    GetIt.instance.registerSingleton<RealUnitRegistrationService>(
      registrationService,
    );
    GetIt.instance.registerSingleton<BalanceService>(balanceService);
    GetIt.instance.registerSingleton<BalanceRepository>(balanceRepository);
    GetIt.instance.registerSingleton<RealUnitTransferService>(transferService);
    GetIt.instance.registerSingleton<AppStore>(appStore);
    GetIt.instance.registerSingleton<BitboxService>(bitboxService);
  });

  tearDownAll(() async => GetIt.instance.reset());

  setUp(() {
    cubit = _MockMigrateBitboxCubit();
    homeBloc = _MockHomeBloc();
    bitboxWallet = _MockBitboxWallet();
    draftAccount = _MockWalletAccount();
    when(() => homeBloc.state).thenReturn(const HomeState());
    whenListen(
      homeBloc,
      const Stream<HomeState>.empty(),
      initialState: const HomeState(),
    );
    when(() => homeBloc.add(any())).thenReturn(null);
    when(() => cubit.cancelPairing()).thenReturn(null);
    when(() => cubit.onDevicePaired(any())).thenAnswer((_) async {});
    when(() => cubit.draftAccount).thenReturn(draftAccount);
    when(() => cubit.linkedJwt).thenReturn('linked-jwt');
    when(() => cubit.onRegisterCompleted()).thenAnswer((_) async {});
    when(() => cubit.onRegisterPending()).thenReturn(null);
    when(() => cubit.onTransferBroadcast()).thenAnswer((_) async {});
    when(
      () => cubit.onTransferFailedTerminally(any()),
    ).thenReturn(null);
  });

  Future<void> pumpState(
    WidgetTester tester,
    MigrateBitboxState state,
  ) async {
    when(() => cubit.state).thenReturn(state);
    whenListen(
      cubit,
      const Stream<MigrateBitboxState>.empty(),
      initialState: state,
    );
    await tester.pumpApp(
      BlocProvider<HomeBloc>.value(
        value: homeBloc,
        child: BlocProvider<MigrateBitboxCubit>.value(
          value: cubit,
          child: const MigrateBitboxViewManager(),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('$MigrateBitboxPage creates its cubit and renders the intro', (
    tester,
  ) async {
    await tester.pumpApp(const MigrateBitboxPage());
    await tester.pump();

    expect(find.byType(MigrateIntroView), findsOneWidget);
  });

  group('$MigrateBitboxViewManager state to view mapping', () {
    final cases = <(MigrateBitboxState, Type)>[
      (const MigrateBitboxIntro(), MigrateIntroView),
      (const MigrateBitboxAwaitingDevice(), MigrateIntroView),
      (const MigrateBitboxRegisterReady(_userData, '0xbitbox'), MigrateRegisterView),
      (const MigrateBitboxRegistrationPending(), MigrateBitboxRegistrationPendingPage),
      (const MigrateBitboxSettlingTimeout(), MigrateBitboxSettlingTimeoutPage),
      (
        const MigrateBitboxTransferReady(
          fromAddress: '0xfrom',
          toAddress: '0xto',
          amount: 9,
        ),
        MigrateTransferReadyView,
      ),
      (
        const MigrateBitboxTransferring(toAddress: '0xto', amount: 9),
        MigrateTransferringView,
      ),
      (MigrateBitboxSuccess(mappingWallet), MigrateBitboxSuccessPage),
      (
        const MigrateBitboxFailure(MigrateBitboxFailureReason.generic),
        MigrateBitboxFailurePage,
      ),
    ];

    for (final (state, widgetType) in cases) {
      testWidgets('$state renders $widgetType', (tester) async {
        await pumpState(tester, state);

        expect(find.byType(widgetType), findsOneWidget);
      });
    }

    final progressCases = <(MigrateBitboxState, String)>[
      (const MigrateBitboxLinking(), 'linking'),
      (const MigrateBitboxPreparingTransfer(), 'preparing transfer'),
      (const MigrateBitboxSettling(), 'settling'),
      (const MigrateBitboxCompleting(), 'completing'),
    ];
    for (final (state, label) in progressCases) {
      testWidgets('$state renders the $label progress page', (tester) async {
        await pumpState(tester, state);

        expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
        expect(find.byType(Scaffold), findsOneWidget);
      });
    }
  });

  group('$MigrateBitboxViewManager PopScope canPop', () {
    final cases = <(MigrateBitboxState, bool)>[
      (const MigrateBitboxIntro(), true),
      (const MigrateBitboxAwaitingDevice(), false),
      (const MigrateBitboxLinking(), false),
      (const MigrateBitboxRegisterReady(_userData, '0xbitbox'), true),
      (const MigrateBitboxRegistrationPending(), true),
      (const MigrateBitboxPreparingTransfer(), false),
      (
        const MigrateBitboxTransferReady(
          fromAddress: '0xfrom',
          toAddress: '0xto',
          amount: 9,
        ),
        true,
      ),
      (const MigrateBitboxTransferring(toAddress: '0xto', amount: 9), false),
      (const MigrateBitboxSettling(), false),
      (const MigrateBitboxSettlingTimeout(), true),
      (const MigrateBitboxCompleting(), false),
      (MigrateBitboxSuccess(mappingWallet), true),
      (
        const MigrateBitboxFailure(MigrateBitboxFailureReason.generic),
        true,
      ),
    ];

    for (final (state, expected) in cases) {
      testWidgets('$state canPop=$expected', (tester) async {
        await pumpState(tester, state);

        final popScope = tester.widget<PopScope>(find.byType(PopScope).first);
        expect(popScope.canPop, expected);
      });
    }
  });

  testWidgets('AwaitingDevice emission opens the ConnectBitboxPage sheet', (
    tester,
  ) async {
    whenListen(
      cubit,
      Stream<MigrateBitboxState>.value(
        const MigrateBitboxAwaitingDevice(),
      ),
      initialState: const MigrateBitboxIntro(),
    );
    // The sheet's ConnectBitboxView cancel button pops via go_router, so the
    // manager must sit on a real (single-entry) GoRouter stack — mirrors
    // connect_bitbox_view_test.dart's pumpViewOnSingleEntryStack.
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => BlocProvider<HomeBloc>.value(
            value: homeBloc,
            child: BlocProvider<MigrateBitboxCubit>.value(
              value: cubit,
              child: const MigrateBitboxViewManager(),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        localizationsDelegates: [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        routerConfig: router,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(ConnectBitboxPage), findsOneWidget);
    final sheet = tester.widget<ConnectBitboxPage>(
      find.byType(ConnectBitboxPage),
    );
    when(
      () => walletService.acquireUncommittedBitboxWallet(any()),
    ).thenAnswer((_) async => bitboxWallet);

    expect(await sheet.acquireWallet!(), same(bitboxWallet));
    sheet.onFinish(bitboxWallet);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    verify(
      () => walletService.acquireUncommittedBitboxWallet('Luke-Skywallet'),
    ).called(1);
    verify(() => cubit.onDevicePaired(bitboxWallet)).called(1);
    expect(find.byType(ConnectBitboxPage), findsNothing);

    verify(() => cubit.cancelPairing()).called(1);
  });

  testWidgets('Success emission dispatches LoadWalletEvent to HomeBloc', (
    tester,
  ) async {
    whenListen(
      cubit,
      Stream<MigrateBitboxState>.value(MigrateBitboxSuccess(bitboxWallet)),
      initialState: const MigrateBitboxIntro(),
    );
    await tester.pumpApp(
      BlocProvider<HomeBloc>.value(
        value: homeBloc,
        child: BlocProvider<MigrateBitboxCubit>.value(
          value: cubit,
          child: const MigrateBitboxViewManager(),
        ),
      ),
    );
    await tester.pump();

    verify(() => homeBloc.add(LoadWalletEvent(bitboxWallet))).called(1);
  });
}
