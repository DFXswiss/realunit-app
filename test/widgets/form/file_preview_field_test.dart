import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/form/file_preview_field.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(
    body: Padding(
      padding: const EdgeInsets.all(16),
      child: child,
    ),
  ),
);

void main() {
  late Directory tempDir;
  late File imageFile;
  late File corruptFile;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('file_preview_field_');
    imageFile = File('${tempDir.path}${Platform.pathSeparator}shot.png');
    final bytes = await File('assets/icons/realunit_wallet_logo_full.png').readAsBytes();
    await imageFile.writeAsBytes(bytes);

    // Unreadable image: empty .png. (Plain text bytes hang the native codec;
    // empty/truncated PNG headers resolve to an error that errorBuilder handles.)
    corruptFile = File('${tempDir.path}${Platform.pathSeparator}corrupt.png');
    await corruptFile.writeAsBytes(const <int>[]);
  });

  tearDownAll(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('$FilePreviewField', () {
    testWidgets(
      'corrupt image path: shows broken_image fallback without throwing',
      (tester) async {
        await tester.pumpWidget(
          _host(
            FilePreviewField(
              selectedFile: XFile(corruptFile.path),
              onTap: () {},
              onRemove: () {},
              placeholderText: 'pick',
              placeholderIconColor: RealUnitColors.neutral400,
              borderColor: RealUnitColors.neutral200,
              borderRadius: 12,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
        );
        // FileImage load/error runs on the real async timeline; pump alone
        // cannot await that I/O.
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();

        expect(find.byIcon(Icons.broken_image_rounded), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Image.file uses ResizeImage cacheWidth = 48 * devicePixelRatio',
      (tester) async {
        const dpr = 3.0;
        tester.view.devicePixelRatio = dpr;
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          _host(
            FilePreviewField(
              selectedFile: XFile(imageFile.path),
              onTap: () {},
              onRemove: () {},
              placeholderText: 'pick',
              placeholderIconColor: RealUnitColors.neutral400,
              borderColor: RealUnitColors.neutral200,
              borderRadius: 12,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
        );
        await tester.pump();

        final image = tester.widget<Image>(find.byType(Image));
        expect(image.image, isA<ResizeImage>());
        final resize = image.image as ResizeImage;
        expect(resize.width, (48 * dpr).round()); // 144 at dpr 3
        expect(resize.height, isNull);
      },
    );

    testWidgets(
      'onRemove: null — no close icon',
      (tester) async {
        await tester.pumpWidget(
          _host(
            FilePreviewField(
              selectedFile: XFile(imageFile.path),
              onTap: () {},
              onRemove: null,
              placeholderText: 'pick',
              placeholderIconColor: RealUnitColors.neutral400,
              borderColor: RealUnitColors.neutral200,
              borderRadius: 8,
              height: 76,
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.close_rounded), findsNothing);
        expect(find.byIcon(Icons.edit_rounded), findsOneWidget);
        expect(find.byType(Image), findsOneWidget);
      },
    );

    testWidgets(
      'onRemove set + enabled: false — neither onTap nor onRemove fires',
      (tester) async {
        var taps = 0;
        var removes = 0;
        await tester.pumpWidget(
          _host(
            FilePreviewField(
              selectedFile: XFile(imageFile.path),
              onTap: () => taps++,
              onRemove: () => removes++,
              enabled: false,
              placeholderText: 'pick',
              placeholderIconColor: RealUnitColors.neutral400,
              borderColor: RealUnitColors.neutral200,
              borderRadius: 12,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
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
