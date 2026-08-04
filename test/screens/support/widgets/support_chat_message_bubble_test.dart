import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/models/support/support_message.dart';
import 'package:realunit_wallet/screens/support/widgets/support_chat_message_bubble.dart';
import 'package:realunit_wallet/styles/colors.dart';

Widget _host(Widget child) => MaterialApp(
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
      ],
      supportedLocales: S.delegate.supportedLocales,
      home: Scaffold(body: child),
    );

SupportMessage _msg({
  String? author,
  String? body = 'Hello',
  String? fileName,
  DateTime? created,
}) =>
    SupportMessage(
      id: 1,
      author: author,
      message: body,
      fileName: fileName,
      created: created ?? DateTime.utc(2026, 5, 15, 10),
    );

void main() {
  group('$SupportChatMessageBubble', () {
    testWidgets('customer message: blue bubble end-aligned, no support label',
        (tester) async {
      await tester.pumpWidget(_host(
        SupportChatMessageBubble(supportMessage: _msg(author: 'Customer')),
      ));

      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, RealUnitColors.realUnitBlue);

      final row = tester.widget<Row>(find.byType(Row));
      expect(row.mainAxisAlignment, MainAxisAlignment.end);

      expect(find.text('Support'), findsNothing);
    });

    testWidgets('support agent message: grey bubble start-aligned, with label',
        (tester) async {
      await tester.pumpWidget(_host(
        SupportChatMessageBubble(supportMessage: _msg(author: 'Robin')),
      ));

      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, RealUnitColors.neutral100);

      final row = tester.widget<Row>(find.byType(Row));
      expect(row.mainAxisAlignment, MainAxisAlignment.start);

      expect(find.text('Support'), findsOneWidget);
    });

    testWidgets('AutoResponder message: grey bubble start-aligned, with label',
        (tester) async {
      await tester.pumpWidget(_host(
        SupportChatMessageBubble(supportMessage: _msg(author: 'AutoResponder')),
      ));

      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, RealUnitColors.neutral100);

      final row = tester.widget<Row>(find.byType(Row));
      expect(row.mainAxisAlignment, MainAxisAlignment.start);

      expect(find.text('Support'), findsOneWidget);
    });

    testWidgets('renders the message body', (tester) async {
      await tester.pumpWidget(_host(
        SupportChatMessageBubble(
          supportMessage: _msg(author: 'Customer', body: 'Where is my withdrawal?'),
        ),
      ));

      expect(find.text('Where is my withdrawal?'), findsOneWidget);
    });

    testWidgets(
        'null body on support: only label + timestamp remain (no body Text)',
        (tester) async {
      await tester.pumpWidget(_host(
        SupportChatMessageBubble(
          supportMessage: _msg(author: 'Robin', body: null),
        ),
      ));

      // Label "Support" + timestamp = 2 Texts.
      expect(find.byType(Text), findsNWidgets(2));
      expect(find.text('Support'), findsOneWidget);
    });

    testWidgets(
        'fileName-only message: shows attach icon and file name, not empty',
        (tester) async {
      await tester.pumpWidget(_host(
        SupportChatMessageBubble(
          supportMessage: _msg(
            author: 'Customer',
            body: null,
            fileName: 'receipt.png',
          ),
        ),
      ));

      expect(find.text('receipt.png'), findsOneWidget);
      expect(find.byIcon(Icons.attach_file_rounded), findsOneWidget);
      // File name + timestamp — bubble is not empty beyond the time.
      expect(find.byType(Text), findsNWidgets(2));
    });

    testWidgets('no fileName: no attach-file icon', (tester) async {
      await tester.pumpWidget(_host(
        SupportChatMessageBubble(
          supportMessage: _msg(author: 'Customer', body: 'just text'),
        ),
      ));

      expect(find.byIcon(Icons.attach_file_rounded), findsNothing);
      expect(find.text('just text'), findsOneWidget);
    });
  });
}
