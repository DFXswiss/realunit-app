import 'package:flutter/material.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/scrollable_actions_layout.dart';

class KycFailurePage extends StatelessWidget {
  final String message;

  const KycFailurePage({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.of(context).kyc)),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0),
        child: SafeArea(
          child: ScrollableActionsLayout(
            centerBody: true,
            actions: const [],
            body: Column(
              spacing: 8.0,
              children: [
                Text(
                  S.of(context).kycFailure,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    height: 30 / 26,
                    letterSpacing: -0.52,
                  ),
                ),
                Text(
                  S.of(context).kycFailureDescription(message),
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
        ),
      ),
    );
  }
}
