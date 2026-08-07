// Responsive matrix gate for OnboardingCompletedPage CTA.
//
// Proves the "Weiter" button stays fully tappable across the full device ×
// text-scale matrix. Regression lock for the iPhone SE + textScale ≥ 1.3 bug
// where the CTA was scrolled below the fold inside the legacy Spacer layout.
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/screens/home/bloc/home_bloc.dart';
import 'package:realunit_wallet/screens/onboarding/onboarding_completed_page.dart';
import 'package:realunit_wallet/styles/themes.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';

import '../../helper/helper.dart';

class _MockHomeBloc extends MockBloc<HomeEvent, HomeState> implements HomeBloc {}

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
  late _MockHomeBloc homeBloc;

  setUp(() {
    homeBloc = _MockHomeBloc();
    when(() => homeBloc.state).thenReturn(const HomeState());
    whenListen(
      homeBloc,
      const Stream<HomeState>.empty(),
      initialState: const HomeState(),
    );
    // expectFullyTappable performs a real tap → onPressed → add(...).
    when(() => homeBloc.add(const CompleteOnboardingEvent())).thenReturn(null);
  });

  Widget buildSubject() => BlocProvider<HomeBloc>.value(
        value: homeBloc,
        child: const OnboardingCompletedPage(),
      );

  group('OnboardingCompletedPage responsive matrix (full device × textScale)', () {
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
            within: find.byType(OnboardingCompletedPage),
            reason: '${cell.label}: CTA not tappable',
          );
        });
      });
    }
  });

  // Focused regression: iPhone SE 375×667 DE + textScale 1.3 — the exact
  // reported failure mode where the CTA dropped below the fold.
  testWidgets(
    'REGRESSION: iPhone SE DE textScale 1.3 — CTA tappable and tap completes onboarding',
    (tester) async {
      final cell = MatrixCell(
        kIosDeviceProfiles.firstWhere((d) => d.id == 'iphone_se_3'),
        1.3,
      );
      await withTargetPlatform(cell.device.platform, () async {
        await _pumpScreen(tester, buildSubject(), cell.mediaQuery);

        await expectFullyTappable(
          tester,
          find.byType(AppFilledButton),
          within: find.byType(OnboardingCompletedPage),
        );
        verify(() => homeBloc.add(const CompleteOnboardingEvent())).called(1);
      });
    },
  );

  testWidgets(
    'REGRESSION: iPhone SE DE textScale 2.0 — CTA still tappable',
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
          within: find.byType(OnboardingCompletedPage),
        );
        verify(() => homeBloc.add(const CompleteOnboardingEvent())).called(1);
      });
    },
  );
}
