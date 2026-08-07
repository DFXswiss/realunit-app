import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/screens/kyc/cubits/kyc/kyc_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/ident/cubits/kyc_ident/kyc_ident_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/ident/kyc_ident_page.dart';
import 'package:realunit_wallet/screens/settings/bloc/settings_bloc.dart';

import '../../../helper/helper.dart';

class _MockKycIdentCubit extends MockCubit<KycIdentState>
    implements KycIdentCubit {}

class _MockKycCubit extends MockCubit<KycState> implements KycCubit {}

void main() {
  // The `kyc_ident_page_default` idle baseline lives in
  // `kyc_ident_golden_test.dart`. This file covers the state-driven branches of
  // `KycIdentView` (`kyc_ident_page.dart`): the loading spinner and the two
  // failure surfaces (finallyRejected disables Next permanently; error/other
  // shows the SnackBar over an otherwise idle body).
  late _MockKycIdentCubit kycIdentCubit;
  late _MockKycCubit kycCubit;
  late MockSettingsBloc settingsBloc;

  setUp(() {
    kycIdentCubit = _MockKycIdentCubit();
    kycCubit = _MockKycCubit();
    settingsBloc = MockSettingsBloc();

    when(() => kycIdentCubit.state).thenReturn(const KycIdentInitial());
    when(() => kycCubit.state).thenReturn(const KycInitial());
    when(() => settingsBloc.state).thenReturn(const SettingsState());
  });

  Widget buildSubject() => wrapForGolden(
        MultiBlocProvider(
          providers: [
            BlocProvider<KycIdentCubit>.value(value: kycIdentCubit),
            BlocProvider<KycCubit>.value(value: kycCubit),
            BlocProvider<SettingsBloc>.value(value: settingsBloc),
          ],
          child: const KycIdentView(accessToken: 'fake-token'),
        ),
      );

  // The page mounts an Image.asset illustration. alchemist's precacheImages
  // decodes assets inside runAsync — a plain pump cannot await that I/O — so
  // replicate the runAsync precache here before freezing/settling.
  Future<void> precacheIllustration(WidgetTester tester) async {
    await tester.runAsync(() async {
      for (final element in find.byType(Image).evaluate()) {
        await precacheImage((element.widget as Image).image, element);
      }
    });
  }

  // Precache, then a single pump freezes the loading button's
  // CupertinoActivityIndicator on frame 0 (pumpAndSettle would time out on it).
  Future<void> precacheThenFreeze(WidgetTester tester) async {
    await precacheIllustration(tester);
    await tester.pump();
  }

  // Precache, deliver the whenListen emission (fires showSnackBar), then settle
  // the SnackBar entrance. The failure bodies host no spinner, so settling is
  // safe.
  Future<void> precacheThenSettle(WidgetTester tester) async {
    await precacheIllustration(tester);
    await tester.pump();
    await tester.pumpAndSettle();
  }

  group('$KycIdentView', () {
    // KycIdentLoading → the Next AppFilledButton renders its loading spinner
    // (page:121-122).
    goldenTest(
      'ident launch in flight — next button spinner',
      fileName: 'kyc_ident_page_loading',
      constraints: phoneConstraints,
      pumpBeforeTest: precacheThenFreeze,
      builder: () {
        when(() => kycIdentCubit.state).thenReturn(const KycIdentLoading());
        return buildSubject();
      },
    );

    // KycIdentFailure(finallyRejected) → the Next button is permanently disabled
    // (page:113-119) and the red `identityCheckFinallyFailed` SnackBar fires
    // (page:47-56).
    goldenTest(
      'finally rejected — disabled next + red snackbar',
      fileName: 'kyc_ident_page_finally_rejected',
      constraints: phoneConstraints,
      pumpBeforeTest: precacheThenSettle,
      builder: () {
        whenListen(
          kycIdentCubit,
          Stream<KycIdentState>.value(
            const KycIdentFailure(status: FailureStatus.finallyRejected),
          ),
          initialState: const KycIdentInitial(),
        );
        return buildSubject();
      },
    );

    // KycIdentFailure(error) → the red `identityCheckFailed` SnackBar fires
    // (page:57-65) while the body stays on the idle Next button (page:121-130).
    goldenTest(
      'error — red snackbar over the idle body',
      fileName: 'kyc_ident_page_error',
      constraints: phoneConstraints,
      pumpBeforeTest: precacheThenSettle,
      builder: () {
        whenListen(
          kycIdentCubit,
          Stream<KycIdentState>.value(
            const KycIdentFailure(
              status: FailureStatus.error,
              errorMessage: 'network unreachable',
            ),
          ),
          initialState: const KycIdentInitial(),
        );
        return buildSubject();
      },
    );
  });
}
