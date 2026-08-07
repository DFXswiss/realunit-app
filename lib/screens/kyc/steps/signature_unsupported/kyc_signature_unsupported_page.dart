import 'package:flutter/material.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/scrollable_actions_layout.dart';

class KycSignatureUnsupportedPage extends StatelessWidget {
  const KycSignatureUnsupportedPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.of(context).kycSignatureUnsupportedTitle),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0),
        child: SafeArea(
          child: ScrollableActionsLayout(
            centerBody: true,
            actions: const [],
            body: Column(
              spacing: 16.0,
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 48,
                  color: RealUnitColors.neutral500,
                ),
                Text(
                  S.of(context).kycSignatureUnsupportedTitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                Text(
                  S.of(context).kycSignatureUnsupportedDescription,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: RealUnitColors.neutral500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
