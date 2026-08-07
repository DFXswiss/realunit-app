import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';
import 'package:realunit_wallet/widgets/scrollable_actions_layout.dart';

class KycCompletedPage extends StatelessWidget {
  const KycCompletedPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.of(context).kyc)),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: SafeArea(
          child: ScrollableActionsLayout(
            centerBody: true,
            body: Column(
              spacing: 24,
              children: [
                Text(
                  S.of(context).kycCompleted,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 26,
                    letterSpacing: 26 * -0.02,
                    height: 30 / 26,
                  ),
                ),
                Text(
                  S.of(context).kycCompletedDescription,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 18 / 14,
                    letterSpacing: 0.0,
                  ),
                ),
              ],
            ),
            actions: [
              Padding(
                padding: const .symmetric(vertical: 16.0),
                child: AppFilledButton(
                  onPressed: context.pop,
                  label: S.of(context).close,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
