import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/screens/home/bloc/home_bloc.dart';
import 'package:realunit_wallet/screens/restore_wallet/cubit/restore_wallet/restore_wallet_cubit.dart';
import 'package:realunit_wallet/screens/restore_wallet/cubit/validate_seed/validate_seed_cubit.dart';
import 'package:realunit_wallet/screens/restore_wallet/restore_wallet_view.dart';

import '../../../helper/helper.dart';

// A valid 12-word BIP39 phrase — every word is in the wordlist, so the mnemonic
// controller renders each in its matching (dark) style rather than the red
// non-match style.
const _seedPhrase =
    'cheese trigger cannon mention judge hire snack sustain annual predict illness celery';

// The 12 mnemonic controllers live inside RestoreWalletView's State and cannot
// be injected, so pasting the phrase into the first cell — which the field's
// paste handler distributes across all 12 controllers — is the only seam to
// populate the fields (it mirrors the real paste flow). Focus is dropped
// afterwards so no blinking cursor makes the capture non-deterministic; a
// single trailing pump is enough (the sibling `valid` baseline already renders
// this page, SVG included, under pumpOnce).
Future<void> _fillSeed(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).first, _seedPhrase);
  await tester.pump();
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
}

class _MockRestoreWalletCubit extends MockCubit<RestoreWalletState>
    implements RestoreWalletCubit {}

class _MockValidateSeedCubit extends MockCubit<ValidateSeedState>
    implements ValidateSeedCubit {}

void main() {
  late _MockRestoreWalletCubit restoreWalletCubit;
  late _MockValidateSeedCubit validateSeedCubit;
  late MockHomeBloc homeBloc;

  setUpAll(() {
    // RestoreWalletView now calls NoScreenshot.screenshotOff() in initState;
    // stub the platform channel so the golden render does not throw a
    // MissingPluginException (same pattern as the sibling seed golden tests).
    stubNoScreenshotChannel();
  });

  setUp(() {
    restoreWalletCubit = _MockRestoreWalletCubit();
    validateSeedCubit = _MockValidateSeedCubit();
    homeBloc = MockHomeBloc();
    when(() => restoreWalletCubit.state).thenReturn(const RestoreWalletState());
    when(() => validateSeedCubit.state).thenReturn(ValidateSeedState.uncomplete);
    when(() => homeBloc.state).thenReturn(const HomeState());
  });

  Widget buildSubject() => MultiBlocProvider(
        providers: [
          BlocProvider<HomeBloc>.value(value: homeBloc),
          BlocProvider<RestoreWalletCubit>.value(value: restoreWalletCubit),
          BlocProvider<ValidateSeedCubit>.value(value: validateSeedCubit),
        ],
        child: const RestoreWalletView(),
      );

  group('$RestoreWalletView', () {
    goldenTest(
      'default state',
      fileName: 'restore_wallet_page_default',
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      builder: () => wrapForGolden(buildSubject()),
    );

    goldenTest(
      'valid seed entered',
      fileName: 'restore_wallet_page_valid',
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      // The valid + invalid states pulse a status banner/icon — the
      // animation never settles, so pumpAndSettle hits its timeout.
      // pumpOnce captures the first frame.
      pumpBeforeTest: pumpOnce,
      builder: () {
        when(() => validateSeedCubit.state).thenReturn(ValidateSeedState.valid);
        return wrapForGolden(buildSubject());
      },
    );

    goldenTest(
      'invalid seed entered',
      fileName: 'restore_wallet_page_invalid',
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      pumpBeforeTest: pumpOnce,
      builder: () {
        when(() => validateSeedCubit.state)
            .thenReturn(ValidateSeedState.invalid);
        return wrapForGolden(buildSubject());
      },
    );

    goldenTest(
      'complete seed enables the next button behind an okker border',
      fileName: 'restore_wallet_page_complete',
      pumpBeforeTest: _fillSeed,
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      builder: () {
        when(() => validateSeedCubit.state)
            .thenReturn(ValidateSeedState.complete);
        return wrapForGolden(buildSubject());
      },
    );

    goldenTest(
      'restore in flight shows the loading button behind an okker border',
      fileName: 'restore_wallet_page_restoring',
      pumpBeforeTest: _fillSeed,
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      builder: () {
        when(() => validateSeedCubit.state).thenReturn(ValidateSeedState.valid);
        when(() => restoreWalletCubit.state)
            .thenReturn(const RestoreWalletState(isLoading: true));
        return wrapForGolden(buildSubject());
      },
    );

    goldenTest(
      'successful restore shows the green success button and border',
      fileName: 'restore_wallet_page_success',
      pumpBeforeTest: _fillSeed,
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      builder: () {
        when(() => validateSeedCubit.state).thenReturn(ValidateSeedState.valid);
        when(() => restoreWalletCubit.state)
            .thenReturn(RestoreWalletState(wallet: MockSoftwareWallet()));
        return wrapForGolden(buildSubject());
      },
    );

    goldenTest(
      'failed restore shows an idle retry button behind a green border',
      fileName: 'restore_wallet_page_failed',
      pumpBeforeTest: _fillSeed,
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      builder: () {
        when(() => validateSeedCubit.state).thenReturn(ValidateSeedState.valid);
        when(() => restoreWalletCubit.state)
            .thenReturn(const RestoreWalletState(hasError: true));
        return wrapForGolden(buildSubject());
      },
    );
  });
}
