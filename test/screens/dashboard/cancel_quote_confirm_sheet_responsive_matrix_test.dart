// Responsive matrix gate for CancelQuoteConfirmSheet.
//
// Proves both sheet CTAs stay fully tappable across the full device ×
// text-scale matrix when presented via showModalBottomSheet(
// isScrollControlled: true). The page matrix only taps the page CTA;
// this file is the catalog entry for the sheet itself.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/screens/dashboard/pending_transaction_detail_page.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';

import '../../helper/helper.dart';

const _openSheetKey = Key('cancel_quote_sheet_matrix.open');

void main() {
  Future<void> pumpAndOpenSheet(WidgetTester tester, MatrixCell cell) async {
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
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  key: _openSheetKey,
                  onPressed: () {
                    showModalBottomSheet<bool>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => CancelQuoteConfirmSheet(
                        strings: S.of(context),
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(_openSheetKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('CancelQuoteConfirmSheet responsive matrix', () {
    for (final cell in kFullResponsiveMatrix) {
      testWidgets('cancelQuote · ${cell.id}', (tester) async {
        await withTargetPlatform(cell.device.platform, () async {
          await expectNoLayoutOverflow(
            tester,
            () => pumpAndOpenSheet(tester, cell),
            reason: 'CancelQuoteConfirmSheet overflow / ${cell.label}',
          );

          expect(
            find.byType(AppFilledButton),
            findsNWidgets(2),
            reason: 'CancelQuoteConfirmSheet / ${cell.label}: expected 2 CTAs',
          );

          await expectFullyTappable(
            tester,
            find.byType(AppFilledButton).first,
            within: find.byType(CancelQuoteConfirmSheet),
            reason: 'CancelQuoteConfirmSheet / ${cell.label}: cancel CTA not tappable',
          );

          await expectNoLayoutOverflow(
            tester,
            () => pumpAndOpenSheet(tester, cell),
            reason: 'CancelQuoteConfirmSheet re-open overflow / ${cell.label}',
          );

          await expectFullyTappable(
            tester,
            find.byType(AppFilledButton).last,
            within: find.byType(CancelQuoteConfirmSheet),
            reason: 'CancelQuoteConfirmSheet / ${cell.label}: confirm CTA not tappable',
          );
        });
      });
    }
  });
}
