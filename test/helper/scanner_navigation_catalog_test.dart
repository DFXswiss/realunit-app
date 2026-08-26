import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'scanner_navigation_catalog.dart';

/// Widget definition file — constructs [QrScannerView] for others; not a
/// navigation consumer.
const _qrScannerViewDefinitionPath = 'lib/widgets/scanner/qr_scanner_view.dart';

void main() {
  test('every catalogued production and regression path exists on disk', () {
    for (final surface in kScannerNavigationCatalog) {
      expect(
        File(surface.productionPath).existsSync(),
        isTrue,
        reason:
            'Surface "${surface.id}" lists production file '
            '${surface.productionPath} but the file is missing',
      );
      expect(
        File(surface.regressionTestPath).existsSync(),
        isTrue,
        reason:
            'Surface "${surface.id}" lists regression test '
            '${surface.regressionTestPath} but the file is missing',
      );
    }
  });

  test(
    'every catalogued production file constructs QrScannerView and uses pushThenRearm',
    () {
      for (final surface in kScannerNavigationCatalog) {
        final contents = File(surface.productionPath).readAsStringSync();
        expect(
          contents.contains('QrScannerView('),
          isTrue,
          reason:
              'Surface "${surface.id}" (${surface.productionPath}) no longer '
              'constructs QrScannerView — remove it from the catalog or restore '
              'the scanner',
        );
        expect(
          contents.contains('pushThenRearm'),
          isTrue,
          reason:
              'Surface "${surface.id}" (${surface.productionPath}) constructs '
              'QrScannerView but no longer references pushThenRearm — the '
              'scanner-navigation contract regressed',
        );
      }
    },
  );

  test(
    'every catalogued regression test fires BarcodeCapture and asserts a single destination',
    () {
      for (final surface in kScannerNavigationCatalog) {
        final contents = File(surface.regressionTestPath).readAsStringSync();
        expect(
          contents.contains('BarcodeCapture'),
          isTrue,
          reason:
              'Surface "${surface.id}" regression test '
              '(${surface.regressionTestPath}) must fire BarcodeCapture',
        );
        expect(
          contents.contains(surface.destinationWidgetName),
          isTrue,
          reason:
              'Surface "${surface.id}" regression test '
              '(${surface.regressionTestPath}) must assert '
              '${surface.destinationWidgetName}',
        );
        expect(
          contents.contains('findsOne'),
          isTrue,
          reason:
              'Surface "${surface.id}" regression test '
              '(${surface.regressionTestPath}) must assert findsOne on the '
              'destination (double-push gate)',
        );
      }
    },
  );

  test('catalog is non-empty (scanner-navigation gate is active)', () {
    expect(kScannerNavigationCatalog, isNotEmpty);
  });

  test(
    'every QrScannerView( under lib/ is catalogued (discovery)',
    () {
      final catalogued = {
        for (final surface in kScannerNavigationCatalog) surface.productionPath,
      };
      final unlisted = <String>[];

      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) {
          continue;
        }
        // Normalize to forward-slash repo-relative path (macOS/Linux cwd =
        // package root under `flutter test`).
        final path = entity.path.replaceAll(r'\', '/');
        if (path == _qrScannerViewDefinitionPath) {
          continue;
        }
        final contents = entity.readAsStringSync();
        if (!contents.contains('QrScannerView(')) {
          continue;
        }
        if (!catalogued.contains(path)) {
          unlisted.add(path);
        }
      }

      expect(
        unlisted,
        isEmpty,
        reason:
            'QrScannerView( consumers under lib/ missing from '
            'kScannerNavigationCatalog:\n${unlisted.join('\n')}\n'
            'Add a catalog entry, use pushThenRearm, and add a real-cubit '
            'double-capture regression test',
      );
    },
  );
}
