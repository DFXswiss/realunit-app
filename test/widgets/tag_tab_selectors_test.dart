import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/widgets/tab_selector.dart';
import 'package:realunit_wallet/widgets/tag_selection.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(
        body: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    );

void main() {
  group('$TagSelection<String>', () {
    testWidgets('renders one ChoiceChip per item with the right label',
        (tester) async {
      await tester.pumpWidget(_host(
        TagSelection<String>(
          items: const [
            ('a', 'Alpha', null),
            ('b', 'Bravo', null),
            ('c', 'Charlie', null),
          ],
          selected: 'a',
          onSelected: (_) {},
        ),
      ));

      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Bravo'), findsOneWidget);
      expect(find.text('Charlie'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNWidgets(3));
    });

    testWidgets('marks exactly the chip matching `selected` as selected',
        (tester) async {
      await tester.pumpWidget(_host(
        TagSelection<String>(
          items: const [
            ('a', 'Alpha', null),
            ('b', 'Bravo', null),
          ],
          selected: 'b',
          onSelected: (_) {},
        ),
      ));

      final chips = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip)).toList();
      expect(chips, hasLength(2));
      expect(chips[0].selected, isFalse); // Alpha
      expect(chips[1].selected, isTrue); // Bravo
    });

    testWidgets('tapping a chip fires onSelected with the chip\'s value',
        (tester) async {
      String? picked;
      await tester.pumpWidget(_host(
        TagSelection<String>(
          items: const [
            ('a', 'Alpha', null),
            ('b', 'Bravo', null),
          ],
          selected: 'a',
          onSelected: (v) => picked = v,
        ),
      ));

      await tester.tap(find.text('Bravo'));
      await tester.pump();

      expect(picked, 'b');
    });

    testWidgets('renders the icon variant when the tuple supplies an IconData',
        (tester) async {
      await tester.pumpWidget(_host(
        TagSelection<String>(
          items: const [
            ('a', 'With icon', Icons.star),
          ],
          selected: 'a',
          onSelected: (_) {},
        ),
      ));

      expect(find.byIcon(Icons.star), findsOneWidget);
    });

    testWidgets('null onSelected disables every ChoiceChip and ignores taps',
        (tester) async {
      String? picked;
      await tester.pumpWidget(_host(
        const TagSelection<String>(
          items: [
            ('a', 'Alpha', null),
            ('b', 'Bravo', null),
          ],
          selected: 'a',
          onSelected: null,
        ),
      ));

      final chips = tester.widgetList<ChoiceChip>(find.byType(ChoiceChip)).toList();
      expect(chips, hasLength(2));
      for (final chip in chips) {
        expect(chip.onSelected, isNull);
      }

      await tester.tap(find.text('Bravo'));
      await tester.pump();
      expect(picked, isNull);
    });
  });

  group('$TabSelector<String>', () {
    Widget buildSelector({
      required String selected,
      required List<String> tabs,
      ValueChanged<String>? onTabSelected,
    }) =>
        TabSelector<String>(
          tabs: tabs,
          selectedTab: selected,
          onTabSelected: onTabSelected ?? (_) {},
          labelBuilder: (_, item, isSelected) => Text(
            item,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        );

    testWidgets('renders one labelBuilder result per tab', (tester) async {
      await tester.pumpWidget(_host(buildSelector(
        selected: 'a',
        tabs: ['a', 'b', 'c'],
      )));

      expect(find.text('a'), findsOneWidget);
      expect(find.text('b'), findsOneWidget);
      expect(find.text('c'), findsOneWidget);
    });

    testWidgets('selected tab\'s label is bold (via labelBuilder)', (tester) async {
      await tester.pumpWidget(_host(buildSelector(
        selected: 'b',
        tabs: ['a', 'b', 'c'],
      )));

      // 3 tabs → 3 Text widgets with our test labelBuilder.
      final selectedText = tester.widgetList<Text>(find.text('b')).first;
      expect(selectedText.style!.fontWeight, FontWeight.bold);
      final unselectedA = tester.widgetList<Text>(find.text('a')).first;
      expect(unselectedA.style!.fontWeight, FontWeight.normal);
    });

    testWidgets('alignment animates between -1 (first) and +1 (last) as tabs change',
        (tester) async {
      // First tab → alignmentX should be -1.0.
      await tester.pumpWidget(_host(buildSelector(
        selected: 'a',
        tabs: ['a', 'b', 'c'],
      )));
      await tester.pumpAndSettle();

      var animatedAlign = tester.widget<AnimatedAlign>(find.byType(AnimatedAlign));
      expect((animatedAlign.alignment as Alignment).x, -1.0);

      // Last tab → +1.0.
      await tester.pumpWidget(_host(buildSelector(
        selected: 'c',
        tabs: ['a', 'b', 'c'],
      )));
      await tester.pumpAndSettle();

      animatedAlign = tester.widget<AnimatedAlign>(find.byType(AnimatedAlign));
      expect((animatedAlign.alignment as Alignment).x, 1.0);
    });

    testWidgets('single-tab selector centers the indicator (alignmentX = 0)',
        (tester) async {
      await tester.pumpWidget(_host(buildSelector(
        selected: 'only',
        tabs: ['only'],
      )));
      await tester.pumpAndSettle();

      final animatedAlign = tester.widget<AnimatedAlign>(find.byType(AnimatedAlign));
      // Single-tab path: tabCount<=1 → alignmentX = 0.0.
      expect((animatedAlign.alignment as Alignment).x, 0.0);
    });
  });
}
