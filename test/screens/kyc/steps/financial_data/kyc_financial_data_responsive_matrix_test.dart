// Responsive matrix gate for KycFinancialDataQuestionsPage CTA.
//
// Proves the "Weiter"/"Abschließen" button stays fully tappable across the full
// device × text-scale matrix with a realistic long German KYC question.
// Regression lock for the iPhone SE + textScale 2.0 bug where the CTA was
// scrolled below the fold (or clipped even when scrolled) inside the legacy
// Spacer layout.
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/models/kyc/dto/kyc_financial_data_dto.dart';
import 'package:realunit_wallet/screens/kyc/steps/financial_data/cubits/kyc_financial_data_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/financial_data/subpages/kyc_financial_data_questions_page.dart';
import 'package:realunit_wallet/styles/themes.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';

import '../../../../helper/helper.dart';

class _MockKycFinancialDataCubit extends MockCubit<KycFinancialDataState>
    implements KycFinancialDataCubit {}

/// Realistic long German KYC compliance question that stresses the layout the
/// way the production bug report describes.
const _longGermanQuestion = KycFinancialQuestion(
  key: 'source_of_wealth_detail',
  type: QuestionType.text,
  title:
      'Bitte beschreiben Sie detailliert die Herkunft Ihres Vermögens und '
      'die wirtschaftliche Herkunft der Mittel, die Sie über diese Plattform '
      'anlegen oder transferieren möchten.',
  description:
      'Gemäss den geltenden Geldwäschebestimmungen sind wir verpflichtet, die '
      'wirtschaftliche Herkunft Ihrer Mittel nachvollziehen zu können. Nennen '
      'Sie bitte die Art der Einkünfte (z. B. Gehalt, Unternehmensverkauf, '
      'Erbschaft, Kapitalerträge), den ungefähren Zeitraum sowie ggf. '
      'beteiligte Dritte oder Institutionen. Unvollständige Angaben können zu '
      'Rückfragen oder einer Verzögerung der Freigabe führen.',
);

const _loadedState = KycFinancialDataLoadedSuccess(
  currentIndex: 0,
  visibleQuestions: [_longGermanQuestion],
  allQuestions: [_longGermanQuestion],
  responses: {'source_of_wealth_detail': 'answer'},
  url: 'url',
);

Future<void> _pumpScreen(
  WidgetTester tester,
  Widget widget,
  MediaQueryData mediaQuery,
) async {
  await tester.binding.setSurfaceSize(mediaQuery.size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MediaQuery(
      data: mediaQuery,
      child: MaterialApp(
        theme: realUnitTheme,
        locale: const Locale('de'),
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        home: widget,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  late _MockKycFinancialDataCubit cubit;

  setUp(() {
    cubit = _MockKycFinancialDataCubit();
    when(() => cubit.state).thenReturn(_loadedState);
    whenListen(
      cubit,
      const Stream<KycFinancialDataState>.empty(),
      initialState: _loadedState,
    );
    when(() => cubit.submitAndNext()).thenAnswer((_) async {});
    when(() => cubit.answerQuestion(any(), any())).thenReturn(null);
  });

  Widget buildSubject() => BlocProvider<KycFinancialDataCubit>.value(
        value: cubit,
        child: const KycFinancialDataQuestionsPage(_loadedState),
      );

  group(
    'KycFinancialDataQuestionsPage responsive matrix (full device × textScale)',
    () {
      for (final cell in kFullResponsiveMatrix) {
        testWidgets(cell.id, (tester) async {
          await withTargetPlatform(cell.device.platform, () async {
            await expectNoLayoutOverflow(
              tester,
              () async {
                await _pumpScreen(tester, buildSubject(), cell.mediaQuery);
              },
              reason: 'overflow on ${cell.label}',
            );

            await expectFullyTappable(
              tester,
              find.byType(AppFilledButton),
              within: find.byType(KycFinancialDataQuestionsPage),
              reason: '${cell.label}: CTA not tappable',
            );
          });
        });
      }
    },
  );

  // Focused regression: iPhone SE 375×667 DE + textScale 2.0 with a long
  // German question — proven fail pre-fix (CTA clipped even when scrolled).
  testWidgets(
    'REGRESSION: iPhone SE DE textScale 2.0 long question — CTA tappable and tap submits',
    (tester) async {
      final cell = MatrixCell(
        kIosDeviceProfiles.firstWhere((d) => d.id == 'iphone_se_3'),
        2.0,
      );
      await withTargetPlatform(cell.device.platform, () async {
        await expectNoLayoutOverflow(tester, () async {
          await _pumpScreen(tester, buildSubject(), cell.mediaQuery);
        });

        await expectFullyTappable(
          tester,
          find.byType(AppFilledButton),
          within: find.byType(KycFinancialDataQuestionsPage),
        );
        verify(() => cubit.submitAndNext()).called(1);
      });
    },
  );

  // Keyboard: Scaffold.resizeToAvoidBottomInset (default true) shrinks the
  // body; ScrollableActionsLayout receives the reduced bounded height. Prove
  // the CTA stays fully tappable with a simulated open keyboard on the text
  // question field.
  testWidgets(
    'KEYBOARD: iPhone SE textScale 1.3 — CTA tappable with viewInsets keyboard',
    (tester) async {
      final cell = MatrixCell(
        kIosDeviceProfiles.firstWhere((d) => d.id == 'iphone_se_3'),
        1.3,
      );
      final keyboardMediaQuery = cell.mediaQuery.copyWith(
        viewInsets: const EdgeInsets.only(bottom: 336),
      );

      await withTargetPlatform(cell.device.platform, () async {
        await expectNoLayoutOverflow(
          tester,
          () async {
            await _pumpScreen(tester, buildSubject(), cell.mediaQuery);
            await tester.enterText(
              find.byType(TextField),
              'Gehalt aus unselbstständiger Tätigkeit und Kapitalerträge.',
            );
            await tester.pump();
            // Re-pump same tree with keyboard open (viewInsets).
            await _pumpScreen(tester, buildSubject(), keyboardMediaQuery);
            await tester.enterText(
              find.byType(TextField),
              'Gehalt aus unselbstständiger Tätigkeit und Kapitalerträge.',
            );
            await tester.pump();
          },
          reason: 'overflow with keyboard on ${cell.label}',
        );

        await expectFullyTappable(
          tester,
          find.byType(AppFilledButton),
          within: find.byType(KycFinancialDataQuestionsPage),
          reason: '${cell.label} + keyboard: CTA not tappable',
        );
      });
    },
  );
}
