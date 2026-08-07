import 'package:flutter/material.dart';

/// Column layout that keeps [actions] reachable on every viewport and text scale.
///
/// **Contract**
/// - [body] scrolls inside a [SingleChildScrollView] whenever it grows with
///   content or accessibility text scale.
/// - [actions] (primary/secondary CTAs) stay **outside** the scroll view, in a
///   sticky block below it, so they never leave the hit-testable region (the
///   BitBox pairing regression).
/// - This widget requires a **bounded height** (bottom sheet, `Expanded`, or a
///   `SizedBox`). Giving it an unbounded height is a programming error: there
///   would be no room to scroll and the sticky actions would be pushed out of
///   the hit-test region — exactly the bug this widget exists to prevent. An
///   unbounded height throws a [FlutterError] in every build mode (debug and
///   release), so the failure is always loud and never a silently degraded
///   layout.
/// - The body is always given at least the leftover viewport height, so
///   [mainAxisAlignment] (and vertical centering via [centerBody]) works inside
///   it. A [Spacer] inside [body] is **not** allowed: inside a scroll view's
///   unbounded main axis it is a programming error (RenderFlex "unbounded"
///   exception), unlike the outer bounded-height contract above.
/// - When the actions alone need the entire viewport, [Expanded] for [body]
///   collapses toward zero and body content becomes unreachable while the
///   actions stay reachable — a deliberate trade (a visible, scrollable CTA
///   beats a dead one) and strictly better than the pre-fix overflow.
///
/// Use this for every bottom sheet and full-screen flow that combines long copy
/// with bottom CTAs. Do not put a [Spacer] above buttons and hope it fits.
class ScrollableActionsLayout extends StatelessWidget {
  const ScrollableActionsLayout({
    super.key,
    required this.body,
    this.actions = const [],
    this.padding = EdgeInsets.zero,
    this.actionsSpacing = 12,
    this.scrollPhysics,
    this.centerBody = false,
    this.shrinkWrap = false,
  });

  /// Scrollable main content (illustration, titles, forms, hints).
  final Widget body;

  /// Sticky action widgets, top-to-bottom (confirm above cancel).
  final List<Widget> actions;

  /// Outer padding around the whole layout.
  final EdgeInsetsGeometry padding;

  /// Vertical gap between action widgets.
  final double actionsSpacing;

  final ScrollPhysics? scrollPhysics;

  /// Vertically centre [body] while it fits the viewport (it still scrolls once
  /// it outgrows it). Use for screens that centred their content with a
  /// `Spacer()` above and below — without this they would top-align.
  final bool centerBody;

  /// Size to content (up to the incoming max height) instead of expanding to
  /// fill it. For bottom sheets / dialogs that should be only as tall as their
  /// content but still cap-and-scroll when content grows past the available
  /// height. In this mode the body is NOT floored to the viewport height (so it
  /// genuinely shrink-wraps), the actions stay pinned below it, and the whole
  /// layout scrolls its body once content exceeds the cap.
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (!constraints.hasBoundedHeight) {
            throw FlutterError.fromParts(<DiagnosticsNode>[
              ErrorSummary('ScrollableActionsLayout requires a bounded height.'),
              ErrorDescription(
                'It was given an unbounded height, so the body could not scroll and the '
                'sticky actions would be pushed out of the hit-test region — the exact '
                'bug this widget exists to prevent.',
              ),
              ErrorHint(
                'Host it in a bottom sheet, an Expanded, or a SizedBox with a fixed '
                'height. A Column(mainAxisSize: .min) hands its children an unbounded '
                'height and is not a valid host.',
              ),
            ]);
          }

          final Widget actionBlock = actions.isEmpty
              ? const SizedBox.shrink()
              : ConstrainedBox(
                  // A Column lays out non-flex children with an UNBOUNDED main axis, so
                  // without this the action block takes its full intrinsic height and
                  // overflows the Column when it exceeds the viewport — clipping the CTA
                  // out of the hit-test region, the exact bug this widget prevents.
                  // Bounding it at the viewport height is enough: a SingleChildScrollView
                  // under a loose maxHeight shrink-wraps to its child, so when the actions
                  // fit (the normal case) NOTHING changes; only when they would overflow
                  // are they capped and scrolled internally.
                  constraints: BoxConstraints(maxHeight: constraints.maxHeight),
                  child: SingleChildScrollView(
                    key: const Key('scrollable_actions_layout.actions_scroll_view'),
                    child: Column(
                      mainAxisSize: .min,
                      spacing: actionsSpacing,
                      children: actions,
                    ),
                  ),
                );

          return Column(
            crossAxisAlignment: .stretch,
            mainAxisSize: shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
            children: [
              if (shrinkWrap)
                Flexible(
                  child: SingleChildScrollView(
                    key: const Key('scrollable_actions_layout.body_scroll_view'),
                    physics: scrollPhysics,
                    child: SizedBox(
                      // Center() below loosens the width constraint; without this the
                      // crossAxisAlignment: .stretch chain breaks for width-dependent bodies.
                      width: double.infinity,
                      child: centerBody ? Center(child: body) : body,
                    ),
                  ),
                )
              else
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, viewport) => SingleChildScrollView(
                      key: const Key('scrollable_actions_layout.body_scroll_view'),
                      physics: scrollPhysics,
                      child: ConstrainedBox(
                        // Always at least the leftover viewport height, so bodies may use
                        // mainAxisAlignment / centering. Once the body outgrows the viewport
                        // minHeight stops binding and the body simply scrolls.
                        constraints: BoxConstraints(minHeight: viewport.maxHeight),
                        child: SizedBox(
                          // Center() below loosens the width constraint; without this the
                          // crossAxisAlignment: .stretch chain breaks for width-dependent bodies.
                          width: double.infinity,
                          child: centerBody ? Center(child: body) : body,
                        ),
                      ),
                    ),
                  ),
                ),
              actionBlock,
            ],
          );
        },
      ),
    );
  }
}
