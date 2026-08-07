import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/dfx/models/kyc/dto/kyc_financial_data_dto.dart';
import 'package:realunit_wallet/screens/kyc/steps/financial_data/cubits/kyc_financial_data_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/financial_data/subpages/kyc_financial_data_questions_page.dart';

import '../../../helper/helper.dart';

class _MockKycFinancialDataCubit extends MockCubit<KycFinancialDataState>
    implements KycFinancialDataCubit {}

// Three fixed questions for the not-last (multi-question) progress golden.
const _threeQuestions = [
  KycFinancialQuestion(
    key: 'income_source',
    type: QuestionType.singleChoice,
    title: 'What is your main source of income?',
    options: [
      KycFinancialOption(key: 'employment', text: 'Employment'),
      KycFinancialOption(key: 'investments', text: 'Investments'),
    ],
  ),
  KycFinancialQuestion(
    key: 'net_worth',
    type: QuestionType.text,
    title: 'What is your estimated net worth?',
  ),
  KycFinancialQuestion(
    key: 'confirm_accuracy',
    type: QuestionType.checkbox,
    title: 'Confirmation',
    options: [
      KycFinancialOption(key: 'accept', text: 'I confirm.'),
    ],
  ),
];

void main() {
  // `kyc_financial_data_questions_page_default` (a text question, empty answer,
  // last-of-1 → disabled "Complete") lives in
  // `kyc_financial_data_questions_golden_test.dart`. This file covers the
  // per-type rendering, the description branches, the answered/enabled button,
  // and the not-last progress + "Next" label of `KycFinancialDataQuestionsPage`
  // (`kyc_financial_data_questions_page.dart`).
  //
  // All questions use fixed keys/strings and fixed response maps so the goldens
  // are deterministic across regens — no clock/random input.
  late _MockKycFinancialDataCubit financialDataCubit;

  setUp(() {
    financialDataCubit = _MockKycFinancialDataCubit();
  });

  Widget buildSubject(KycFinancialDataLoadedSuccess state) {
    when(() => financialDataCubit.state).thenReturn(state);
    return wrapForGolden(
      BlocProvider<KycFinancialDataCubit>.value(
        value: financialDataCubit,
        child: KycFinancialDataQuestionsPage(state),
      ),
    );
  }

  KycFinancialDataLoadedSuccess singleQuestion(
    KycFinancialQuestion question, {
    Map<String, String> responses = const {},
  }) =>
      KycFinancialDataLoadedSuccess(
        allQuestions: [question],
        visibleQuestions: [question],
        responses: responses,
        currentIndex: 0,
        url: 'https://example.com',
      );

  group('$KycFinancialDataQuestionsPage', () {
    // QuestionType.checkbox → CheckboxListTile rendering the option text
    // (kyc_question_checkbox_widget.dart).
    goldenTest(
      'checkbox question — CheckboxListTile',
      fileName: 'kyc_financial_data_questions_page_checkbox',
      constraints: phoneConstraints,
      builder: () => buildSubject(
        singleQuestion(
          const KycFinancialQuestion(
            key: 'confirm_accuracy',
            type: QuestionType.checkbox,
            title: 'Confirmation',
            description: 'Tick to confirm the information provided is accurate.',
            options: [
              KycFinancialOption(
                key: 'accept',
                text: 'I confirm the information provided is accurate.',
              ),
            ],
          ),
        ),
      ),
    );

    // QuestionType.singleChoice → RadioGroup of ListTiles, none selected
    // (kyc_question_single_choice_widget.dart).
    goldenTest(
      'single-choice question — RadioGroup',
      fileName: 'kyc_financial_data_questions_page_single_choice',
      constraints: phoneConstraints,
      builder: () => buildSubject(
        singleQuestion(
          const KycFinancialQuestion(
            key: 'income_source',
            type: QuestionType.singleChoice,
            title: 'What is your main source of income?',
            options: [
              KycFinancialOption(key: 'employment', text: 'Employment'),
              KycFinancialOption(key: 'self_employment', text: 'Self-employment'),
              KycFinancialOption(key: 'investments', text: 'Investments'),
            ],
          ),
        ),
      ),
    );

    // QuestionType.multipleChoice → a list of CheckboxListTiles, none selected
    // (kyc_question_multiple_choice_widget.dart).
    goldenTest(
      'multiple-choice question — CheckboxListTile list',
      fileName: 'kyc_financial_data_questions_page_multiple_choice',
      constraints: phoneConstraints,
      builder: () => buildSubject(
        singleQuestion(
          const KycFinancialQuestion(
            key: 'asset_types',
            type: QuestionType.multipleChoice,
            title: 'Which asset types do you hold?',
            options: [
              KycFinancialOption(key: 'stocks', text: 'Stocks'),
              KycFinancialOption(key: 'bonds', text: 'Bonds'),
              KycFinancialOption(key: 'crypto', text: 'Crypto assets'),
            ],
          ),
        ),
      ),
    );

    // key == 'tnc' → the description renders as a blue, underlined link
    // (kyc_financial_data_questions_page.dart:109-134).
    goldenTest(
      'link description — blue underlined (tnc)',
      fileName: 'kyc_financial_data_questions_page_link_description',
      constraints: phoneConstraints,
      builder: () => buildSubject(
        singleQuestion(
          const KycFinancialQuestion(
            key: 'tnc',
            type: QuestionType.checkbox,
            title: 'Terms and Conditions',
            description: 'I accept the terms and conditions.',
            options: [
              KycFinancialOption(
                key: 'accept',
                text: 'I accept the terms and conditions.',
              ),
            ],
          ),
        ),
      ),
    );

    // description == null → the description block is omitted (page:78-80).
    goldenTest(
      'question without description',
      fileName: 'kyc_financial_data_questions_page_no_description',
      constraints: phoneConstraints,
      builder: () => buildSubject(
        singleQuestion(
          const KycFinancialQuestion(
            key: 'net_worth',
            type: QuestionType.text,
            title: 'What is your estimated net worth?',
          ),
        ),
      ),
    );

    // hasAnswer == true (a non-empty response) → the "Complete" button is
    // enabled (page:89-95); the text field shows the retained answer.
    goldenTest(
      'answer present — enabled button',
      fileName: 'kyc_financial_data_questions_page_answered',
      constraints: phoneConstraints,
      builder: () => buildSubject(
        singleQuestion(
          const KycFinancialQuestion(
            key: 'annual_income',
            type: QuestionType.text,
            title: 'What is your annual income?',
            description: 'Please provide a rough estimate.',
          ),
          responses: const {'annual_income': '120000'},
        ),
      ),
    );

    // currentIndex 0 of 3 visible → isLastQuestion false → button label is
    // "Next" (page:92-94) and the progress reads "Frage 1 von 3" (page:55-60).
    goldenTest(
      'not-last question — Next label + progress',
      fileName: 'kyc_financial_data_questions_page_not_last',
      constraints: phoneConstraints,
      builder: () => buildSubject(
        const KycFinancialDataLoadedSuccess(
          allQuestions: _threeQuestions,
          visibleQuestions: _threeQuestions,
          responses: {},
          currentIndex: 0,
          url: 'https://example.com',
        ),
      ),
    );
  });
}
