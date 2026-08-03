import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/models/balance.dart';
import 'package:realunit_wallet/models/transaction.dart';
import 'package:realunit_wallet/packages/config/api_config.dart';
import 'package:realunit_wallet/packages/repository/transaction_repository.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/models/transactions/dto/transactions_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_pdf_service.dart';
import 'package:realunit_wallet/packages/utils/default_assets.dart';
import 'package:realunit_wallet/screens/dashboard/bloc/balance_cubit.dart';
import 'package:realunit_wallet/screens/dashboard/bloc/dashboard_bloc.dart';
import 'package:realunit_wallet/screens/dashboard/bloc/pending_transactions_cubit.dart';
import 'package:realunit_wallet/screens/dashboard/dashboard_page.dart';
import 'package:realunit_wallet/screens/settings/bloc/settings_bloc.dart';
import 'package:realunit_wallet/styles/currency.dart';

import '../../../helper/helper.dart';

class _MockTransactionRepository extends Mock implements TransactionRepository {}

class _MockRealUnitPdfService extends Mock implements RealUnitPdfService {}

class _MockApiConfig extends Mock implements ApiConfig {}

class _MockDashboardBloc extends MockBloc<DashboardEvent, DashboardState>
    implements DashboardBloc {}

class _MockBalanceCubit extends MockCubit<Balance> implements BalanceCubit {}

class _MockPendingTransactionsCubit extends MockCubit<List<TransactionDto>>
    implements PendingTransactionsCubit {}

void main() {
  late _MockDashboardBloc dashboardBloc;
  late _MockBalanceCubit balanceCubit;
  late _MockPendingTransactionsCubit pendingTxCubit;
  late MockSettingsBloc settingsBloc;

  Balance zeroBalance() => Balance(
        chainId: realUnitAsset.chainId,
        contractAddress: realUnitAsset.address,
        walletAddress: '0x0',
        balance: BigInt.zero,
        asset: realUnitAsset,
      );

  DashboardState emptyDashboardState() => DashboardState(
        price: BigInt.zero,
        priceChart: const [],
        portfolioHistory: const [],
        currency: Currency.chf,
      );

  setUpAll(() {
    final getIt = GetIt.instance;
    final apiConfig = _MockApiConfig();
    final appStore = MockAppStore();
    final transactionRepository = _MockTransactionRepository();
    when(() => apiConfig.asset).thenReturn(realUnitAsset);
    when(() => appStore.apiConfig).thenReturn(apiConfig);
    when(() => appStore.primaryAddress).thenReturn('0x0');
    when(() => transactionRepository.watchTransactionsOfAssets(
              any(),
              any(),
              any(),
            ))
        .thenAnswer((_) => const Stream<List<Transaction>>.empty());
    getIt.registerSingleton<AppStore>(appStore);
    getIt.registerSingleton<RealUnitPdfService>(_MockRealUnitPdfService());
    getIt.registerSingleton<TransactionRepository>(transactionRepository);
  });

  tearDownAll(() async => GetIt.instance.reset());

  setUp(() {
    dashboardBloc = _MockDashboardBloc();
    balanceCubit = _MockBalanceCubit();
    pendingTxCubit = _MockPendingTransactionsCubit();
    settingsBloc = MockSettingsBloc();

    when(() => dashboardBloc.state).thenReturn(emptyDashboardState());
    when(() => balanceCubit.state).thenReturn(zeroBalance());
    when(() => balanceCubit.asset).thenReturn(realUnitAsset);
    when(() => pendingTxCubit.state).thenReturn(const <TransactionDto>[]);
    when(() => settingsBloc.state).thenReturn(const SettingsState());
  });

  Widget buildSubject() => MultiBlocProvider(
        providers: [
          BlocProvider<SettingsBloc>.value(value: settingsBloc),
          BlocProvider<DashboardBloc>.value(value: dashboardBloc),
          BlocProvider<BalanceCubit>.value(value: balanceCubit),
          BlocProvider<PendingTransactionsCubit>.value(value: pendingTxCubit),
        ],
        child: const DashboardView(),
      );

  group('$DashboardView', () {
    goldenTest(
      'empty balance, no transactions',
      fileName: 'dashboard_empty',
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      builder: () => wrapForGolden(buildSubject()),
    );

    goldenTest(
      'with balance, no transactions',
      fileName: 'dashboard_with_balance',
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      builder: () {
        when(() => balanceCubit.state).thenReturn(
          Balance(
            chainId: realUnitAsset.chainId,
            contractAddress: realUnitAsset.address,
            walletAddress: '0x0',
            balance: BigInt.from(5000000000000000000),
            asset: realUnitAsset,
          ),
        );
        return wrapForGolden(buildSubject());
      },
    );
    goldenTest(
      'insider features unlocked',
      fileName: 'dashboard_insider_unlocked',
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      builder: () {
        when(() => settingsBloc.state)
            .thenReturn(const SettingsState(insiderFeaturesUnlocked: true));
        when(() => balanceCubit.state).thenReturn(
          Balance(
            chainId: realUnitAsset.chainId,
            contractAddress: realUnitAsset.address,
            walletAddress: '0x0',
            balance: BigInt.from(5000000000000000000),
            asset: realUnitAsset,
          ),
        );
        return wrapForGolden(buildSubject());
      },
    );
  });
}
