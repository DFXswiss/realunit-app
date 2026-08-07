import 'package:flutter/material.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';
import 'package:realunit_wallet/widgets/buttons/app_text_button.dart';
import 'package:realunit_wallet/widgets/scrollable_actions_layout.dart';

class EnableBiometricBottomSheet extends StatelessWidget {
  const EnableBiometricBottomSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: ScrollableActionsLayout(
          shrinkWrap: true,
          padding: const EdgeInsets.all(20.0),
          actionsSpacing: 8.0,
          body: Column(
            spacing: 32.0,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.fingerprint,
                size: 64,
                color: RealUnitColors.realUnitBlue,
              ),
              Column(
                spacing: 8.0,
                children: [
                  Text(
                    S.of(context).biometricAuthenticationActivate,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: RealUnitColors.realUnitBlack,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  Text(
                    S.of(context).biometricAuthenticationActivateDescription,
                    style: const TextStyle(
                      fontSize: 14,
                      color: RealUnitColors.neutral500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(top: 32.0),
              child: AppFilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                label: S.of(context).enable,
              ),
            ),
            AppTextButton(
              onPressed: () => Navigator.of(context).pop(false),
              label: S.of(context).skip,
            ),
          ],
        ),
      ),
    );
  }
}
