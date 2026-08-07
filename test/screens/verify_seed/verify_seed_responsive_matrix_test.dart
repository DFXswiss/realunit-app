// Responsive matrix gate for VerifySeedView confirm CTA.
//
// Proves the seed-verify confirm button stays fully tappable across the full
// device × text-scale matrix (see test/helper/responsive_matrix.dart).
// Regression lock for the IntrinsicHeight + Spacer collapse that pushed the
// CTA below the viewport on first frame without a RenderFlex overflow.
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/wallet_service.dart';
import 'package:realunit_wallet/screens/home/bloc/home_bloc.dart';
import 'package:realunit_wallet/screens/verify_seed/cubit/verify_seed_cubit.dart';
import 'package:realunit_wallet/screens/verify_seed/verify_seed_page.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';

import '../../helper/helper.dart';

class MockVerifySeedCubit extends MockCubit<VerifySeedState> implements VerifySeedCubit {}

class MockHomeBloc extends MockBloc<HomeEvent, HomeState> implements HomeBloc {}

class MockWalletService extends Mock implements WalletService {}

/// Realistic long DE recovery words for worst-case field content.
const _enteredWords = ['tapfer', 'gewitter', 'monster', 'sonnenschein'];

void main() {
  late VerifySeedCubit verifySeedCubit;
  late HomeBloc homeBloc;

  void setupDependencyInjection() {
    final getIt = GetIt.instance;
    getIt.registerSingleton<WalletService>(MockWalletService());
  }

  setUpAll(setupDependencyInjection);

  tearDownAll(() async => await GetIt.instance.reset());

  setUp(() {
    verifySeedCubit = MockVerifySeedCubit();
    homeBloc = MockHomeBloc();

    const state = VerifySeedState(
      wordIndices: [1, 3, 5, 7],
      enteredWords: _enteredWords,
    );
    when(() => verifySeedCubit.state).thenReturn(state);
    whenListen(
      verifySeedCubit,
      const Stream<VerifySeedState>.empty(),
      initialState: state,
    );
    when(() => verifySeedCubit.verify()).thenAnswer((_) async => true);
  });

  Widget buildSubject() {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: homeBloc),
        BlocProvider.value(value: verifySeedCubit),
      ],
      child: const VerifySeedView(),
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

  group('VerifySeedView responsive matrix (full device × textScale)', () {
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
            within: find.byType(VerifySeedView),
            reason: '${cell.label}: verify-seed CTA not tappable',
          );
        });
      });
    }
  });
}
