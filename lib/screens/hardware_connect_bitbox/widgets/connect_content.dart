import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';
import 'package:realunit_wallet/widgets/scrollable_actions_layout.dart';

class ConnectContent extends StatelessWidget {
  final String imagePath;
  final String title;
  final Widget child;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;

  /// Overrides for the button labels. Default to the generic confirm / cancel
  /// strings so existing call sites stay unchanged.
  final String? confirmLabel;
  final String? cancelLabel;

  const ConnectContent({
    super.key,
    required this.imagePath,
    required this.title,
    required this.child,
    this.onConfirm,
    this.onCancel,
    this.confirmLabel,
    this.cancelLabel,
  });

  @override
  Widget build(BuildContext context) {
    final actions = <Widget>[
      if (onConfirm != null)
        AppFilledButton(
          onPressed: onConfirm,
          label: confirmLabel ?? S.of(context).confirm,
        ),
      if (onCancel != null)
        AppFilledButton(
          variant: .secondary,
          fullWidth: false,
          onPressed: onCancel,
          label: cancelLabel ?? S.of(context).cancel,
        ),
    ];

    return ScrollableActionsLayout(
      padding: const .symmetric(vertical: 20),
      actionsSpacing: 12,
      body: Column(
        spacing: 10,
        children: [
          // Cap illustration height so accessibility text scale still leaves
          // room for copy + actions in the scroll viewport.
          Padding(
            padding: const .only(top: 24, bottom: 12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: SvgPicture.asset(imagePath, fit: BoxFit.contain),
            ),
          ),
          Text(
            title,
            textAlign: .center,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          child,
        ],
      ),
      actions: actions,
    );
  }
}
