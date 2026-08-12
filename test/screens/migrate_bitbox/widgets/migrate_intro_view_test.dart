import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/models/balance.dart';
import 'package:realunit_wallet/packages/config/api_config.dart';
import 'package:realunit_wallet/packages/repository/balance_repository.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/utils/default_assets.dart';
import 'package:realunit_wallet/screens/migrate_bitbox/cubits/migrate_bitbox/migrate_bitbox_cubit.dart';
import 'package:realunit_wallet/screens/migrate_bitbox/widgets/migrate_intro_view.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';

import '../../../helper/pump_app.dart';

class _MockMigrateBitboxCubit extends MockCubit<MigrateBitboxState>
    implements MigrateBitboxCubit {}

class _MockBalanceRepository extends Mock implements BalanceRepository {}

class _MockAppStore extends Mock implements AppStore {}

class _MockApiConfig extends Mock implements ApiConfig {}

void main() {
  const address = '0x0000000000000000000000000000000000000001';
  late _MockMigrateBitboxCubit cubit;
  late _MockBalanceRepository balanceRepository;

  Balance fixtureBalance([int amount = 0]) => Balance(
    chainId: realUnitAsset.chainId,
    contractAddress: realUnitAsset.address,
    walletAddress: address,
    balance: BigInt.from(amount),
    asset: realUnitAsset,
  );

  setUpAll(() {
    registerFallbackValue(fixtureBalance());
    final appStore = _MockAppStore();
    final apiConfig = _MockApiConfig();
    when(() => appStore.apiConfig).thenReturn(apiConfig);
    when(() => appStore.primaryAddress).thenReturn(address);
    when(() => apiConfig.asset).thenReturn(realUnitAsset);
    GetIt.instance.registerSingleton<AppStore>(appStore);
  });

  tearDownAll(() async => GetIt.instance.reset());

  setUp(() {
    cubit = _MockMigrateBitboxCubit();
    balanceRepository = _MockBalanceRepository();
    when(() => cubit.state).thenReturn(const MigrateBitboxIntro());
    whenListen(
      cubit,
      const Stream<MigrateBitboxState>.empty(),
      initialState: const MigrateBitboxIntro(),
    );
    when(() => cubit.startPairing()).thenAnswer((_) async {});
    when(
      () => balanceRepository.watchBalance(any()),
    ).thenAnswer((_) => Stream.value(fixtureBalance(123)));
    GetIt.instance.registerSingleton<BalanceRepository>(balanceRepository);
  });

  tearDown(() async {
    await GetIt.instance.unregister<BalanceRepository>();
  });

  testWidgets('shows the live balance and starts pairing from the primary CTA', (
    tester,
  ) async {
    await tester.pumpApp(
      BlocProvider<MigrateBitboxCubit>.value(
        value: cubit,
        child: const MigrateIntroView(),
      ),
    );
    await tester.pump();

    expect(find.textContaining('123'), findsOneWidget);
    await tester.tap(find.byType(AppFilledButton));

    verify(() => cubit.startPairing()).called(1);
  });
}
