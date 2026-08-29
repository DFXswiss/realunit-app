import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';

/// Copies the personalised invite share text and shows «Kopiert» for 2s
/// after a successful clipboard write. A failed write keeps the copy label
/// in the error state for 2s and stays tappable. Copy is loading (not
/// tappable) while the write is in flight. A hung write is treated as a failure
/// after 2s so copy is not stuck (same as the landing copy control).
/// A second tap after Kopiert copies again and restarts the timer.
/// A new share text does not confirm or error a write that started on a
/// previous invite.
class ReferralCopyInviteButton extends StatefulWidget {
  final String text;

  const ReferralCopyInviteButton({super.key, required this.text});

  @override
  State<ReferralCopyInviteButton> createState() =>
      _ReferralCopyInviteButtonState();
}

class _ReferralCopyInviteButtonState extends State<ReferralCopyInviteButton> {
  Timer? _reset;
  bool _copied = false;
  bool _failed = false;
  bool _copying = false;

  @override
  void didUpdateWidget(ReferralCopyInviteButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text == widget.text ||
        (!_copied && !_failed && !_copying)) {
      return;
    }
    _reset?.cancel();
    _copied = false;
    _failed = false;
  }

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    if (_copying) return;
    setState(() {
      _copying = true;
      _failed = false;
      _copied = false;
    });
    final text = widget.text;
    try {
      await Clipboard.setData(ClipboardData(text: text)).timeout(
        const Duration(seconds: 2),
      );
      if (!mounted || widget.text != text) return;
      setState(() {
        _copied = true;
        _failed = false;
      });
      _reset?.cancel();
      _reset = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _copied = false);
      });
    } catch (_) {
      if (!mounted || widget.text != text) return;
      setState(() {
        _copied = false;
        _failed = true;
      });
      _reset?.cancel();
      _reset = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _failed = false);
      });
    } finally {
      if (mounted) {
        setState(() => _copying = false);
      } else {
        _copying = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final label = _copied ? s.referralCopied : s.referralCopyInviteLink;
    return Semantics(
      container: true,
      liveRegion: _copied,
      label: _copied ? '${s.referralCopied}. ${widget.text}' : null,
      child: AppFilledButton(
        label: label,
        variant: FilledButtonVariant.secondary,
        state: _copying
            ? FilledButtonState.loading
            : _copied
                ? FilledButtonState.success
                : _failed
                    ? FilledButtonState.error
                    : FilledButtonState.idle,
        onPressed: _copying ? null : _copy,
      ),
    );
  }
}
