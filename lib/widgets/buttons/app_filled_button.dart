import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:realunit_wallet/styles/colors.dart';

enum FilledButtonVariant { primary, secondary }

enum FilledButtonState { idle, loading, success, error }

/// Should be used instead of [FilledButton] to ensure consistent styling across the app.
class AppFilledButton extends StatelessWidget {
  const AppFilledButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = .primary,
    this.state = .idle,
    this.icon,
    this.fullWidth = true,
    this.autofocus = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final FilledButtonVariant variant;
  final FilledButtonState state;
  final IconData? icon;
  final bool fullWidth;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final button = switch (state) {
      FilledButtonState.loading => _loadingButton(),
      FilledButtonState.success => _successButton(),
      FilledButtonState.error => _errorButton(),
      FilledButtonState.idle => _idleButton(),
    };
    if (fullWidth) return SizedBox(width: double.infinity, child: button);
    return button;
  }

  Widget _idleButton() {
    final style = variant == FilledButtonVariant.secondary ? _secondaryStyle() : null;
    if (icon != null) {
      return FilledButton.icon(
        onPressed: onPressed,
        autofocus: autofocus,
        style: style,
        icon: Icon(
          icon!,
          color: variant == FilledButtonVariant.secondary ? RealUnitColors.realUnitBlack : null,
        ),
        label: Text(
          label,
          textAlign: .center,
        ),
      );
    }
    return FilledButton(
      onPressed: onPressed,
      autofocus: autofocus,
      style: style,
      child: Text(
        label,
        textAlign: .center,
      ),
    );
  }

  Widget _loadingButton() => FilledButton.icon(
    onPressed: null,
    style: variant == FilledButtonVariant.secondary
        ? _secondaryStyle()
        : ButtonStyle(
            backgroundColor: WidgetStateProperty.all(
              RealUnitColors.realUnitBlue.withValues(alpha: 0.5),
            ),
            foregroundColor: WidgetStateProperty.all(
              RealUnitColors.basic.white.withValues(alpha: 0.5),
            ),
          ),
    icon: SizedBox(
      height: 14,
      width: 14,
      child: CupertinoActivityIndicator(
        color: variant == FilledButtonVariant.secondary
            ? RealUnitColors.neutral500
            : RealUnitColors.basic.white.withValues(alpha: 0.5),
      ),
    ),
    label: Text(
      label,
      textAlign: .center,
    ),
  );

  Widget _successButton() {
    if (icon != null) {
      return FilledButton.icon(
        onPressed: onPressed,
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.all(RealUnitColors.green),
          foregroundColor: WidgetStateProperty.all(RealUnitColors.basic.white),
          iconColor: WidgetStateProperty.all(RealUnitColors.basic.white),
        ),
        icon: Icon(icon!),
        label: Text(
          label,
          textAlign: .center,
        ),
      );
    }
    return FilledButton(
      onPressed: onPressed,
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.all(RealUnitColors.green),
        foregroundColor: WidgetStateProperty.all(RealUnitColors.basic.white),
        iconColor: WidgetStateProperty.all(RealUnitColors.basic.white),
      ),
      child: Text(
        label,
        textAlign: .center,
      ),
    );
  }

  Widget _errorButton() {
    if (icon != null) {
      return FilledButton.icon(
        onPressed: onPressed,
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.all(RealUnitColors.status.red600),
          foregroundColor: WidgetStateProperty.all(RealUnitColors.basic.white),
          iconColor: WidgetStateProperty.all(RealUnitColors.basic.white),
        ),
        icon: Icon(icon!),
        label: Text(
          label,
          textAlign: .center,
        ),
      );
    }

    return FilledButton(
      onPressed: onPressed,
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.all(RealUnitColors.status.red600),
        foregroundColor: WidgetStateProperty.all(RealUnitColors.basic.white),
      ),
      child: Text(
        label,
        textAlign: .center,
      ),
    );
  }

  ButtonStyle _secondaryStyle() => ButtonStyle(
    backgroundColor: WidgetStateProperty.all(RealUnitColors.neutral100),
    foregroundColor: WidgetStateProperty.all(RealUnitColors.realUnitBlack),
  );
}
