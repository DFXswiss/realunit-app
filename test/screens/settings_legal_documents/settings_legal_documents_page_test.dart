import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/config/legal_documents_config.dart';
import 'package:realunit_wallet/screens/settings_legal_documents/settings_legal_documents_page.dart';
import 'package:realunit_wallet/setup/routing/routes/legal_routes.dart';
import 'package:realunit_wallet/widgets/outlined_tile.dart';

import '../../helper/pump_app.dart';

void main() {
  group('$SettingsLegalDocumentsPage', () {
    testWidgets('renders initially correctly', (tester) async {
      await tester.pumpApp(
        const SettingsLegalDocumentsPage(),
      );

      expect(find.byType(SingleChildScrollView), findsOne);
      // terms of use (1), legal documents, aktionariat & dfx (2),
      // referral TB (1) — last so the handbook golden stays the top of the list
      expect(
        find.byType(OutlinedTile),
        findsNWidgets(LegalDocumentsConfig.allDocuments.length + 1 + 2 + 1),
      );
    });

    testWidgets(
      'referral TB tile opens the read-only Teilnahmebedingungen',
      (tester) async {
        final router = GoRouter(
          initialLocation: '/',
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const SettingsLegalDocumentsPage(),
            ),
            GoRoute(
              name: LegalRoutes.referralTerms,
              path: '/referralTerms',
              builder: (_, _) => const Text('tb'),
            ),
          ],
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(
          MaterialApp.router(
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
        );
        await tester.pump();
        await tester.scrollUntilVisible(
          find.byKey(const Key('settings-referral-terms')),
          300,
        );
        await tester.tap(find.byKey(const Key('settings-referral-terms')));
        await tester.pumpAndSettle();
        expect(find.text('tb'), findsOneWidget);
      },
    );
  });
}
