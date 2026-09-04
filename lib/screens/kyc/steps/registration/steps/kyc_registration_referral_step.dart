import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_code_lookup_dto.dart';
import 'package:realunit_wallet/screens/kyc/steps/registration/cubits/registration_step/kyc_registration_step_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/registration/widgets/referral_code_field.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';
import 'package:realunit_wallet/widgets/buttons/app_text_button.dart';
import 'package:realunit_wallet/widgets/scrollable_actions_layout.dart';

/// Optional invite/promo code step (Bilddokumentation Entwurf 4).
/// Skip advances without requiring a code; the same field is used for both.
class KycRegistrationReferralStep extends StatefulWidget {
  final TextEditingController referralCodeCtrl;

  /// Injected in tests. Production lookup goes through [ReferralCodeField].
  final Future<ReferralCodeLookupDto> Function(String code)? lookup;

  final ValueChanged<String?>? onResolved;

  /// Injected in tests. Production reads the clipboard in [ReferralCodeField].
  final Future<String?> Function()? readClipboard;

  /// Injected in tests. Production peeks the deeplink stash.
  final Future<String?> Function()? pendingCode;

  /// Production auto-pastes a landing copy when the field is empty.
  final bool autoPasteOnEmpty;

  const KycRegistrationReferralStep({
    super.key,
    required this.referralCodeCtrl,
    this.lookup,
    this.onResolved,
    this.readClipboard,
    this.pendingCode,
    this.autoPasteOnEmpty = false,
  });

  @override
  State<KycRegistrationReferralStep> createState() => _KycRegistrationReferralStepState();
}

class _KycRegistrationReferralStepState extends State<KycRegistrationReferralStep> {
  final _fieldKey = GlobalKey<ReferralCodeFieldState>();
  bool _advancing = false;
  bool _skipping = false;
  int _advanceGeneration = 0;

  Future<void> _advance(BuildContext context, {required bool skip}) async {
    if (_skipping) return;
    if (_advancing && !skip) return;
    final generation = ++_advanceGeneration;
    setState(() {
      _advancing = true;
      _skipping = skip;
    });
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      if (skip) {
        _fieldKey.currentState?.dismissPromoDialog();
        widget.referralCodeCtrl.clear();
        // Drop a looked-up typed code immediately so KYC submit cannot stash
        // it after Skip. A deeplink stash is left in place (null resolved).
        // Also discard an in-flight paste/lookup so a late clipboard write
        // or GET cannot restash after Überspringen — including when Next
        // is still awaiting that lookup.
        _fieldKey.currentState?.abandonLookup();
        widget.onResolved?.call(null);
      } else {
        // Await paste then lookup so a spent 4xx code is not stashed after
        // Next disposes the field (in-flight lookup would not call
        // onResolved(null)).
        await _fieldKey.currentState?.commitLookup();
      }
      if (generation != _advanceGeneration) return;
      if (!context.mounted) return;
      context.read<KycRegistrationStepCubit>().next();
    } finally {
      if (mounted && generation == _advanceGeneration) {
        setState(() {
          _advancing = false;
          _skipping = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return SafeArea(
      child: ScrollableActionsLayout(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        body: ReferralCodeField(
          key: _fieldKey,
          controller: widget.referralCodeCtrl,
          lookup: widget.lookup,
          showHeading: false,
          onResolved: widget.onResolved,
          readClipboard: widget.readClipboard,
          pendingCode: widget.pendingCode,
          autoPasteOnEmpty: widget.autoPasteOnEmpty,
          autofocus: true,
          enabled: !_advancing,
        ),
        actions: [
          AppFilledButton(
            label: s.next,
            state: _advancing && !_skipping ? FilledButtonState.loading : FilledButtonState.idle,
            onPressed: _advancing ? null : () => _advance(context, skip: false),
          ),
          AppTextButton(
            label: s.skip,
            onPressed: _skipping ? null : () => _advance(context, skip: true),
          ),
        ],
      ),
    );
  }
}
