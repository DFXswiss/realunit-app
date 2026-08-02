// Responsive matrix gate for KYC status page CTAs.
//
// Proves the three status pages keep their single sticky CTA fully tappable
// across the full device × text-scale matrix (see test/helper/responsive_matrix.dart).
// This is the regression lock for the dead-CTA bug: long DE copy + high
// textScale + Column(Spacer/copy/button/Spacer) with no scroll view overflowed
// the Scaffold body so the button painted outside the hit-testable region.
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/widgets/buttons/app_text_button.dart';
import 'package:realunit_wallet/screens/kyc/steps/personal_data/kyc_personal_data_page.dart';
import 'package:realunit_wallet/screens/kyc/subpages/kyc_unsupported_step_page.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/screens/kyc/cubits/kyc/kyc_cubit.dart';
import 'package:realunit_wallet/screens/kyc/subpages/kyc_completed_page.dart';
import 'package:realunit_wallet/screens/kyc/subpages/kyc_manual_review_page.dart';
import 'package:realunit_wallet/screens/kyc/subpages/kyc_pending_page.dart';
import 'package:realunit_wallet/styles/themes.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';

import '../../../helper/helper.dart';

class _MockKycCubit extends MockCubit<KycState> implements KycCubit {}

/// Longest enum name → longest interpolated DE copy ("…FINANCIALDATA…").
const _longestPendingStep = KycStep.financialData;

const _localizationsDelegates = <LocalizationsDelegate<dynamic>>[
  S.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
];

/// Root marker so completed-page REGRESSION can assert a real `context.pop`.
const _rootMarker = 'KYC_COMPLETED_ROOT';

