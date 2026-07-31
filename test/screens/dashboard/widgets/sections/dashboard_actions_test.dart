import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/screens/dashboard/widgets/sections/dashboard_actions.dart';
import 'package:realunit_wallet/setup/routing/routes/app_routes.dart';
import 'package:realunit_wallet/widgets/action_button.dart';

void main() {
  late List<String> pushedRoutes;

  setUp(() {
    pushedRoutes = <String>[];
  });

  // Routes the four action buttons can push. Each target records the pushed
  // route name so the `onPressed` closures are both executed and asserted,
  // instead of only painted.
  GoRouter buildRouter() {
    GoRoute target(String name, String path) => GoRoute(
      name: name,
      path: path,
      builder: (_, _) {
        pushedRoutes.add(name);
        return Scaffold(body: Text('ROUTE:$name'));
      },
    );

    return GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: DashboardActions()),
        ),
        target(AppRoutes.buy, '/buy'),
        target(AppRoutes.sell, '/sell'),
        target(AppRoutes.pay, '/pay'),
        target(AppRoutes.send, '/send'),
      ],
    );
  }

  Future<void> pumpActions(WidgetTester tester) async {
    final router = buildRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder actionButtonByLabel(String label) => find.byWidgetPredicate(
    (w) => w is ActionButton && w.label == label,
  );

  group('$DashboardActions', () {
    testWidgets('renders the buy, sell, pay and send action buttons', (tester) async {
      await pumpActions(tester);

      expect(actionButtonByLabel(S.current.buy), findsOneWidget);
      expect(actionButtonByLabel(S.current.sell), findsOneWidget);
      expect(actionButtonByLabel(S.current.pay), findsOneWidget);
      expect(actionButtonByLabel(S.current.send), findsOneWidget);
      // Each button is laid out inside an Expanded so the row divides the
      // available width into four equal slots.
      expect(find.byType(Expanded), findsNWidgets(4));
    });

    testWidgets('renders the expected icons for each action', (tester) async {
      await pumpActions(tester);

      expect(find.byIcon(Icons.add_circle_rounded), findsOneWidget);
      expect(find.byIcon(Icons.do_not_disturb_on_rounded), findsOneWidget);
      expect(find.byIcon(Icons.qr_code_scanner_rounded), findsOneWidget);
      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
    });

    testWidgets('buy button pushes the buy route', (tester) async {
      await pumpActions(tester);

      await tester.tap(actionButtonByLabel(S.current.buy));
      await tester.pumpAndSettle();

      expect(pushedRoutes, [AppRoutes.buy]);
    });

    testWidgets('sell button pushes the sell route', (tester) async {
      await pumpActions(tester);

      await tester.tap(actionButtonByLabel(S.current.sell));
      await tester.pumpAndSettle();

      expect(pushedRoutes, [AppRoutes.sell]);
    });

    testWidgets('pay button pushes the pay route', (tester) async {
      await pumpActions(tester);

      await tester.tap(actionButtonByLabel(S.current.pay));
      await tester.pumpAndSettle();

      expect(pushedRoutes, [AppRoutes.pay]);
    });

    testWidgets('send button pushes the send route', (tester) async {
      await pumpActions(tester);

      await tester.tap(actionButtonByLabel(S.current.send));
      await tester.pumpAndSettle();

      expect(pushedRoutes, [AppRoutes.send]);
    });
  });
}
