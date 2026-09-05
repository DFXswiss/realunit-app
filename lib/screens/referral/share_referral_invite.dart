import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

/// Origin for the iPad/Mac share popover. Uses the button box when laid out;
/// otherwise the screen so the sheet is not pinned to a 1×1 point at (0, 0).
Rect shareReferralInviteOrigin(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  if (box != null && box.hasSize && !box.size.isEmpty) {
    return box.localToGlobal(Offset.zero) & box.size;
  }
  return Offset.zero & MediaQuery.sizeOf(context);
}

/// Share the personalised invite text. [subject] is the share-sheet title
/// (Android chooser / Web Share) and the email subject. A platform throw
/// is returned as [ShareResultStatus.unavailable] so the share button can
/// show its error state.
// @no-integration-test: thin wrapper around `package:share_plus`; the invite
//   copy/share behaviour is covered by referral_copy_share_e2e_test.dart via a
//   mocked platform channel, and the OS share sheet itself has no headless CI device.
Future<ShareResult> shareReferralInvite({
  required BuildContext context,
  required String text,
  required String subject,
}) async {
  try {
    return await SharePlus.instance.share(
      ShareParams(
        text: text,
        subject: subject,
        title: subject,
        sharePositionOrigin: shareReferralInviteOrigin(context),
      ),
    );
  } catch (_) {
    return const ShareResult('', ShareResultStatus.unavailable);
  }
}
