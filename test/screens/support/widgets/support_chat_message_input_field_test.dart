import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:realunit_wallet/screens/support/widgets/support_chat_message_input_field.dart';

import '../../../helper/helper.dart';

Widget _host(Widget child) => Scaffold(body: child);

void main() {
  late TextEditingController controller;
  late Directory tempDir;

  setUp(() async {
    controller = TextEditingController();
    tempDir = await Directory.systemTemp.createTemp('chat_input_');
  });

  tearDown(() async {
    controller.dispose();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  XFile writeTempFile(String name) {
    final file = File('${tempDir.path}/$name')..writeAsBytesSync([1]);
    return XFile(file.path);
  }

  group('$SupportChatMessageInputField', () {
    testWidgets('closed ticket: shows the disabled banner, no TextField, no IconButton',
        (tester) async {
      await tester.pumpApp(_host(
        SupportChatMessageInputField(
          controller: controller,
          isSending: false,
          isTicketOpen: false,
          onSend: () {},
          onAttach: () {},
          onRemoveAttachment: () {},
        ),
      ));

      expect(find.byType(TextField), findsNothing);
      expect(find.byType(IconButton), findsNothing);
      // Banner is the only Text widget in the tree.
      expect(find.byType(Text), findsOneWidget);
    });

    testWidgets('open + idle: TextField enabled + send and attach IconButtons active',
        (tester) async {
      var sends = 0;
      var attaches = 0;
      await tester.pumpApp(_host(
        SupportChatMessageInputField(
          controller: controller,
          isSending: false,
          isTicketOpen: true,
          onSend: () => sends++,
          onAttach: () => attaches++,
          onRemoveAttachment: () {},
        ),
      ));

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.enabled, isTrue);

      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
      expect(find.byIcon(Icons.attach_file_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();
      expect(sends, 1);

      await tester.tap(find.byIcon(Icons.attach_file_rounded));
      await tester.pump();
      expect(attaches, 1);
    });

    testWidgets('attach button is present, fires onAttach, and is disabled while sending',
        (tester) async {
      var attaches = 0;
      await tester.pumpApp(_host(
        SupportChatMessageInputField(
          controller: controller,
          isSending: false,
          isTicketOpen: true,
          onSend: () {},
          onAttach: () => attaches++,
          onRemoveAttachment: () {},
        ),
      ));

      final attachIdle = find.byIcon(Icons.attach_file_rounded);
      expect(attachIdle, findsOneWidget);
      await tester.tap(attachIdle);
      await tester.pump();
      expect(attaches, 1);

      await tester.pumpApp(_host(
        SupportChatMessageInputField(
          controller: controller,
          isSending: true,
          isTicketOpen: true,
          onSend: () {},
          onAttach: () => attaches++,
          onRemoveAttachment: () {},
        ),
      ));

      final attachBtn = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.attach_file_rounded),
      );
      expect(attachBtn.onPressed, isNull);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.attach_file_rounded));
      await tester.pump();
      expect(attaches, 1); // no second fire while disabled
    });

    testWidgets('open + sending: TextField disabled + send and attach inactive',
        (tester) async {
      var sends = 0;
      var attaches = 0;
      await tester.pumpApp(_host(
        SupportChatMessageInputField(
          controller: controller,
          isSending: true,
          isTicketOpen: true,
          onSend: () => sends++,
          onAttach: () => attaches++,
          onRemoveAttachment: () {},
        ),
      ));

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.enabled, isFalse);

      // The send icon is replaced by a CupertinoActivityIndicator.
      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      expect(find.byIcon(Icons.send_rounded), findsNothing);
      expect(find.byIcon(Icons.attach_file_rounded), findsOneWidget);

      for (final btn in tester.widgetList<IconButton>(find.byType(IconButton))) {
        expect(btn.onPressed, isNull);
      }

      await tester.tap(find.byType(IconButton).first);
      await tester.pump();
      expect(sends, 0);
      expect(attaches, 0);
    });

    testWidgets('shows attachment preview and remove callback', (tester) async {
      var removes = 0;
      final file = writeTempFile('preview.jpg');
      await tester.pumpApp(_host(
        SupportChatMessageInputField(
          controller: controller,
          isSending: false,
          isTicketOpen: true,
          attachment: file,
          onSend: () {},
          onAttach: () {},
          onRemoveAttachment: () => removes++,
        ),
      ));

      expect(find.text('preview.jpg'), findsOneWidget);
      // Preview row shows attach icon + the attach button → two attach icons.
      expect(find.byIcon(Icons.attach_file_rounded), findsNWidgets(2));
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();
      expect(removes, 1);
    });
  });
}
