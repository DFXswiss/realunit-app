import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/hardware_wallet/bitbox_credentials.dart';
import 'package:realunit_wallet/packages/wallet/wallet_account.dart';
import 'package:realunit_wallet/screens/home/bloc/home_bloc.dart';
import 'package:realunit_wallet/screens/kyc/steps/email/cubits/email_verification/kyc_email_verification_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/email/subpages/kyc_email_verification_page.dart';

import '../../../helper/helper.dart';

class _MockKycEmailVerificationCubit
    extends MockCubit<KycEmailVerificationState>
    implements KycEmailVerificationCubit {}

void main() {
  // `kyc_email_verification_page_default` (initial state) lives in
  // `kyc_email_verification_golden_test.dart`. This file covers the loading and
  // failure branches of `KycEmailVerificationView`
  // (`kyc_email_verification_page.dart`).
  //
  // `isBitbox` is derived from the HomeBloc wallet, not the verification cubit
  // (page:82-87): `openWallet?.currentAccount.primaryAddress is BitboxCredentials`.
  // A null `openWallet` (software default) resolves to `false`; a
  // `BitboxWalletAccount` whose `primaryAddress` is a real `BitboxCredentials`
  // resolves to `true`, gating the multi-page BitBox sign hint (page:98-105).
  late _MockKycEmailVerificationCubit verificationCubit;
  late MockHomeBloc homeBloc;

  setUp(() {
    verificationCubit = _MockKycEmailVerificationCubit();
    homeBloc = MockHomeBloc();
    when(() => verificationCubit.state)
        .thenReturn(const KycEmailVerificationInitial());
    when(() => homeBloc.state).thenReturn(const HomeState());
  });

  Widget buildSubject() => wrapForGolden(
        MultiBlocProvider(
          providers: [
            BlocProvider<KycEmailVerificationCubit>.value(
              value: verificationCubit,
            ),
            BlocProvider<HomeBloc>.value(value: homeBloc),
          ],
          child: const KycEmailVerificationView(),
        ),
      );

  // The illustration `SvgPicture.asset` loads asynchronously and the loading
  // button hosts a `CupertinoActivityIndicator` that animates forever, so
  // pumpAndSettle would hang. Pump a fixed set of frames instead: enough for
  // flutter_svg's microtask-based asset load to resolve, with the spinner
  // frozen at a deterministic phase (fixed elapsed time across regens).
  Future<void> pumpLoadingSpinner(WidgetTester tester) async {
    await tester.pump(); // build + mount the SVG and the spinner
    await tester.pump(const Duration(milliseconds: 32)); // resolve SVG load
    await tester.pump(const Duration(milliseconds: 32)); // paint the SVG
  }

  group('$KycEmailVerificationView', () {
    // isLoading && !isBitbox → button spinner, no BitBox hint (software wallet).
    goldenTest(
      'loading — button spinner, software wallet (no BitBox hint)',
      fileName: 'kyc_email_verification_page_loading',
      constraints: phoneConstraints,
      pumpBeforeTest: pumpLoadingSpinner,
      builder: () {
        when(() => verificationCubit.state)
            .thenReturn(const KycEmailVerificationLoading());
        return buildSubject();
      },
    );

    // isLoading && isBitbox → button spinner plus the multi-page BitBox sign
    // hint text.
    goldenTest(
      'loading — button spinner + BitBox sign hint',
      fileName: 'kyc_email_verification_page_loading_bitbox',
      constraints: phoneConstraints,
      pumpBeforeTest: pumpLoadingSpinner,
      builder: () {
        when(() => verificationCubit.state)
            .thenReturn(const KycEmailVerificationLoading());
        final bitboxWallet = MockBitboxWallet();
        when(() => bitboxWallet.currentAccount).thenReturn(
          BitboxWalletAccount(
            0,
            BitboxCredentials('0x0000000000000000000000000000000000000001'),
          ),
        );
        when(() => homeBloc.state)
            .thenReturn(HomeState(openWallet: bitboxWallet));
        return buildSubject();
      },
    );

    // A KycEmailVerificationFailure emitted as a transition fires the
    // BlocListener (page:34-42) → red "verification failed" SnackBar. The state
    // is not loading, so the button is idle (no spinner) and pumpAndSettle runs
    // the SnackBar entrance to completion.
    goldenTest(
      'verification failed — red error SnackBar',
      fileName: 'kyc_email_verification_page_error_snackbar',
      constraints: phoneConstraints,
      pumpBeforeTest: (tester) async {
        await tester.pump(); // deliver the whenListen emission to the listener
        await tester.pumpAndSettle(); // SVG load + SnackBar entrance
      },
      builder: () {
        whenListen(
          verificationCubit,
          Stream<KycEmailVerificationState>.value(
            const KycEmailVerificationFailure(),
          ),
          initialState: const KycEmailVerificationInitial(),
        );
        return buildSubject();
      },
    );
  });
}
