// Responsive matrix gate for ForgotPin + EnableBiometric bottom sheets.
//
// Proves CTAs stay fully tappable across the full device × text-scale matrix
// (see test/helper/responsive_matrix.dart) when presented via a real
// showModalBottomSheet(isScrollControlled: true). Regression lock for the
// pre-fix Column(mainAxisSize: .min) host that pushed CTAs outside the
// hit-test region at large accessibility text scales.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/screens/pin/widgets/enable_biometric_bottom_sheet.dart';
import 'package:realunit_wallet/screens/pin/widgets/forgot_pin_bottom_sheet.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';

import '../../helper/helper.dart';

const _openSheetKey = Key('pin_sheets_matrix.open');

void main() {
  Future<void> pumpAndOpenSheet(
    WidgetTester tester,
    MatrixCell cell, {
    required Widget sheet,
    required bool useGoRouter,
  }) async {
    await tester.binding.setSurfaceSize(cell.mediaQuery.size);
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    Widget openButton(BuildContext context) => Center(
      child: ElevatedButton(
        key: _openSheetKey,
        onPressed: () {
          showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            builder: (_) => sheet,
          );
        },
        child: const Text('open'),
      ),
    );

    if (useGoRouter) {
      // ForgotPinBottomSheet calls context.pop via go_router; a plain
      // MaterialApp Navigator is not enough for that extension to resolve.
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(
              body: openButton(context),
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        MediaQuery(
          data: cell.mediaQuery,
          child: MaterialApp.router(
            locale: const Locale('de'),
            localizationsDelegates: const [
              S.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: S.delegate.supportedLocales,
            routerConfig: router,
          ),
        ),
      );
    } else {
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
              body: Builder(builder: openButton),
            ),
          ),
        ),
      );
    }

    await tester.pump();
    await tester.tap(find.byKey(_openSheetKey));
    // Modal bottom sheet enter transition is ~250ms; budget 300ms to settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('ForgotPinBottomSheet responsive matrix', () {
    for (final cell in kFullResponsiveMatrix) {
      testWidgets('forgotPin · ${cell.id}', (tester) async {
        await withTargetPlatform(cell.device.platform, () async {
          await expectNoLayoutOverflow(
            tester,
            () async {
              await pumpAndOpenSheet(
                tester,
                cell,
                sheet: const ForgotPinBottomSheet(),
                useGoRouter: true,
              );
            },
            reason: 'ForgotPinBottomSheet overflow / ${cell.label}',
          );

          expect(
            find.byType(AppFilledButton),
            findsNWidgets(2),
            reason: 'ForgotPinBottomSheet / ${cell.label}: expected 2 CTAs',
          );

          await expectFullyTappable(
            tester,
            find.byType(AppFilledButton).first,
            within: find.byType(ForgotPinBottomSheet),
            reason:
                'ForgotPinBottomSheet / ${cell.label}: Close CTA not tappable',
          );

          // expectFullyTappable taps for real and dismisses the sheet — reopen
          // fresh before asserting the second button.
          await expectNoLayoutOverflow(
            tester,
            () async {
              await pumpAndOpenSheet(
                tester,
                cell,
                sheet: const ForgotPinBottomSheet(),
                useGoRouter: true,
              );
            },
            reason:
                'ForgotPinBottomSheet re-open overflow / ${cell.label}',
          );

          await expectFullyTappable(
            tester,
            find.byType(AppFilledButton).last,
            within: find.byType(ForgotPinBottomSheet),
            reason:
                'ForgotPinBottomSheet / ${cell.label}: Reset CTA not tappable',
          );
        });
      });
    }
  });

  group('EnableBiometricBottomSheet responsive matrix', () {
    for (final cell in kFullResponsiveMatrix) {
      testWidgets('enableBiometric · ${cell.id}', (tester) async {
        await withTargetPlatform(cell.device.platform, () async {
          await expectNoLayoutOverflow(
            tester,
            () async {
              await pumpAndOpenSheet(
                tester,
                cell,
                sheet: const EnableBiometricBottomSheet(),
                useGoRouter: false,
              );
            },
            reason: 'EnableBiometricBottomSheet overflow / ${cell.label}',
          );

          await expectFullyTappable(
            tester,
            find.byType(AppFilledButton),
            within: find.byType(EnableBiometricBottomSheet),
            reason:
                'EnableBiometricBottomSheet / ${cell.label}: '
                'Enable CTA not tappable',
          );
        });
      });
    }
  });
}
