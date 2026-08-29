import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:realunit_wallet/screens/referral/open_referral_terms.dart';
import 'package:realunit_wallet/setup/routing/routes/legal_routes.dart';

void main() {
  testWidgets('pushes the read-only Teilnahmebedingungen route', (tester) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Builder(
            builder: (context) => TextButton(
              onPressed: () => openReferralTerms(context),
              child: const Text('go'),
            ),
          ),
        ),
        GoRoute(
          name: LegalRoutes.referralTerms,
          path: '/referralTerms',
          builder: (_, _) => const Text('tb'),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.text('tb'), findsOneWidget);
  });

  testWidgets('is a no-op without a GoRouter', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Text('stay')),
    );
    final context = tester.element(find.text('stay'));
    openReferralTerms(context);
    await tester.pump();
    expect(find.text('stay'), findsOneWidget);
  });
}
