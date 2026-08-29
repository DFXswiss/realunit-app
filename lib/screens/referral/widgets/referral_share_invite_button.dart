import 'dart:async';

import 'package:flutter/material.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/screens/referral/share_referral_invite.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';
import 'package:share_plus/share_plus.dart';

/// Shares the personalised invite text. A second tap while the sheet is
/// open is ignored. A platform share failure keeps the label in the error
/// state for 2s and stays tappable. A new share text while the sheet is
/// open does not show that error on the new invite. If the sheet never
/// returns, resuming the app clears loading so Versenden is tappable.
class ReferralShareInviteButton extends StatefulWidget {
  final String text;
  final bool autofocus;

  const ReferralShareInviteButton({
    super.key,
    required this.text,
    this.autofocus = false,
  });

  @override
  State<ReferralShareInviteButton> createState() =>
      _ReferralShareInviteButtonState();
}

class _ReferralShareInviteButtonState extends State<ReferralShareInviteButton>
    with WidgetsBindingObserver {
  Timer? _reset;
  bool _failed = false;
  bool _sharing = false;
  int _shareGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(ReferralShareInviteButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text == widget.text || (!_failed && !_sharing)) return;
    _reset?.cancel();
    _failed = false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reset?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_sharing) return;
    _shareGeneration++;
    setState(() => _sharing = false);
  }

  Future<void> _share() async {
    if (_sharing) return;
    final generation = ++_shareGeneration;
    setState(() {
      _sharing = true;
      _failed = false;
    });
    final text = widget.text;
    try {
      final result = await shareReferralInvite(
        context: context,
        text: text,
        subject: S.of(context).referralInviteUrlLabel,
      );
      if (!mounted || generation != _shareGeneration || widget.text != text) {
        return;
      }
      if (result.status != ShareResultStatus.unavailable) return;
      setState(() => _failed = true);
      _reset?.cancel();
      _reset = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _failed = false);
      });
    } finally {
      if (mounted && generation == _shareGeneration) {
        setState(() => _sharing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppFilledButton(
      label: S.of(context).referralShareInviteLink,
      autofocus: widget.autofocus && !_failed && !_sharing,
      state: _sharing
          ? FilledButtonState.loading
          : _failed
              ? FilledButtonState.error
              : FilledButtonState.idle,
      onPressed: _sharing ? null : _share,
    );
  }
}
