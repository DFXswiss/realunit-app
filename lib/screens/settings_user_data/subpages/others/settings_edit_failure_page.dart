import 'package:flutter/material.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';
import 'package:realunit_wallet/widgets/scrollable_actions_layout.dart';

class SettingsEditFailurePage extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback onRefresh;

  const SettingsEditFailurePage(
    this.message, {
    super.key,
    required this.title,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Padding(
        padding: const .symmetric(horizontal: 20.0),
        child: SafeArea(
          child: ScrollableActionsLayout(
            centerBody: true,
            body: Column(
              mainAxisSize: .min,
              spacing: 8.0,
              children: [
                Text(
                  S.of(context).kycFailure,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                Text(
                  S.of(context).kycFailureDescription(message),
                  textAlign: .center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: RealUnitColors.neutral500),
                ),
              ],
            ),
            actions: [
              Padding(
                padding: const .symmetric(vertical: 16.0),
                child: AppFilledButton(
                  onPressed: onRefresh,
                  label: S.of(context).refresh,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
