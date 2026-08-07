import 'package:flutter/material.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';
import 'package:realunit_wallet/widgets/scrollable_actions_layout.dart';
import 'package:realunit_wallet/widgets/text_substring_highlighting.dart';

class SettingsEditPendingPage extends StatelessWidget {
  final String title;
  final VoidCallback onRefresh;

  const SettingsEditPendingPage({
    super.key,
    required this.title,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
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
                  S.of(context).kycPending,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                TextSubstringHighlighting(
                  text: S.of(context).kycPendingDescription(title),
                  textAlign: .center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: RealUnitColors.neutral500),
                  highlightedText: title,
                  highlightedStyle:
                      Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(
                        color: RealUnitColors.neutral500,
                        fontWeight: .w600,
                      ),
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