void main() {
  late _MockKycCubit cubit;

  setUp(() {
    cubit = _MockKycCubit();
    when(() => cubit.state).thenReturn(const KycInitial());
    when(() => cubit.checkKyc()).thenAnswer((_) async {});
  });

  Future<void> pumpPage(
    WidgetTester tester,
    MatrixCell cell,
    Widget page,
  ) async {
    await tester.binding.setSurfaceSize(cell.device.size);
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(
      MediaQuery(
        data: cell.mediaQuery,
        child: MaterialApp(
          theme: realUnitTheme,
          locale: const Locale('de'),
          localizationsDelegates: _localizationsDelegates,
          supportedLocales: S.delegate.supportedLocales,
          home: page,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// Hosts [KycCompletedPage] under a two-route GoRouter so `context.pop` has
  /// somewhere to go back to (mirrors support_email_capture_page_test).
  Future<GoRouter> pumpCompletedPage(
    WidgetTester tester,
    MatrixCell cell,
  ) async {
    await tester.binding.setSurfaceSize(cell.device.size);
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(
            body: Center(child: Text(_rootMarker)),
          ),
        ),
        GoRoute(
          path: '/completed',
          builder: (_, _) => const KycCompletedPage(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MediaQuery(
        data: cell.mediaQuery,
        child: MaterialApp.router(
          theme: realUnitTheme,
          locale: const Locale('de'),
          localizationsDelegates: _localizationsDelegates,
          supportedLocales: S.delegate.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();

    router.push('/completed');
    await tester.pumpAndSettle();

    return router;
  }

  group('KycCompletedPage responsive matrix (full device × textScale)', () {
    for (final cell in kFullResponsiveMatrix) {
      testWidgets(cell.id, (tester) async {
        await withTargetPlatform(cell.device.platform, () async {
          await expectNoLayoutOverflow(
            tester,
            () async {
              await pumpCompletedPage(tester, cell);
            },
            reason: 'overflow on KycCompletedPage / ${cell.label}',
          );

          await expectFullyTappable(
            tester,
            find.byType(AppFilledButton),
            within: find.byType(KycCompletedPage),
            reason: 'KycCompletedPage / ${cell.label}: CTA not tappable',
          );
        });
      });
    }
  });

  group('KycManualReviewPage responsive matrix (full device × textScale)', () {
    for (final cell in kFullResponsiveMatrix) {
      testWidgets(cell.id, (tester) async {
        await withTargetPlatform(cell.device.platform, () async {
          await expectNoLayoutOverflow(
            tester,
            () async {
              await pumpPage(
                tester,
                cell,
                BlocProvider<KycCubit>.value(
                  value: cubit,
                  child: const KycManualReviewPage(),
                ),
              );
            },
            reason: 'overflow on KycManualReviewPage / ${cell.label}',
          );

          await expectFullyTappable(
            tester,
            find.byType(AppFilledButton),
            within: find.byType(KycManualReviewPage),
            reason: 'KycManualReviewPage / ${cell.label}: CTA not tappable',
          );
        });
      });
    }
  });

  // Two live tap targets in one sticky block — the first of its kind in the KYC family — so both are
  // asserted, not just the primary CTA. The DE copy is long enough that the 3.0 text-scale cells are
  // the point of this group.
  group('KycUnsupportedStepPage responsive matrix (full device × textScale)', () {
    for (final cell in kFullResponsiveMatrix) {
      testWidgets(cell.id, (tester) async {
        await withTargetPlatform(cell.device.platform, () async {
          await expectNoLayoutOverflow(
            tester,
            () async {
              await pumpPage(
                tester,
                cell,
                BlocProvider<KycCubit>.value(
                  value: cubit,
                  child: const KycUnsupportedStepPage(),
                ),
              );
            },
            reason: 'overflow on KycUnsupportedStepPage / ${cell.label}',
          );

          await expectFullyTappable(
            tester,
            find.byType(AppFilledButton),
            within: find.byType(KycUnsupportedStepPage),
            reason: 'KycUnsupportedStepPage / ${cell.label}: retry not tappable',
          );

          // The support CTA's reachability is covered by the overflow assertion above — it cannot be
          // tapped here because `pumpPage` hosts the page under `MaterialApp(home:)` with no router,
          // and the CTA navigates. Its tap target and its route are pinned in the page test, which
          // hosts a GoRouter.
          expect(find.byType(AppTextButton), findsOne);
        });
      });
    }
  });

  group('KycPersonalDataPage missing-payload responsive matrix (full device × textScale)', () {
    for (final cell in kFullResponsiveMatrix) {
      testWidgets(cell.id, (tester) async {
        await withTargetPlatform(cell.device.platform, () async {
          await expectNoLayoutOverflow(
            tester,
            () async {
              await pumpPage(
                tester,
                cell,
                BlocProvider<KycCubit>.value(
                  value: cubit,
                  // null payload → the defensive refresh surface
                  child: const KycPersonalDataPage(url: 'https://example.com'),
                ),
              );
            },
            reason: 'overflow on KycPersonalDataPage(missing payload) / ${cell.label}',
          );

          await expectFullyTappable(
            tester,
            find.byType(AppFilledButton),
            within: find.byType(KycPersonalDataPage),
            reason: 'KycPersonalDataPage(missing payload) / ${cell.label}: CTA not tappable',
          );
        });
      });
    }
  });

  group('KycPendingPage responsive matrix (full device × textScale)', () {
    for (final cell in kFullResponsiveMatrix) {
      testWidgets(cell.id, (tester) async {
        await withTargetPlatform(cell.device.platform, () async {
          await expectNoLayoutOverflow(
            tester,
            () async {
              await pumpPage(
                tester,
                cell,
                BlocProvider<KycCubit>.value(
                  value: cubit,
                  child: const KycPendingPage(pendingStep: _longestPendingStep),
                ),
              );
            },
            reason: 'overflow on KycPendingPage / ${cell.label}',
          );

          await expectFullyTappable(
            tester,
            find.byType(AppFilledButton),
            within: find.byType(KycPendingPage),
            reason: 'KycPendingPage / ${cell.label}: CTA not tappable',
          );
        });
      });
    }
  });

  // Focused regressions: pre-fix breakage cells (measured facts).
  // expectFullyTappable already taps; we additionally verify the side effect.

  testWidgets(
    'REGRESSION: iPhone SE + textScale 2.0 completed — tap pops to root',
    (tester) async {
      final cell = MatrixCell(
        kIosDeviceProfiles.firstWhere((d) => d.id == 'iphone_se_3'),
        2.0,
      );
      await withTargetPlatform(cell.device.platform, () async {
        await expectNoLayoutOverflow(tester, () async {
          await pumpCompletedPage(tester, cell);
        });

        expect(find.byType(KycCompletedPage), findsOneWidget);
        expect(find.text(_rootMarker), findsNothing);

        await expectFullyTappable(
          tester,
          find.byType(AppFilledButton),
          within: find.byType(KycCompletedPage),
        );
        await tester.pumpAndSettle();

        expect(find.text(_rootMarker), findsOneWidget);
        expect(find.byType(KycCompletedPage), findsNothing);
      });
    },
  );

  testWidgets(
    'REGRESSION: iPhone SE + textScale 2.0 manual review — tap calls checkKyc',
    (tester) async {
      final cell = MatrixCell(
        kIosDeviceProfiles.firstWhere((d) => d.id == 'iphone_se_3'),
        2.0,
      );
      await withTargetPlatform(cell.device.platform, () async {
        await expectNoLayoutOverflow(tester, () async {
          await pumpPage(
            tester,
            cell,
            BlocProvider<KycCubit>.value(
              value: cubit,
              child: const KycManualReviewPage(),
            ),
          );
        });
        await expectFullyTappable(
          tester,
          find.byType(AppFilledButton),
          within: find.byType(KycManualReviewPage),
        );
        verify(() => cubit.checkKyc()).called(1);
      });
    },
  );

  testWidgets(
    'REGRESSION: iPhone SE + textScale 3.0 pending — tap calls checkKyc',
    (tester) async {
      final cell = MatrixCell(
        kIosDeviceProfiles.firstWhere((d) => d.id == 'iphone_se_3'),
        3.0,
      );
      await withTargetPlatform(cell.device.platform, () async {
        await expectNoLayoutOverflow(tester, () async {
          await pumpPage(
            tester,
            cell,
            BlocProvider<KycCubit>.value(
              value: cubit,
              child: const KycPendingPage(pendingStep: _longestPendingStep),
            ),
          );
        });
        await expectFullyTappable(
          tester,
          find.byType(AppFilledButton),
          within: find.byType(KycPendingPage),
        );
        verify(() => cubit.checkKyc()).called(1);
      });
    },
  );
}
