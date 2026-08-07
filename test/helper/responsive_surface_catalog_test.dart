import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'responsive_surface_catalog.dart';

/// Every public (`class X extends StatelessWidget`/`StatefulWidget`) name declared in
/// [source]. Private (`_`-prefixed) classes are excluded: a matrix test in a different
/// file could never import/reference them, so requiring a match against them would prove
/// nothing.
List<String> _publicWidgetClassNames(String source) => [
  for (final match in RegExp(
    r'class\s+([A-Za-z][A-Za-z0-9]*)\s+extends\s+State(?:less|ful)Widget\b',
  ).allMatches(source))
    match.group(1)!,
];

/// `lib/`-relative paths imported from [source] via `package:realunit_wallet/...`.
Set<String> _packageLibImportPaths(String source) => {
  for (final match in RegExp(
    r"import\s+'package:realunit_wallet/([^']+)'",
  ).allMatches(source))
    'lib/${match.group(1)!}',
};

/// Whether [productionPath] is reachable from the matrix test's package imports,
/// allowing at most one composition hop (direct import, or import of a lib file that
/// itself imports the production file). Unbounded transitive closure is intentionally
/// not used — it would make the check meaningless.
bool _isProductionReachableViaOneHopImport({
  required String productionPath,
  required String matrixContents,
}) {
  final directImports = _packageLibImportPaths(matrixContents);
  if (directImports.contains(productionPath)) {
    return true;
  }
  for (final importPath in directImports) {
    final file = File(importPath);
    if (!file.existsSync()) {
      continue;
    }
    final hopImports = _packageLibImportPaths(file.readAsStringSync());
    if (hopImports.contains(productionPath)) {
      return true;
    }
  }
  return false;
}

void main() {
  test('every catalogued responsive surface has a matrix test file on disk', () {
    for (final surface in kResponsiveSurfaceCatalog) {
      final file = File(surface.matrixTestPath);
      expect(
        file.existsSync(),
        isTrue,
        reason:
            'Surface "${surface.id}" lists matrix test '
            '${surface.matrixTestPath} but the file is missing',
      );
    }
  });

  test('every catalogued surface has a production file on disk', () {
    for (final surface in kResponsiveSurfaceCatalog) {
      final file = File(surface.productionPath);
      expect(
        file.existsSync(),
        isTrue,
        reason:
            'Surface "${surface.id}" lists production file '
            '${surface.productionPath} but the file is missing',
      );
    }
  });

  test('every catalogued surface actually uses ScrollableActionsLayout', () {
    for (final surface in kResponsiveSurfaceCatalog) {
      final contents = File(surface.productionPath).readAsStringSync();
      expect(
        RegExp(r'ScrollableActionsLayout\s*\(').hasMatch(contents),
        isTrue,
        reason:
            'Surface "${surface.id}" (${surface.productionPath}) no longer '
            'references ScrollableActionsLayout — the responsive-layout '
            'contract regressed',
      );
    }
  });

  test('catalog is non-empty (responsive gate is active)', () {
    expect(kResponsiveSurfaceCatalog, isNotEmpty);
  });

  test(
    "every catalogued surface's matrix test actually exercises its production widget",
    () {
      final gaps = <String>[];
      for (final surface in kResponsiveSurfaceCatalog) {
        final productionContents = File(surface.productionPath).readAsStringSync();
        final classNames = _publicWidgetClassNames(productionContents);
        expect(
          classNames,
          isNotEmpty,
          reason:
              'Surface "${surface.id}" (${surface.productionPath}) declares no public '
              'StatelessWidget/StatefulWidget class — cannot verify its matrix test '
              'actually exercises it',
        );

        final matrixContents = File(surface.matrixTestPath).readAsStringSync();
        final referenced = classNames.where(matrixContents.contains).toList();
        final reachable = _isProductionReachableViaOneHopImport(
          productionPath: surface.productionPath,
          matrixContents: matrixContents,
        );
        if (referenced.isEmpty && !reachable) {
          gaps.add(
            'Surface "${surface.id}": none of $classNames (declared in '
            '${surface.productionPath}) are referenced by name in '
            '${surface.matrixTestPath}, and ${surface.productionPath} is not '
            "reachable from ${surface.matrixTestPath}'s direct imports "
            '(or one hop beyond them) — the matrix test may be exercising a '
            'different widget than the one this entry claims to gate',
          );
        }
      }

      expect(
        gaps,
        isEmpty,
        reason:
            'Matrix tests that do not reference their production widget by class name '
            'and do not reach it via one-hop package import:\n'
            '${gaps.join('\n')}',
      );
    },
  );
}
