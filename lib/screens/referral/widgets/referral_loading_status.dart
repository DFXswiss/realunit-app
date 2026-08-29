import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/styles/colors.dart';

/// Spinner plus copy for referral screens waiting on the summary.
class ReferralLoadingStatus extends StatelessWidget {
  const ReferralLoadingStatus({super.key});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Center(
      child: Semantics(
        container: true,
        liveRegion: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            const ExcludeSemantics(child: CupertinoActivityIndicator()),
            Text(
              s.referralLoading,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: RealUnitColors.neutral500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
