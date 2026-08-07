// Responsive matrix gate for RestoreWalletView next CTA.
//
// Proves the restore-wallet primary button stays fully tappable across the
// full device × text-scale matrix (see test/helper/responsive_matrix.dart).
// Regression lock for the IntrinsicHeight + Spacer collapse that pushed the
// CTA below the viewport on first frame without a RenderFlex overflow.
//
// Realistic worst-case content (12-word mnemonic shape; state is mocked):
// 'cheese trigger cannon mention judge hire snack sustain annual predict illness celery'
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_kyc_service.dart';
import 'package:realunit_wallet/packages/service/wallet_service.dart';
import 'package:realunit_wallet/screens/home/bloc/home_bloc.dart';
import 'package:realunit_wallet/screens/restore_wallet/cubit/restore_wallet/restore_wallet_cubit.dart';
import 'package:realunit_wallet/screens/restore_wallet/cubit/validate_seed/validate_seed_cubit.dart';
import 'package:realunit_wallet/screens/restore_wallet/restore_wallet_view.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';

import '../../helper/helper.dart';

class MockRestoreWalletCubit extends MockCubit<RestoreWalletState>
    implements RestoreWalletCubit {}

class MockValidateSeedCubit extends MockCubit<ValidateSeedState>
    implements ValidateSeedCubit {}

class MockHomeBloc extends MockBloc<HomeEvent, HomeState> implements HomeBloc {}

class MockWalletService extends Mock implements WalletService {}

class MockDfxKycService extends Mock implements DfxKycService {}

void main() {
  late RestoreWalletCubit restoreWalletCubit;
  late ValidateSeedCubit validateSeedCubit;
  late HomeBloc homeBloc;

  void setupDependencyInjection() {
    final getIt = GetIt.instance;
    getIt.registerSingleton<WalletService>(MockWalletService());
    getIt.registerSingleton<DfxKycService>(MockDfxKycService());
  }

  setUpAll(setupDependencyInjection);

  tearDownAll(() async => await GetIt.instance.reset());

  setUp(() {
    restoreWalletCubit = MockRestoreWalletCubit();
    validateSeedCubit = MockValidateSeedCubit();
    homeBloc = MockHomeBloc();

    // Primary CTA state: seed is complete (enabled "Next" button).
    // Realistic worst-case mnemonic content (mocked, not typed into fields):
    // 'cheese trigger cannon mention judge hire snack sustain annual predict illness celery'
    when(() => restoreWalletCubit.state).thenReturn(const RestoreWalletState());
    when(() => validateSeedCubit.state).thenReturn(ValidateSeedState.complete);
  });

  Widget buildSubject() {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: homeBloc),
        BlocProvider.value(value: restoreWalletCubit),
        BlocProvider.value(value: validateSeedCubit),
      ],
      child: const RestoreWalletView(),
    );
  }

  Future<void> pumpScreen(WidgetTester tester, MatrixCell cell, Widget child) async {
    await tester.binding.setSurfaceSize(cell.mediaQuery.size);
    addTearDown(() async => await tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MediaQuery(
        data: cell.mediaQuery,
        child: MaterialApp(
          locale: const Locale('de'),
          localizationsDelegates: const [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: S.delegate.supportedLocales,
          home: child,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  group('RestoreWalletView responsive matrix (full device × textScale)', () {
    for (final cell in kFullResponsiveMatrix) {
      testWidgets(cell.id, (tester) async {
        await withTargetPlatform(cell.device.platform, () async {
          await expectNoLayoutOverflow(
            tester,
            () async {
              await pumpScreen(tester, cell, buildSubject());
            },
            reason: 'overflow on ${cell.label}',
          );

          await expectFullyTappable(
            tester,
            find.byType(AppFilledButton),
            within: find.byType(RestoreWalletView),
            reason: '${cell.label}: restore-wallet CTA not tappable',
          );
        });
      });
    }
  });
}
