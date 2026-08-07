import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/dfx/models/kyc/dto/kyc_financial_data_dto.dart';
import 'package:realunit_wallet/screens/kyc/cubits/kyc/kyc_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/financial_data/cubits/kyc_financial_data_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/financial_data/kyc_financial_data_page.dart';

import '../../../helper/helper.dart';

class _MockKycFinancialDataCubit extends MockCubit<KycFinancialDataState>
    implements KycFinancialDataCubit {}

class _MockKycCubit extends MockCubit<KycState> implements KycCubit {}

void main() {
  // `kyc_financial_data_page_default` (the loading spinner) lives in
  // `kyc_financial_data_golden_test.dart`. This file covers the remaining
  // rendered branches of the `KycFinancialDataView` switch
  // (`kyc_financial_data_page.dart:60-68`).
  late _MockKycFinancialDataCubit financialDataCubit;
  late _MockKycCubit kycCubit;

  const question = KycFinancialQuestion(
    key: 'annual_income',
    type: QuestionType.text,
    title: 'What is your annual income?',
    description: 'Please provide a rough estimate.',
  );

  const loadedState = KycFinancialDataLoadedSuccess(
    allQuestions: [question],
    visibleQuestions: [question],
    responses: {'annual_income': '100000'},
    currentIndex: 0,
    url: 'https://example.com',
  );

  setUp(() {
    financialDataCubit = _MockKycFinancialDataCubit();
    kycCubit = _MockKycCubit();
    when(() => kycCubit.state).thenReturn(const KycInitial());
  });

  Widget buildSubject() => wrapForGolden(
        MultiBlocProvider(
          providers: [
            BlocProvider<KycFinancialDataCubit>.value(value: financialDataCubit),
            BlocProvider<KycCubit>.value(value: kycCubit),
          ],
          child: const KycFinancialDataView(),
        ),
      );

  group('$KycFinancialDataView', () {
    // KycFinancialDataSubmitFailure is a LoadedSuccess subtype: the questions
    // page stays mounted (answers retained) and the View's BlocListener
    // (page:46-58) surfaces the retained-answers submit error as a red SnackBar.
    // Emitting it as a transition from a plain LoadedSuccess fires the listener;
    // pumpAndSettle runs the SnackBar entrance to completion.
    goldenTest(
      'submit failure — questions retained + red SnackBar',
      fileName: 'kyc_financial_data_page_submit_failure',
      constraints: phoneConstraints,
      pumpBeforeTest: (tester) async {
        await tester.pump(); // deliver the whenListen emission to the listener
        await tester.pumpAndSettle(); // run the SnackBar entrance to completion
      },
      builder: () {
        whenListen(
          financialDataCubit,
          Stream<KycFinancialDataState>.value(
            KycFinancialDataSubmitFailure.from(
              loadedState,
              'Übermittlung fehlgeschlagen. Bitte versuchen Sie es erneut.',
            ),
          ),
          initialState: loadedState,
        );
        return buildSubject();
      },
    );

    // KycFinancialDataInitial (and KycFinancialDataSubmitSuccess) fall through to
    // the `(_) => const Scaffold()` fallback branch (page:66): an intentionally
    // blank scaffold shown for the brief pre-load / post-submit frames before
    // checkKyc routes away. Locks that the fallback stays blank.
    goldenTest(
      'initial/submit-success fallback — blank scaffold',
      fileName: 'kyc_financial_data_page_fallback',
      constraints: phoneConstraints,
      builder: () {
        when(() => financialDataCubit.state)
            .thenReturn(const KycFinancialDataInitial());
        return buildSubject();
      },
    );
  });
}
