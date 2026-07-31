import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/setup/routing/routes/app_routes.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/action_button.dart';

class DashboardActions extends StatelessWidget {
  const DashboardActions({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: 10,
      children: [
        Expanded(
          child: ActionButton(
            icon: Icon(
              Icons.add_circle_rounded,
              color: RealUnitColors.basic.white,
              size: 20,
            ),
            label: S.of(context).buy,
            onPressed: () => context.pushNamed(AppRoutes.buy),
          ),
        ),
        Expanded(
          child: ActionButton(
            icon: Icon(
              Icons.do_not_disturb_on_rounded,
              color: RealUnitColors.basic.white,
              size: 20,
            ),
            label: S.of(context).sell,
            onPressed: () => context.pushNamed(AppRoutes.sell),
          ),
        ),
        Expanded(
          child: ActionButton(
            icon: Icon(
              Icons.qr_code_scanner_rounded,
              color: RealUnitColors.basic.white,
              size: 20,
            ),
            label: S.of(context).pay,
            onPressed: () => context.pushNamed(AppRoutes.pay),
          ),
        ),
        Expanded(
          child: ActionButton(
            icon: Icon(
              Icons.send_rounded,
              color: RealUnitColors.basic.white,
              size: 20,
            ),
            label: S.of(context).send,
            onPressed: () => context.pushNamed(AppRoutes.send),
          ),
        ),
      ],
    );
  }
}
