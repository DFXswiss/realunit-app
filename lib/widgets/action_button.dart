import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:realunit_wallet/styles/colors.dart';

class ActionButton extends StatelessWidget {
  const ActionButton({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
    this.isLoading = false,
  });

  final Widget icon;
  final bool isLoading;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(25),
      color: RealUnitColors.realUnitBlue,
    ),
    child: InkWell(
      onTap: isLoading ? null : onPressed,
      child: SizedBox(
        width: 110,
        height: 50,
        child: isLoading
            ? CupertinoActivityIndicator(
                color: RealUnitColors.basic.white,
              )
            : Center(
                // Expanded call-sites (dashboard_actions) squeeze this
                // SizedBox's width down to ~80-84px, and large text scales
                // blow past the fixed 50px height — scaleDown + a
                // single-line label keeps the button overflow-free and
                // fully tappable instead of wrapping/clipping (responsive
                // matrix gate, issue class from PR #885).
                child: FittedBox(
                  fit: .scaleDown,
                  child: Column(
                    mainAxisSize: .min,
                    children: [
                      icon,
                      Text(
                        label,
                        maxLines: 1,
                        softWrap: false,
                        textAlign: .center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: RealUnitColors.basic.white,
                          fontWeight: .w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    ),
  );
}
