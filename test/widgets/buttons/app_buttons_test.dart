import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';
import 'package:realunit_wallet/widgets/buttons/app_text_button.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('$AppTextButton', () {
    testWidgets('renders the label and triggers onPressed', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(
        AppTextButton(label: 'Cancel', onPressed: () => taps++),
      ));

      expect(find.text('Cancel'), findsOneWidget);
      await tester.tap(find.byType(AppTextButton));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('icon-less variant uses plain TextButton (no Icon in tree)',
        (tester) async {
      await tester.pumpWidget(_host(const AppTextButton(label: 'X')));

      expect(find.byType(TextButton), findsOneWidget);
      expect(find.byType(Icon), findsNothing);
    });

    testWidgets('icon variant renders an Icon next to the label', (tester) async {
      await tester.pumpWidget(_host(
        const AppTextButton(label: 'Add', icon: Icons.add),
      ));

      expect(find.byIcon(Icons.add), findsOneWidget);
      expect(find.text('Add'), findsOneWidget);
    });

    testWidgets('fullWidth: true wraps the button in a SizedBox(width=∞)',
        (tester) async {
      await tester.pumpWidget(_host(
        const AppTextButton(label: 'Wide'),
      ));

      // Find a SizedBox ancestor that wraps the button with infinite width.
      final sizedBoxes = tester.widgetList<SizedBox>(find.byType(SizedBox)).toList();
      final hasInfiniteWidth = sizedBoxes.any((s) => s.width == double.infinity);
      expect(hasInfiniteWidth, isTrue);
    });

    testWidgets('fullWidth: false does NOT wrap in an infinite-width SizedBox',
        (tester) async {
      await tester.pumpWidget(_host(
        const AppTextButton(label: 'Narrow', fullWidth: false),
      ));

      final sizedBoxes = tester.widgetList<SizedBox>(find.byType(SizedBox)).toList();
      final hasInfiniteWidth = sizedBoxes.any((s) => s.width == double.infinity);
      expect(hasInfiniteWidth, isFalse);
    });
  });

  group('$AppFilledButton (FilledButtonState)', () {
    testWidgets('idle: tap fires onPressed', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(
        AppFilledButton(label: 'Go', onPressed: () => taps++),
      ));

      await tester.tap(find.byType(AppFilledButton));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('idle: autofocus defaults to false on the FilledButton',
        (tester) async {
      await tester.pumpWidget(_host(
        AppFilledButton(label: 'Go', onPressed: () {}),
      ));

      expect(tester.widget<FilledButton>(find.byType(FilledButton)).autofocus, isFalse);
    });

    testWidgets('idle: autofocus is forwarded to FilledButton and FilledButton.icon',
        (tester) async {
      await tester.pumpWidget(_host(
        AppFilledButton(label: 'Retry', autofocus: true, onPressed: () {}),
      ));
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).autofocus, isTrue);

      await tester.pumpWidget(_host(
        AppFilledButton(
          label: 'Retry',
          icon: Icons.refresh,
          autofocus: true,
          onPressed: () {},
        ),
      ));
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).autofocus, isTrue);
    });

    testWidgets('loading: shows CupertinoActivityIndicator, disables onPressed',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(
        AppFilledButton(
          label: 'Submitting',
          state: FilledButtonState.loading,
          onPressed: () => taps++,
        ),
      ));

      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      await tester.tap(find.byType(AppFilledButton));
      await tester.pump();
      // _loadingButton hardcodes onPressed: null, so the callback is ignored.
      expect(taps, 0);
    });

    testWidgets('success: honors onPressed when provided', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(
        AppFilledButton(
          label: 'Done',
          state: FilledButtonState.success,
          onPressed: () => taps++,
        ),
      ));

      await tester.tap(find.byType(AppFilledButton));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('error: honors onPressed when provided', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(
        AppFilledButton(
          label: 'Retry?',
          state: FilledButtonState.error,
          onPressed: () => taps++,
        ),
      ));

      await tester.tap(find.byType(AppFilledButton));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('icon variant renders the Icon in idle state', (tester) async {
      await tester.pumpWidget(_host(
        const AppFilledButton(label: 'Add', icon: Icons.add),
      ));

      expect(find.byIcon(Icons.add), findsOneWidget);
    });
  });
}
