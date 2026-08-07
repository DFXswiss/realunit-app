import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/screens/kyc/cubits/kyc/kyc_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/2fa/cubits/kyc_2fa/kyc_2fa_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/2fa/cubits/kyc_2fa_verify/kyc_2fa_verify_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/2fa/kyc_2fa_page.dart';

import '../../../helper/helper.dart';

class _MockKyc2FaCubit extends MockCubit<Kyc2FaState> implements Kyc2FaCubit {}

class _MockKyc2FaVerifyCubit extends MockCubit<Kyc2FaVerifyState>
    implements Kyc2FaVerifyCubit {}

class _MockKycCubit extends MockCubit<KycState> implements KycCubit {}

void main() {
  // The `kyc_2fa_page_default` idle baseline lives in `kyc_2fa_golden_test.dart`.
  // This file covers the state-driven branches of `Kyc2FaView`
  // (`kyc_2fa_page.dart`): the two loading spinners and the two red error
  // SnackBars fired from the `MultiBlocListener`.
  //
  // Documented skip — the code-field validation messages (`twoFaCodeRequired`
  // / `registerPhoneNumberOnlyDigits` / `twoFaCodeTooShort`, page:117-127)
  // render only after the Next button runs `_formKey.currentState!.validate()`.
  // The `Form` has no `autovalidateMode` and no state mirrors the validator
  // output, so the message is purely interaction-driven with no State seam — a
  // text-field validate() error, skipped per the golden-states convention.
  late _MockKyc2FaCubit kyc2FaCubit;
  late _MockKyc2FaVerifyCubit kyc2FaVerifyCubit;
  late _MockKycCubit kycCubit;

  setUp(() {
    kyc2FaCubit = _MockKyc2FaCubit();
    kyc2FaVerifyCubit = _MockKyc2FaVerifyCubit();
    kycCubit = _MockKycCubit();

    when(() => kyc2FaCubit.state).thenReturn(const Kyc2FaInitial());
    when(() => kyc2FaCubit.requestCode()).thenAnswer((_) => Future.value());
    when(() => kyc2FaVerifyCubit.state).thenReturn(const Kyc2FaVerifyInitial());
    when(() => kycCubit.state).thenReturn(const KycInitial());
  });

  Widget buildSubject() => wrapForGolden(
        MultiBlocProvider(
          providers: [
            BlocProvider<Kyc2FaCubit>.value(value: kyc2FaCubit),
            BlocProvider<Kyc2FaVerifyCubit>.value(value: kyc2FaVerifyCubit),
            BlocProvider<KycCubit>.value(value: kycCubit),
          ],
          child: const Kyc2FaView(),
        ),
      );

  // Deliver the whenListen emission to the MultiBlocListener (which fires
  // showSnackBar), then run the SnackBar entrance to completion. The 4s
  // auto-dismiss is a Timer, not a scheduled frame, so pumpAndSettle returns
  // with the SnackBar at rest.
  Future<void> settleSnackBar(WidgetTester tester) async {
    await tester.pump();
    await tester.pumpAndSettle();
  }

  group('$Kyc2FaView', () {
    // Kyc2FaVerifyLoading → the Next AppFilledButton renders its loading variant
    // (CupertinoActivityIndicator, page:135-136). Freeze the spinner on frame 0.
    goldenTest(
      'verify in flight — next button spinner',
      fileName: 'kyc_2fa_page_verify_loading',
      constraints: phoneConstraints,
      pumpBeforeTest: pumpOnce,
      builder: () {
        when(() => kyc2FaVerifyCubit.state)
            .thenReturn(const Kyc2FaVerifyLoading());
        return buildSubject();
      },
    );

    // Kyc2FaLoading → the resend AppTextButton is disabled and shows the
    // "Sending…" label (page:146-158). No spinner, so the default settle applies.
    goldenTest(
      'resend in flight — disabled sending label',
      fileName: 'kyc_2fa_page_resend_loading',
      constraints: phoneConstraints,
      builder: () {
        when(() => kyc2FaCubit.state).thenReturn(const Kyc2FaLoading());
        return buildSubject();
      },
    );

    // Kyc2FaVerifyFailure → red `twoFaWrongCode` SnackBar (page:66-72).
    goldenTest(
      'verify failure — red wrong-code snackbar',
      fileName: 'kyc_2fa_page_verify_failure',
      constraints: phoneConstraints,
      pumpBeforeTest: settleSnackBar,
      builder: () {
        whenListen(
          kyc2FaVerifyCubit,
          Stream<Kyc2FaVerifyState>.value(
            const Kyc2FaVerifyFailure(errorMessage: 'invalid code'),
          ),
          initialState: const Kyc2FaVerifyInitial(),
        );
        return buildSubject();
      },
    );

    // Kyc2FaFailure → red `twoFaSendCodeFailed` SnackBar (page:76-88).
    goldenTest(
      'request-code failure — red send-failed snackbar',
      fileName: 'kyc_2fa_page_request_code_failure',
      constraints: phoneConstraints,
      pumpBeforeTest: settleSnackBar,
      builder: () {
        whenListen(
          kyc2FaCubit,
          Stream<Kyc2FaState>.value(
            const Kyc2FaFailure(errorMessage: 'rate limited'),
          ),
          initialState: const Kyc2FaInitial(),
        );
        when(() => kyc2FaCubit.requestCode()).thenAnswer((_) => Future.value());
        return buildSubject();
      },
    );
  });
}
