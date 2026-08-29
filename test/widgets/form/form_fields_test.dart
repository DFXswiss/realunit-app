import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/widgets/form/dropdown_field.dart';
import 'package:realunit_wallet/widgets/form/labeled_text_field.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: child)),
    );

void main() {
  group('$LabeledTextField', () {
    testWidgets('omits the label Padding when label is null', (tester) async {
      await tester.pumpWidget(_host(
        const LabeledTextField(hintText: 'hint'),
      ));

      expect(find.byType(TextFormField), findsOneWidget);
      // No Text widgets render when the label is null (the TextFormField's
      // hint is rendered by InputDecorator, not a top-level Text).
      expect(find.text('Hello'), findsNothing);
    });

    testWidgets('renders the label when provided', (tester) async {
      await tester.pumpWidget(_host(
        const LabeledTextField(label: 'Email'),
      ));

      expect(find.text('Email'), findsOneWidget);
    });

    testWidgets('initialValue seeds the form field', (tester) async {
      await tester.pumpWidget(_host(
        const LabeledTextField(initialValue: 'seed'),
      ));

      expect(find.text('seed'), findsOneWidget);
    });

    testWidgets('can disable spell check', (tester) async {
      await tester.pumpWidget(_host(
        const LabeledTextField(
          spellCheckConfiguration: SpellCheckConfiguration.disabled(),
        ),
      ));

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.spellCheckConfiguration?.spellCheckEnabled, isFalse);
    });

    testWidgets('can disable smart dashes and quotes', (tester) async {
      await tester.pumpWidget(_host(
        const LabeledTextField(
          smartDashesType: SmartDashesType.disabled,
          smartQuotesType: SmartQuotesType.disabled,
        ),
      ));

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.smartDashesType, SmartDashesType.disabled);
      expect(field.smartQuotesType, SmartQuotesType.disabled);
    });

    testWidgets('uses TextInputAction.done when requested', (tester) async {
      await tester.pumpWidget(_host(
        const LabeledTextField(textInputAction: TextInputAction.done),
      ));

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.textInputAction, TextInputAction.done);
    });

    testWidgets('defaults autocorrect and suggestions off', (tester) async {
      await tester.pumpWidget(_host(const LabeledTextField()));

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.autocorrect, isFalse);
      expect(field.enableSuggestions, isFalse);
    });

    testWidgets('can autofocus the field', (tester) async {
      await tester.pumpWidget(_host(const LabeledTextField(autofocus: true)));

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.autofocus, isTrue);
    });

    testWidgets('can disable IME personalized learning', (tester) async {
      await tester.pumpWidget(_host(
        const LabeledTextField(enableIMEPersonalizedLearning: false),
      ));

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.enableIMEPersonalizedLearning, isFalse);
    });

    testWidgets('can enable autocorrect and suggestions', (tester) async {
      await tester.pumpWidget(_host(
        const LabeledTextField(
          autocorrect: true,
          enableSuggestions: true,
        ),
      ));

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.autocorrect, isTrue);
      expect(field.enableSuggestions, isTrue);
    });

    testWidgets('passes autofillHints to the TextFormField', (tester) async {
      await tester.pumpWidget(_host(
        const LabeledTextField(
          autofillHints: [AutofillHints.givenName],
        ),
      ));

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.autofillHints, contains(AutofillHints.givenName));
    });

    testWidgets('onChanged fires when the user types', (tester) async {
      String? last;
      await tester.pumpWidget(_host(
        LabeledTextField(onChanged: (v) => last = v),
      ));

      await tester.enterText(find.byType(TextFormField), 'hello');
      expect(last, 'hello');
    });
  });

  group('$DropdownField<String>', () {
    testWidgets('renders all items as menu choices when tapped', (tester) async {
      await tester.pumpWidget(_host(
        DropdownField<String>(
          initialValue: 'a',
          items: const [
            DropdownMenuItem(value: 'a', child: Text('Alpha')),
            DropdownMenuItem(value: 'b', child: Text('Bravo')),
            DropdownMenuItem(value: 'c', child: Text('Charlie')),
          ],
          onChanged: (_) {},
        ),
      ));

      // initialValue 'Alpha' is rendered in the closed dropdown.
      expect(find.text('Alpha'), findsWidgets);

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();

      // Other items become visible in the open menu.
      expect(find.text('Bravo'), findsOneWidget);
      expect(find.text('Charlie'), findsOneWidget);
    });

    testWidgets('renders the label when provided', (tester) async {
      await tester.pumpWidget(_host(
        const DropdownField<String>(
          label: 'Country',
          items: [
            DropdownMenuItem(value: 'CH', child: Text('CH')),
          ],
        ),
      ));

      expect(find.text('Country'), findsOneWidget);
    });

    testWidgets('onChanged fires when the user picks an item', (tester) async {
      String? picked;
      await tester.pumpWidget(_host(
        DropdownField<String>(
          initialValue: 'a',
          items: const [
            DropdownMenuItem(value: 'a', child: Text('A')),
            DropdownMenuItem(value: 'b', child: Text('B')),
          ],
          onChanged: (v) => picked = v,
        ),
      ));

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('B').last);
      await tester.pumpAndSettle();

      expect(picked, 'b');
    });
  });
}
