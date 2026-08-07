import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/screens/kyc/cubits/kyc/kyc_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/email/cubits/email_step/kyc_email_step_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/email/kyc_email_page.dart';

import '../../../helper/helper.dart';

class _MockKycEmailStepCubit extends MockCubit<KycEmailStepState>
    implements KycEmailStepCubit {}

class _MockKycCubit extends MockCubit<KycState> implements KycCubit {}

void main() {
  // `kyc_email_page_{default,loading,does_not_match,unknown_error}` in
  // `kyc_email_golden_test.dart` stub the failure through the `state` getter
  // only, so the form's `BlocListener` never fires and no SnackBar is present
  // (those goldens render the plain form and feed the handbook screenshots).
  // This file renders the actual red error SnackBars by emitting the failure as
  // a state *transition* through the real `BlocListener`
  // (`KycEmailForm`, kyc_email_page.dart:58-70).
  //
  // Documented skip — inline field-validation errors (`registerEmailRequired`
  // for an empty field, `registerEmailInvalid` for a malformed one): the
  // `TextFormField` sets no `autovalidateMode` (`labeled_text_field.dart:47`)
  // and the `Form` only validates from the Next-button `onPressed`
  // (kyc_email_page.dart:127). There is no state- or autovalidate-driven path to
  // the inline error, so rendering it would require simulating the button tap —
  // an interaction-driven `Form.validate()` error, out of scope for these state
  // baselines.
  late _MockKycEmailStepCubit emailStepCubit;
  late _MockKycCubit kycCubit;

  setUp(() {
    emailStepCubit = _MockKycEmailStepCubit();
    kycCubit = _MockKycCubit();
    when(() => kycCubit.state).thenReturn(const KycInitial());
  });

  Widget buildSubject() => wrapForGolden(
        MultiBlocProvider(
          providers: [
            BlocProvider<KycEmailStepCubit>.value(value: emailStepCubit),
            BlocProvider<KycCubit>.value(value: kycCubit),
          ],
          child: const KycEmailView(),
        ),
      );

  Future<void> pumpSnackBar(WidgetTester tester) async {
    await tester.pump(); // deliver the whenListen emission to the BlocListener
    await tester.pumpAndSettle(); // run the SnackBar entrance to completion
  }

  group('$KycEmailView', () {
    // error == emailDoesNotMatch → the listener shows the localized
    // `registerEmailDoesNotMatch` copy (kyc_email_page.dart:61-63), not
    // `state.message`.
    goldenTest(
      'emailDoesNotMatch failure — red error SnackBar',
      fileName: 'kyc_email_page_error_snackbar_does_not_match',
      constraints: phoneConstraints,
      pumpBeforeTest: pumpSnackBar,
      builder: () {
        whenListen(
          emailStepCubit,
          Stream<KycEmailStepState>.value(
            const KycEmailStepFailure(
              KycEmailStepError.emailDoesNotMatch,
              'unused — the listener renders registerEmailDoesNotMatch',
            ),
          ),
          initialState: const KycEmailStepInitial(),
        );
        return buildSubject();
      },
    );

    // error == unknown → the listener shows `state.message` verbatim
    // (kyc_email_page.dart:63).
    goldenTest(
      'unknown failure — red error SnackBar',
      fileName: 'kyc_email_page_error_snackbar_unknown',
      constraints: phoneConstraints,
      pumpBeforeTest: pumpSnackBar,
      builder: () {
        whenListen(
          emailStepCubit,
          Stream<KycEmailStepState>.value(
            const KycEmailStepFailure(
              KycEmailStepError.unknown,
              'Etwas ist schiefgelaufen. Bitte versuchen Sie es erneut.',
            ),
          ),
          initialState: const KycEmailStepInitial(),
        );
        return buildSubject();
      },
    );
  });
}
