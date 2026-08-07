import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/styles/themes.dart';

/// Asserts that no [RenderFlex] overflow was reported during [body].
///
/// Catches the class of bugs where content is painted below a clipped sheet
/// and buttons stop receiving taps.
Future<void> expectNoLayoutOverflow(
  WidgetTester tester,
  Future<void> Function() body, {
  String? reason,
}) async {
  final overflows = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final message = details.exceptionAsString();
    if (message.contains('overflowed') || message.contains('OVERFLOWING')) {
      overflows.add(message.split('\n').first);
    }
    previous?.call(details);
  };
  try {
    await body();
    // Allow a frame for flex overflow reporting.
    await tester.pump();
  } finally {
    FlutterError.onError = previous;
  }

  expect(
    overflows,
    isEmpty,
    reason: reason ??
        'Expected no RenderFlex overflow, got:\n${overflows.join('\n')}',
  );
}

/// Asserts [finder] resolves to a box with real size, fully inside [within],
/// and that a real pointer tap at its visual center actually reaches a render
/// object belonging to [finder]'s widget subtree (not just that *some* hit
/// path exists — [RenderView.hitTest] always returns a non-empty path, so
/// checking for non-emptiness alone proves nothing). [within] is required
/// because it is the only load-bearing containment check; callers must name
/// the sheet/page that bounds the tappable area.
///
/// Prefer this over `tester.widget<AppFilledButton>(...).onPressed?.call()`.
Future<void> expectFullyTappable(
  WidgetTester tester,
  Finder finder, {
  required Finder within,
  String? reason,
}) async {
  expect(
    finder,
    findsOneWidget,
    reason: reason ?? 'tappable target not found: $finder',
  );

  final box = tester.renderObject<RenderBox>(finder);
  // Map BOTH corners through the render transform: `localToGlobal(zero) &
  // size` appends the untransformed layout size, which overstates the visual
  // rect for scaled targets (e.g. inside a FittedBox) and fails containment
  // on content that visibly fits. For untransformed targets both forms agree.
  final rect = Rect.fromPoints(
    box.localToGlobal(Offset.zero),
    box.localToGlobal(box.size.bottomRight(Offset.zero)),
  );

  expect(
    rect.width,
    greaterThan(0),
    reason: reason ?? 'tappable target has zero width',
  );
  expect(
    rect.height,
    greaterThan(0),
    reason: reason ?? 'tappable target has zero height',
  );

  expect(within, findsOneWidget, reason: 'within parent not found');
  final parentBox = tester.renderObject<RenderBox>(within);
  final parentRect = Rect.fromPoints(
    parentBox.localToGlobal(Offset.zero),
    parentBox.localToGlobal(parentBox.size.bottomRight(Offset.zero)),
  );
  // Allow 1px float tolerance.
  final inflated = parentRect.inflate(1);
  expect(
    inflated.contains(rect.topLeft) && inflated.contains(rect.bottomRight),
    isTrue,
    reason:
        reason ??
        'target $rect is not fully inside parent $parentRect '
            '(clipped / overflowed — taps will miss)',
  );

  // Hit-test at the visual center and assert the hit path actually reaches a
  // render object belonging to [finder]'s own element subtree — not merely
  // that some (any) hit path exists, which is always true for RenderView.
  final center = rect.center;
  final result = HitTestResult();
  WidgetsBinding.instance.hitTestInView(result, center, tester.view.viewId);

  final targets = <RenderObject>{};
  void collectRenderObjects(Element element) {
    final renderObject = element.renderObject;
    if (renderObject != null) {
      targets.add(renderObject);
    }
    element.visitChildren(collectRenderObjects);
  }

  collectRenderObjects(finder.evaluate().single);

  expect(
    result.path.any((entry) => targets.contains(entry.target)),
    isTrue,
    reason:
        reason ??
        'hit test at $center did not reach $finder — the control is '
            'covered, clipped, or outside the hit-test region',
  );

  await tester.tap(finder, warnIfMissed: true);
  await tester.pump();
}

/// Runs [body] with [platform] active as the target-platform override.
///
/// The override must span the whole test body: widgets that read
/// `defaultTargetPlatform` directly (e.g. `DeviceInfo.isIOS`, which selects a
/// different, longer iOS copy) re-read it on every rebuild, and
/// [expectFullyTappable] rebuilds while tapping. `addTearDown` cannot be used —
/// the framework's `_verifyInvariants()` runs before package:test tear-downs
/// and would trip `debugAssertAllFoundationVarsUnset`.
Future<void> withTargetPlatform(
  TargetPlatform platform,
  Future<void> Function() body,
) async {
  final previous = debugDefaultTargetPlatformOverride;
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = previous;
  }
}

/// Pumps [widget] as a clipped bottom-sheet-like host (mirrors production
/// `showModalBottomSheet` clipping) under [mediaQuery], with real app
/// localizations wired up so widgets calling `S.of(context)` do not throw.
Future<void> pumpClippedSheet(
  WidgetTester tester, {
  required Widget widget,
  required MediaQueryData mediaQuery,
  ThemeData? theme,
  Locale locale = const Locale('de'),
}) async {
  await tester.binding.setSurfaceSize(mediaQuery.size);
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });

  await tester.pumpWidget(
    MediaQuery(
      data: mediaQuery,
      child: MaterialApp(
        theme: theme ?? realUnitTheme,
        locale: locale,
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: Material(
              clipBehavior: Clip.antiAlias,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
              child: widget,
            ),
          ),
        ),
      ),
    ),
  );
  // SVGs / first frame settle, matching the reference matrix test.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}
