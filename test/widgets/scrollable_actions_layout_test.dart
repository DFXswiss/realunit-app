import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/widgets/scrollable_actions_layout.dart';

import '../helper/helper.dart';

/// Global axis-aligned rect of the [finder]'s [RenderBox].
Rect _globalRect(WidgetTester tester, Finder finder) {
  final box = tester.renderObject<RenderBox>(finder);
  return box.localToGlobal(Offset.zero) & box.size;
}

void main() {
  group('$ScrollableActionsLayout', () {
    testWidgets('keeps actions tappable when body is taller than viewport', (tester) async {
      var taps = 0;
      const viewport = Size(375, 500);

      await tester.binding.setSurfaceSize(viewport);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await expectNoLayoutOverflow(tester, () async {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(size: viewport),
              child: Scaffold(
                body: SizedBox(
                  height: 500,
                  child: ScrollableActionsLayout(
                    body: Column(
                      children: List.generate(
                        40,
                        (i) => SizedBox(height: 40, child: Text('row $i')),
                      ),
                    ),
                    actions: [
                      FilledButton(
                        onPressed: () => taps++,
                        child: const Text('Do it'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
      });

      await expectFullyTappable(
        tester,
        find.text('Do it'),
        within: find.byType(ScrollableActionsLayout),
      );
      expect(taps, 1);
    });

    testWidgets('throws when height is unbounded (no silent degradation)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ScrollableActionsLayout(
                body: Text('body'),
                actions: [Text('action')],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final exception = tester.takeException();
      expect(exception, isA<FlutterError>());
      expect(
        (exception as FlutterError).toString(),
        contains('requires a bounded height'),
      );
    });

    testWidgets(
      'centerBody: true centers a short body within the scroll viewport',
      (tester) async {
        const hostSize = Size(375, 500);
        // Short body clearly smaller than the leftover scroll viewport.
        const bodyHeight = 80.0;
        // Key the inner marker (visible content), not the outer body wrapper:
        // ConstrainedBox(minHeight: viewport) makes the outer body fill the
        // viewport by design, so its center always coincides with the viewport.
        final markerKey = GlobalKey();

        await tester.binding.setSurfaceSize(hostSize);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(size: hostSize),
              child: Scaffold(
                body: SizedBox(
                  height: hostSize.height,
                  child: ScrollableActionsLayout(
                    centerBody: true,
                    body: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          key: markerKey,
                          height: bodyHeight,
                          child: const Text('short body'),
                        ),
                      ],
                    ),
                    actions: [
                      FilledButton(
                        onPressed: () {},
                        child: const Text('Confirm'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final markerRect = _globalRect(tester, find.byKey(markerKey));
        // SingleChildScrollView's render box is the visible scroll viewport
        // above the sticky action block.
        final viewportRect = _globalRect(
          tester,
          find.byKey(const Key('scrollable_actions_layout.body_scroll_view')),
        );

        // ±4px: small float/subpixel tolerance for RenderBox→global conversion;
        // true centering is exact, so a few logical pixels still proves intent
        // without flaking on platform rounding.
        expect(
          markerRect.center.dy,
          closeTo(viewportRect.center.dy, 4),
          reason:
              'short body marker should be vertically centered in the scroll '
              'viewport (marker.center.dy=${markerRect.center.dy}, '
              'viewport.center.dy=${viewportRect.center.dy})',
        );
      },
    );

    testWidgets(
      'centerBody: true keeps a tall body from clipping or centering off-screen',
      (tester) async {
        const hostSize = Size(375, 500);
        final bodyKey = GlobalKey();

        await tester.binding.setSurfaceSize(hostSize);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await expectNoLayoutOverflow(tester, () async {
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: const MediaQueryData(size: hostSize),
                child: Scaffold(
                  body: SizedBox(
                    height: hostSize.height,
                    child: ScrollableActionsLayout(
                      centerBody: true,
                      body: Column(
                        key: bodyKey,
                        children: List.generate(
                          40,
                          (i) => SizedBox(height: 40, child: Text('row $i')),
                        ),
                      ),
                      actions: [
                        FilledButton(
                          onPressed: () {},
                          child: const Text('Confirm tall'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
        });

        final bodyRect = _globalRect(tester, find.byKey(bodyKey));
        final viewportRect = _globalRect(
          tester,
          find.byKey(const Key('scrollable_actions_layout.body_scroll_view')),
        );

        // Tall body must start at the top of the scroll viewport (not centered
        // off-screen). ±4px covers subpixel/rounding noise only.
        expect(
          bodyRect.top,
          closeTo(viewportRect.top, 4),
          reason:
              'tall body must top-align in the viewport when it outgrows it '
              '(body.top=${bodyRect.top}, viewport.top=${viewportRect.top})',
        );

        // Content must be scrollable: scroll position starts at 0 and advances
        // after a drag. Scope to the body scroll view — actions also embed a
        // Scrollable/SingleChildScrollView when the action list is non-empty.
        final scrollable = tester.state<ScrollableState>(
          find.descendant(
            of: find.byKey(
              const Key('scrollable_actions_layout.body_scroll_view'),
            ),
            matching: find.byType(Scrollable),
          ),
        );
        expect(scrollable.position.pixels, 0);
        await tester.drag(
          find.byKey(const Key('scrollable_actions_layout.body_scroll_view')),
          const Offset(0, -200),
        );
        await tester.pump();
        expect(scrollable.position.pixels, greaterThan(0));

        await expectFullyTappable(
          tester,
          find.text('Confirm tall'),
          within: find.byType(ScrollableActionsLayout),
        );
      },
    );

    testWidgets(
      'centerBody: false (default) keeps a short body top-aligned',
      (tester) async {
        const hostSize = Size(375, 500);
        const bodyHeight = 80.0;
        // Key the inner marker (visible content), not the outer body wrapper:
        // ConstrainedBox(minHeight: viewport) makes the outer body fill the
        // viewport by design, so its top/center always match the viewport.
        final markerKey = GlobalKey();

        await tester.binding.setSurfaceSize(hostSize);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(size: hostSize),
              child: Scaffold(
                body: SizedBox(
                  height: hostSize.height,
                  child: ScrollableActionsLayout(
                    // centerBody intentionally omitted — default false.
                    body: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          key: markerKey,
                          height: bodyHeight,
                          child: const Text('short body default'),
                        ),
                      ],
                    ),
                    actions: [
                      FilledButton(
                        onPressed: () {},
                        child: const Text('Confirm default'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final markerRect = _globalRect(tester, find.byKey(markerKey));
        final viewportRect = _globalRect(
          tester,
          find.byKey(const Key('scrollable_actions_layout.body_scroll_view')),
        );

        // Default must stay top-aligned (regression for the 15 non-centering
        // screens). ±4px is only for float/subpixel noise.
        expect(
          markerRect.top,
          closeTo(viewportRect.top, 4),
          reason:
              'default centerBody=false must top-align short body marker '
              '(marker.top=${markerRect.top}, viewport.top=${viewportRect.top})',
        );
        // Explicitly not centered: marker center should be well above viewport
        // center when the content is much shorter than the viewport.
        expect(
          (viewportRect.center.dy - markerRect.center.dy).abs(),
          greaterThan(20),
          reason: 'short body marker must not be vertically centered by default',
        );
      },
    );

    testWidgets(
      'caps tall actionBlock so Column does not overflow and CTA stays tappable',
      (tester) async {
        // Host short enough that 4×56px actions + 3×12px spacing (260px) alone
        // exceed the host height (140px) — the pre-fix overflow scenario
        // (plain Column of actions with no ConstrainedBox/SingleChildScrollView).
        const hostHeight = 140.0;
        const hostSize = Size(375, hostHeight);
        const actionHeight = 56.0;
        // 4×56 + 3×12 spacing = 260px intrinsic (must overflow host=140).
        const intrinsicActionsHeight = 4 * actionHeight + 3 * 12.0;
        var taps = 0;

        await tester.binding.setSurfaceSize(hostSize);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await expectNoLayoutOverflow(tester, () async {
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: const MediaQueryData(size: hostSize),
                child: Scaffold(
                  body: SizedBox(
                    height: hostHeight,
                    child: ScrollableActionsLayout(
                      body: const Text('body'),
                      actions: [
                        SizedBox(
                          height: actionHeight,
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: () => taps++,
                            child: const Text('Primary CTA'),
                          ),
                        ),
                        const SizedBox(
                          height: actionHeight,
                          width: double.infinity,
                          child: ColoredBox(
                            color: Color(0xFFCCCCCC),
                            child: Center(child: Text('Action 2')),
                          ),
                        ),
                        const SizedBox(
                          height: actionHeight,
                          width: double.infinity,
                          child: ColoredBox(
                            color: Color(0xFFBBBBBB),
                            child: Center(child: Text('Action 3')),
                          ),
                        ),
                        const SizedBox(
                          height: actionHeight,
                          width: double.infinity,
                          child: ColoredBox(
                            color: Color(0xFFAAAAAA),
                            child: Center(child: Text('Action 4')),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
        });

        await expectFullyTappable(
          tester,
          find.text('Primary CTA'),
          within: find.byType(ScrollableActionsLayout),
        );
        expect(taps, 1);

        // Cap binds only at the full available height — no fraction budget.
        // Intrinsic 260 > host 140, so the action block must be clamped to host.
        expect(intrinsicActionsHeight, greaterThan(hostHeight));
        final actionsScrollBox = tester.renderObject<RenderBox>(
          find.byKey(const Key('scrollable_actions_layout.actions_scroll_view')),
        );
        expect(
          actionsScrollBox.size.height,
          lessThanOrEqualTo(hostHeight),
          reason:
              'actionBlock height ${actionsScrollBox.size.height} must not exceed '
              'full available host height ($hostHeight)',
        );
      },
    );

    testWidgets(
      'normal-case actionBlock shrink-wraps to exact intrinsic height; body keeps leftover',
      (tester) async {
        const hostSize = Size(375, 500);
        const hostHeight = 500.0;
        // Fixed-height action so intrinsic height is known exactly (no theme
        // button sizing). Cap maxHeight = host (500) >> 48, so it must not bind.
        const intrinsicActionHeight = 48.0;
        final actionKey = GlobalKey();

        await tester.binding.setSurfaceSize(hostSize);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(size: hostSize),
              child: Scaffold(
                body: SizedBox(
                  height: hostHeight,
                  child: ScrollableActionsLayout(
                    body: const SizedBox(
                      height: 80,
                      child: Text('short body normal'),
                    ),
                    actions: [
                      SizedBox(
                        key: actionKey,
                        height: intrinsicActionHeight,
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () {},
                          child: const Text('Confirm normal'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final actionsScrollBox = tester.renderObject<RenderBox>(
          find.byKey(const Key('scrollable_actions_layout.actions_scroll_view')),
        );
        final actionsHeight = actionsScrollBox.size.height;

        // Cap must NEVER bind when content fits: rendered height equals
        // intrinsic height exactly (the field regression was a fraction cap
        // that clamped content which still fit the real leftover space).
        expect(
          actionsHeight,
          closeTo(intrinsicActionHeight, 1),
          reason:
              'when actions fit the viewport, actionBlock must shrink-wrap to '
              'exact intrinsic height $intrinsicActionHeight, got $actionsHeight '
              '(cap must not bind)',
        );

        // Body SingleChildScrollView viewport height must be the host leftover
        // after the shrink-wrapped actionBlock (same geometry as before any cap
        // existed). Keyed so it is never confused with the actions scroll view.
        final bodyScrollBox = tester.renderObject<RenderBox>(
          find.byKey(const Key('scrollable_actions_layout.body_scroll_view')),
        );
        expect(
          bodyScrollBox.size.height,
          closeTo(hostHeight - actionsHeight, 1),
          reason:
              'Expanded body viewport should receive hostHeight - actionBlock '
              '(${hostHeight - actionsHeight}), got ${bodyScrollBox.size.height}',
        );
      },
    );

    testWidgets(
      'does not clip actions that fit the real viewport even when they exceed an arbitrary fraction of it',
      (tester) async {
        // Field regression (DashboardView, empty balance, iPhone 13 mini @ 3x
        // text scale): inner available height ~308px, action content ~220px —
        // fits the real budget, but a 0.6 fraction cap would clamp to ~184.8px
        // and clip a CTA that was previously fine.
        //
        // Host total 356 with widget padding vertical 24×2 → inner 308.
        const hostHeight = 356.0;
        const hostSize = Size(375, hostHeight);
        const padding = EdgeInsets.symmetric(horizontal: 20, vertical: 24);
        const availableHeight = hostHeight - 48; // 308
        // ~220px action that fits in 308 but exceeds 0.6*308 = 184.8.
        const actionIntrinsicHeight = 220.0;
        const fractionWouldCapAt = availableHeight * 0.6; // 184.8
        var taps = 0;

        // Sanity: this scenario only pins the regression if the action fits
        // the real viewport yet would have been clipped by a fraction cap.
        expect(actionIntrinsicHeight, lessThan(availableHeight));
        expect(actionIntrinsicHeight, greaterThan(fractionWouldCapAt));

        await tester.binding.setSurfaceSize(hostSize);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await expectNoLayoutOverflow(tester, () async {
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: const MediaQueryData(size: hostSize),
                child: Scaffold(
                  body: SizedBox(
                    height: hostHeight,
                    child: ScrollableActionsLayout(
                      padding: padding,
                      body: const Text('dashboard body'),
                      actions: [
                        SizedBox(
                          height: actionIntrinsicHeight,
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: () => taps++,
                            child: const Text('Dashboard CTA'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
        });

        final actionsScrollBox = tester.renderObject<RenderBox>(
          find.byKey(const Key('scrollable_actions_layout.actions_scroll_view')),
        );
        // Cap must NOT bind: rendered height equals intrinsic ~220, not 184.8.
        expect(
          actionsScrollBox.size.height,
          closeTo(actionIntrinsicHeight, 1),
          reason:
              'action that fits real available height ($availableHeight) must '
              'render at full intrinsic $actionIntrinsicHeight, not be clamped '
              'to a fraction budget ($fractionWouldCapAt); got '
              '${actionsScrollBox.size.height}',
        );
        expect(
          actionsScrollBox.size.height,
          greaterThan(fractionWouldCapAt),
          reason:
              'explicitly larger than the deleted 0.6-fraction cap so nobody '
              'reintroduces a fraction-style budget',
        );

        await expectFullyTappable(
          tester,
          find.text('Dashboard CTA'),
          within: find.byType(ScrollableActionsLayout),
        );
        expect(taps, 1);
      },
    );

    testWidgets(
      'shrinkWrap: true sizes to short content under a generous cap',
      (tester) async {
        // Cap is a loose maxHeight (bottom-sheet style). Align loosens the
        // SizedBox's tight height so the layout can genuinely shrink-wrap.
        const hostSize = Size(375, 600);
        const cap = 600.0;
        const bodyHeight = 80.0;
        const actionHeight = 48.0;

        await tester.binding.setSurfaceSize(hostSize);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await expectNoLayoutOverflow(tester, () async {
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: const MediaQueryData(size: hostSize),
                child: Scaffold(
                  body: SizedBox(
                    height: cap,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: cap),
                        child: ScrollableActionsLayout(
                          shrinkWrap: true,
                          body: const SizedBox(
                            height: bodyHeight,
                            child: Text('shrink wrap short body'),
                          ),
                          actions: [
                            SizedBox(
                              height: actionHeight,
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: () {},
                                child: const Text('Shrink wrap CTA'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
        });

        final layoutBox = tester.renderObject<RenderBox>(
          find.byType(ScrollableActionsLayout),
        );
        // Content-sized: body + actions, not expanded to the 600px cap.
        // Tolerance covers spacing/theme chrome only — not a near-full fill.
        expect(
          layoutBox.size.height,
          closeTo(bodyHeight + actionHeight, 20),
          reason:
              'shrinkWrap short layout must size to content '
              '(~${bodyHeight + actionHeight}), not fill $cap; '
              'got ${layoutBox.size.height}',
        );
        expect(
          layoutBox.size.height,
          lessThan(cap / 2),
          reason: 'must not expand toward the generous cap',
        );

        await expectFullyTappable(
          tester,
          find.text('Shrink wrap CTA'),
          within: find.byType(ScrollableActionsLayout),
        );
      },
    );

    testWidgets(
      'shrinkWrap: true caps tall body, scrolls, and pins actions below',
      (tester) async {
        const hostSize = Size(375, 500);
        const cap = 500.0;
        const actionHeight = 48.0;
        var taps = 0;

        await tester.binding.setSurfaceSize(hostSize);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await expectNoLayoutOverflow(tester, () async {
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: const MediaQueryData(size: hostSize),
                child: Scaffold(
                  body: SizedBox(
                    height: cap,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: cap),
                        child: ScrollableActionsLayout(
                          shrinkWrap: true,
                          body: Column(
                            children: List.generate(
                              40,
                              (i) => SizedBox(height: 40, child: Text('row $i')),
                            ),
                          ),
                          actions: [
                            SizedBox(
                              height: actionHeight,
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: () => taps++,
                                child: const Text('Shrink wrap tall CTA'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
        });

        final layoutBox = tester.renderObject<RenderBox>(
          find.byType(ScrollableActionsLayout),
        );
        // Tall content must hit the cap, not overflow past it.
        expect(
          layoutBox.size.height,
          closeTo(cap, 1),
          reason:
              'shrinkWrap tall layout must equal the cap ($cap), '
              'got ${layoutBox.size.height}',
        );

        final bodyScrollKey = const Key('scrollable_actions_layout.body_scroll_view');
        final scrollable = tester.state<ScrollableState>(
          find.descendant(
            of: find.byKey(bodyScrollKey),
            matching: find.byType(Scrollable),
          ),
        );
        expect(
          scrollable.position.maxScrollExtent,
          greaterThan(0),
          reason: 'body must be scrollable when taller than the remaining cap',
        );

        final bodyScrollRect = _globalRect(tester, find.byKey(bodyScrollKey));
        final actionRect = _globalRect(tester, find.text('Shrink wrap tall CTA'));
        expect(
          actionRect.top,
          greaterThanOrEqualTo(bodyScrollRect.bottom - 0.5),
          reason:
              'actions must stay pinned below the body scroll view '
              '(action.top=${actionRect.top}, body.bottom=${bodyScrollRect.bottom})',
        );

        await expectFullyTappable(
          tester,
          find.text('Shrink wrap tall CTA'),
          within: find.byType(ScrollableActionsLayout),
        );
        expect(taps, 1);
      },
    );

    testWidgets(
      'shrinkWrap: false (default) still expands short body to fill host',
      (tester) async {
        const hostSize = Size(375, 600);
        const hostHeight = 600.0;
        const bodyHeight = 80.0;
        const actionHeight = 48.0;

        await tester.binding.setSurfaceSize(hostSize);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(size: hostSize),
              child: Scaffold(
                body: SizedBox(
                  height: hostHeight,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: hostHeight),
                    child: ScrollableActionsLayout(
                      // shrinkWrap intentionally omitted — default false.
                      body: const SizedBox(
                        height: bodyHeight,
                        child: Text('default short body'),
                      ),
                      actions: [
                        SizedBox(
                          height: actionHeight,
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: () {},
                            child: const Text('Default expand CTA'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final layoutBox = tester.renderObject<RenderBox>(
          find.byType(ScrollableActionsLayout),
        );
        // Existing screens rely on Expanded body filling the bounded host.
        expect(
          layoutBox.size.height,
          closeTo(hostHeight, 1),
          reason:
              'default shrinkWrap=false must expand to full host height '
              '($hostHeight), got ${layoutBox.size.height}',
        );
      },
    );
  });
}
