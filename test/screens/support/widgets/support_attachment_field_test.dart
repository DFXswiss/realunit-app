import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/screens/support/widgets/support_attachment_field.dart';

import '../../../helper/pump_app.dart';

void main() {
  // Real image bytes so Image.file decodes without noise — same pattern as
  // the settings_user_data responsive matrix.
  late Directory tempDir;
  late File imageFile;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('support_attachment_field_');
    imageFile = File('${tempDir.path}${Platform.pathSeparator}shot.png');
    final bytes = await File('assets/icons/realunit_wallet_logo_full.png').readAsBytes();
    await imageFile.writeAsBytes(bytes);
  });

  tearDownAll(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('$SupportAttachmentField', () {
    testWidgets(
      'empty: shows placeholder (not the label) and no close icon',
      (tester) async {
        await tester.pumpApp(
          SupportAttachmentField(
            selectedFile: null,
            onTap: () {},
            onRemove: () {},
          ),
        );
        await tester.pumpAndSettle();

        // Section label once; placeholder is a different string.
        expect(find.text(S.current.supportAttachment), findsOneWidget);
        expect(find.text(S.current.supportChooseAttachment), findsOneWidget);
        expect(find.byIcon(Icons.close_rounded), findsNothing);
        expect(find.byIcon(Icons.add_a_photo_rounded), findsOneWidget);
        expect(find.byType(Image), findsNothing);
      },
    );

    testWidgets(
      'with file: preview, file name, edit and close icons',
      (tester) async {
        final file = XFile(imageFile.path);
        await tester.pumpApp(
          SupportAttachmentField(
            selectedFile: file,
            onTap: () {},
            onRemove: () {},
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text(file.name), findsOneWidget);
        expect(find.byType(Image), findsOneWidget);
        expect(find.byIcon(Icons.edit_rounded), findsOneWidget);
        expect(find.byIcon(Icons.close_rounded), findsOneWidget);
        expect(find.byIcon(Icons.add_a_photo_rounded), findsNothing);
        expect(find.text(S.current.supportChooseAttachment), findsNothing);
      },
    );

    testWidgets(
      'close icon fires onRemove and does not fire onTap',
      (tester) async {
        var removes = 0;
        var taps = 0;
        await tester.pumpApp(
          SupportAttachmentField(
            selectedFile: XFile(imageFile.path),
            onTap: () => taps++,
            onRemove: () => removes++,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.close_rounded));
        await tester.pumpAndSettle();

        expect(removes, 1);
        expect(taps, 0);
      },
    );

    testWidgets(
      'tapping the field (not close) fires onTap',
      (tester) async {
        var taps = 0;
        await tester.pumpApp(
          SupportAttachmentField(
            selectedFile: null,
            onTap: () => taps++,
            onRemove: () {},
          ),
        );
        await tester.pumpAndSettle();

        // Hit the empty-state icon inside the GestureDetector, not the label.
        await tester.tap(find.byIcon(Icons.add_a_photo_rounded));
        await tester.pumpAndSettle();

        expect(taps, 1);
      },
    );

    testWidgets(
      'enabled: false fires neither onTap nor onRemove',
      (tester) async {
        var taps = 0;
        var removes = 0;
        await tester.pumpApp(
          SupportAttachmentField(
            selectedFile: XFile(imageFile.path),
            enabled: false,
            onTap: () => taps++,
            onRemove: () => removes++,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.edit_rounded));
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.close_rounded));
        await tester.pumpAndSettle();

        expect(taps, 0);
        expect(removes, 0);
      },
    );
  });
}
