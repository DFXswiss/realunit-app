import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/screens/home/bloc/home_bloc.dart';
import 'package:realunit_wallet/screens/verify_seed/cubit/verify_seed_cubit.dart';
import 'package:realunit_wallet/screens/verify_seed/verify_seed_page.dart';

import '../../../helper/helper.dart';

class _MockVerifySeedCubit extends MockCubit<VerifySeedState> implements VerifySeedCubit {}

void main() {
  late _MockVerifySeedCubit verifySeedCubit;
  late MockHomeBloc homeBloc;

  setUpAll(() {
    stubNoScreenshotChannel();
  });

  setUp(() {
    verifySeedCubit = _MockVerifySeedCubit();
    homeBloc = MockHomeBloc();
    when(() => verifySeedCubit.state).thenReturn(
      const VerifySeedState(
        wordIndices: [1, 3, 5, 7],
        enteredWords: ['', '', '', ''],
      ),
    );
    when(() => homeBloc.state).thenReturn(const HomeState());
  });

  Widget buildSubject() => MultiBlocProvider(
    providers: [
      BlocProvider<HomeBloc>.value(value: homeBloc),
      BlocProvider<VerifySeedCubit>.value(value: verifySeedCubit),
    ],
    child: const VerifySeedView(),
  );

  group('$VerifySeedView', () {
    goldenTest(
      'default state with word indices',
      fileName: 'verify_seed_page_default',
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      builder: () => wrapForGolden(buildSubject()),
    );

    goldenTest(
      'all words entered',
      fileName: 'verify_seed_page_all_entered',
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      builder: () {
        when(() => verifySeedCubit.state).thenReturn(
          const VerifySeedState(
            wordIndices: [1, 3, 5, 7],
            enteredWords: ['abandon', 'ability', 'about', 'above'],
          ),
        );
        return wrapForGolden(buildSubject());
      },
    );

    goldenTest(
      'wrong words paint the fields red and show the invalid button',
      fileName: 'verify_seed_page_error',
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      builder: () {
        when(() => verifySeedCubit.state).thenReturn(
          const VerifySeedState(
            wordIndices: [1, 3, 5, 7],
            enteredWords: ['abandon', 'ability', 'about', 'above'],
            hasError: true,
          ),
        );
        return wrapForGolden(buildSubject());
      },
    );

    goldenTest(
      'verifying state shows the loading button',
      fileName: 'verify_seed_page_verifying',
      // The loading button hosts a CupertinoActivityIndicator that never
      // settles; pump once to capture the initial frame.
      pumpBeforeTest: pumpOnce,
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      builder: () {
        when(() => verifySeedCubit.state).thenReturn(
          const VerifySeedState(
            wordIndices: [1, 3, 5, 7],
            enteredWords: ['abandon', 'ability', 'about', 'above'],
            isVerifying: true,
          ),
        );
        return wrapForGolden(buildSubject());
      },
    );

    // The success button is visible for 2s before navigation. The mocked cubit
    // emits no state change, so the isVerified listener (which would await that
    // 2s delay, then dispatch LoadWalletEvent) never fires and the green
    // success button renders stably.
    goldenTest(
      'verified state shows the green success button',
      fileName: 'verify_seed_page_verified',
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      builder: () {
        when(() => verifySeedCubit.state).thenReturn(
          const VerifySeedState(
            wordIndices: [1, 3, 5, 7],
            enteredWords: ['abandon', 'ability', 'about', 'above'],
            isVerified: true,
          ),
        );
        return wrapForGolden(buildSubject());
      },
    );

    goldenTest(
      'commit failure shows an idle retry button with a refresh icon',
      fileName: 'verify_seed_page_commit_failed',
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      builder: () {
        when(() => verifySeedCubit.state).thenReturn(
          const VerifySeedState(
            wordIndices: [1, 3, 5, 7],
            enteredWords: ['abandon', 'ability', 'about', 'above'],
            commitFailed: true,
          ),
        );
        return wrapForGolden(buildSubject());
      },
    );

    goldenTest(
      'empty word indices render nothing but the scaffold',
      fileName: 'verify_seed_page_empty',
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      builder: () {
        when(() => verifySeedCubit.state).thenReturn(const VerifySeedState());
        return wrapForGolden(buildSubject());
      },
    );
  });
}
