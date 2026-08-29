import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/screens/sell/widgets/sell_executed_sheet.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';

import '../../../helper/helper.dart';

void main() {
  group('$SellExecutedSheet', () {
    testWidgets('renders the blue check_circle_rounded success icon', (tester) async {
      // GoRouter context.pop reads from the GoRouter; we don't actually
      // trigger the button so a missing router doesn't matter.
      await tester.pumpApp(const SellExecutedSheet());

      final icon = tester.widget<Icon>(find.byIcon(Icons.check_circle_rounded));
      expect(icon.color, RealUnitColors.realUnitBlue);
      expect(icon.size, 64);
    });

    testWidgets('renders a secondary, narrow close AppFilledButton', (tester) async {
      await tester.pumpApp(const SellExecutedSheet());

      final button = tester.widget<AppFilledButton>(find.byType(AppFilledButton));
      expect(button.variant, FilledButtonVariant.secondary);
      expect(button.fullWidth, isFalse);
    });

    testWidgets('close button has a non-null onPressed callback', (tester) async {
      // Wrap in a minimal GoRouter so context.pop is resolvable.
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const SellExecutedSheet(),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
      ));

      final button = tester.widget<AppFilledButton>(find.byType(AppFilledButton));
      expect(button.onPressed, isNotNull);
    });
  });
}
