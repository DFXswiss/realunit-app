import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/screens/home/bloc/home_bloc.dart';
import 'package:realunit_wallet/screens/pay/pay_scan_page.dart';
import 'package:realunit_wallet/setup/routing/router_config.dart';
import 'package:realunit_wallet/setup/routing/routes/app_routes.dart';

import '../../helper/helper.dart';

class _MockHomeBloc extends MockBloc<HomeEvent, HomeState> implements HomeBloc {}

void main() {
  late _MockHomeBloc homeBloc;

  setUpAll(() {
    // PayScanPage embeds a MobileScanner; the stub keeps the headless camera
    // preview deterministic and free of MissingPluginException.
    stubMobileScannerChannel();
  });

  setUp(() {
    homeBloc = _MockHomeBloc();
    when(() => homeBloc.state).thenReturn(const HomeState());
  });

  // Mirrors the production wiring in main.dart: the routed pages read their
  // blocs from above MaterialApp.router, so HomeBloc (used by the initial
  // /home route) is provided here. Navigation then drives the real
  // `routerConfig` to the /pay GoRoute under test.
  Future<void> pumpRouter(WidgetTester tester) async {
    await tester.pumpWidget(
      BlocProvider<HomeBloc>.value(
        value: homeBloc,
        child: MaterialApp.router(
          routerConfig: routerConfig,
          localizationsDelegates: const [
            S.delegate,
            GlobalMaterialLocalizations.delegate,
          ],
          supportedLocales: S.delegate.supportedLocales,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the pay route builds PayScanPage', (tester) async {
    await pumpRouter(tester);

    routerConfig.goNamed(AppRoutes.pay);
    await tester.pumpAndSettle();

    expect(find.byType(PayScanPage), findsOneWidget);
    expect(find.byType(PayScanView), findsOneWidget);

    // Restore the router to its initial location so the global singleton
    // does not leak the /pay location into any later test.
    addTearDown(() => routerConfig.goNamed(AppRoutes.home));
  });

  testWidgets(
    'the pay route passes a String extra through as initialPayload',
    (tester) async {
      await pumpRouter(tester);

      routerConfig.pushNamed(
        AppRoutes.pay,
        extra: 'lightning:LNURL1DP68GURN8GHJ7VF3XGENJVE5UMD',
      );
      // A single pump is not enough for an imperative pushNamed to land in
      // the tree yet, and pumpAndSettle is unsafe here (PayScanView shows an
      // indefinitely-animating CupertinoActivityIndicator once initialPayload
      // is set). Two plain pumps reliably lands the pushed route.
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(
        tester.widget<PayScanPage>(find.byType(PayScanPage)).initialPayload,
        'lightning:LNURL1DP68GURN8GHJ7VF3XGENJVE5UMD',
      );

      addTearDown(() => routerConfig.goNamed(AppRoutes.home));
    },
  );

  testWidgets(
    'the pay route guards a non-String extra to null (never an unchecked cast)',
    (tester) async {
      await pumpRouter(tester);

      routerConfig.pushNamed(AppRoutes.pay, extra: 42);
      // Same reasoning as the test above: two plain pumps, no pumpAndSettle.
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(
        tester.widget<PayScanPage>(find.byType(PayScanPage)).initialPayload,
        isNull,
      );

      addTearDown(() => routerConfig.goNamed(AppRoutes.home));
    },
  );
}
