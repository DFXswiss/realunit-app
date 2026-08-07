import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';
import 'package:realunit_wallet/widgets/handlebars.dart';
import 'package:realunit_wallet/widgets/scrollable_actions_layout.dart';

class SellExecutedSheet extends StatelessWidget {
  const SellExecutedSheet({super.key});

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      width: double.infinity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Handlebars.horizontal(context, margin: const EdgeInsets.only(top: 5), width: 36),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.9,
            ),
            child: ScrollableActionsLayout(
              shrinkWrap: true,
              body: Padding(
                padding: const EdgeInsets.symmetric(vertical: 50.0, horizontal: 30.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      color: RealUnitColors.realUnitBlue,
                      size: 64,
                    ),
                    const SizedBox(height: 28),
                    Text(
                      S.of(context).sellSuccess,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        height: 30 / 26,
                        letterSpacing: 26 * -0.02,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      S.of(context).sellSuccessDescription,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: RealUnitColors.neutral500,
                        fontSize: 14,
                        height: 18 / 14,
                        letterSpacing: 0.0,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: AppFilledButton(
                    variant: .secondary,
                    fullWidth: false,
                    onPressed: () => context.pop(),
                    label: S.of(context).close,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
