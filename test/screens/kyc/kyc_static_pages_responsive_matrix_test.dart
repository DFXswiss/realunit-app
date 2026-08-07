// Responsive matrix gate for CTA-less KYC static pages.
//
// Proves KycFailurePage and KycSignatureUnsupportedPage keep their message
// fully reachable (scrollable + tappable geometry) across the full device ×
// text-scale matrix. Regression lock for bare Column + Spacer() with no scroll
// view, which overflowed/clipped long DE copy at high accessibility text scale.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/screens/kyc/steps/signature_unsupported/kyc_signature_unsupported_page.dart';
import 'package:realunit_wallet/screens/kyc/subpages/kyc_failure_page.dart';
import 'package:realunit_wallet/styles/themes.dart';

import '../../helper/helper.dart';

/// Long DE failure detail interpolated into the already-long
/// `kycFailureDescription` template — long enough to force scrolling on small
/// phones at high text scale.
const _longFailureMessage =
    'Die Verbindung zum Server wurde unerwartet unterbrochen, während Ihre '
    'Dokumente zur Identitätsprüfung hochgeladen wurden. Möglicherweise liegt '
    'ein vorübergehendes Problem bei unserem Partner für die '
    'Identitätsüberprüfung vor, oder Ihre Internetverbindung war instabil.';

const _localizationsDelegates = <LocalizationsDelegate<dynamic>>[
  S.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
];

void main() {
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

  group('KycFailurePage responsive matrix (full device × textScale)', () {
    for (final cell in kFullResponsiveMatrix) {
      testWidgets(cell.id, (tester) async {
        await withTargetPlatform(cell.device.platform, () async {
          await expectNoLayoutOverflow(
            tester,
            () async {
              await pumpPage(
                tester,
                cell,
                const KycFailurePage(message: _longFailureMessage),
              );
            },
            reason: 'overflow on KycFailurePage / ${cell.label}',
          );

          final messageFinder = find.textContaining(_longFailureMessage);
          expect(messageFinder, findsOneWidget);
          await tester.ensureVisible(messageFinder);

          final viewportRect = Offset.zero & cell.device.size;
          final messageRect = tester.getRect(messageFinder);
          expect(
            messageRect.overlaps(viewportRect),
            isTrue,
            reason:
                'KycFailurePage / ${cell.label}: message rect $messageRect '
                'does not intersect viewport $viewportRect',
          );
        });
      });
    }
  });

  group('KycSignatureUnsupportedPage responsive matrix (full device × textScale)', () {
    for (final cell in kFullResponsiveMatrix) {
      testWidgets(cell.id, (tester) async {
        await withTargetPlatform(cell.device.platform, () async {
          await expectNoLayoutOverflow(
            tester,
            () async {
              await pumpPage(
                tester,
                cell,
                const KycSignatureUnsupportedPage(),
              );
            },
            reason: 'overflow on KycSignatureUnsupportedPage / ${cell.label}',
          );

          final messageFinder = find.text(S.current.kycSignatureUnsupportedDescription);
          expect(messageFinder, findsOneWidget);
          await tester.ensureVisible(messageFinder);

          final viewportRect = Offset.zero & cell.device.size;
          final messageRect = tester.getRect(messageFinder);
          expect(
            messageRect.overlaps(viewportRect),
            isTrue,
            reason:
                'KycSignatureUnsupportedPage / ${cell.label}: message rect $messageRect '
                'does not intersect viewport $viewportRect',
          );
        });
      });
    }
  });
}
