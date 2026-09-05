import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/io/normalize_referral_code.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_code_lookup_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_referral_service.dart';
import 'package:realunit_wallet/packages/service/dfx/referral_lookup_status.dart';
import 'package:realunit_wallet/screens/referral/referral_error_message.dart';
import 'package:realunit_wallet/setup/di.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';
import 'package:realunit_wallet/widgets/form/labeled_text_field.dart';

/// Optional invite/promo code on registration. Looks up the public code
/// route (including a pasted `realunit.app/invite/…` URL) and shows the
/// invite recognition copy or the promo campaign dialog.
class ReferralCodeField extends StatefulWidget {
  final TextEditingController controller;

  /// Injected in tests. Production uses [RealUnitReferralService.lookupCode].
  final Future<ReferralCodeLookupDto> Function(String code)? lookup;

  /// When false, the surrounding page already shows the heading (AppBar).
  final bool showHeading;

  /// Normalized code after lookup: set on success / in-flight text, `null`
  /// when empty or the code is invalid/spent so KYC submit will not overwrite
  /// a deeplink stash.
  final ValueChanged<String?>? onResolved;

  /// Injected in tests. Production reads [Clipboard.getData].
  final Future<String?> Function()? readClipboard;

  /// KYC sets this so a copied landing code can be pasted immediately.
  final bool autofocus;

  /// False while KYC Next/Skip is in flight so the resolved code cannot
  /// change. An in-flight paste that finishes while locked is discarded.
  final bool enabled;

  /// When true and the field is empty, hydrate from [pendingCode] then the
  /// clipboard (iOS has no Play referrer; Offerte Punkt 3 Code-Eingabe).
  final bool autoPasteOnEmpty;

  /// Deeplink stash. Wins over clipboard auto-paste. Production is
  /// [peekPendingReferralCode].
  final Future<String?> Function()? pendingCode;

  const ReferralCodeField({
    super.key,
    required this.controller,
    this.lookup,
    this.showHeading = true,
    this.onResolved,
    this.readClipboard,
    this.autofocus = false,
    this.enabled = true,
    this.autoPasteOnEmpty = false,
    this.pendingCode,
  });

  @override
  State<ReferralCodeField> createState() => ReferralCodeFieldState();
}

class ReferralCodeFieldState extends State<ReferralCodeField> {
  Timer? _debounce;
  ReferralCodeLookupDto? _result;
  bool _invalid = false;
  String? _invalidMessage;
  bool _unavailable = false;
  bool _loading = false;
  String? _shownPromoFor;
  bool _promoDialogOpen = false;
  bool _pasting = false;

  /// Bumped on every lookup so a slower earlier GET cannot overwrite a
  /// later result for the same code (Done / paste / Retry while in flight).
  int _lookupGeneration = 0;
  Future<void>? _inFlightLookup;
  String? _inFlightCode;

  /// Code the current terminal result (_result / _invalid / _unavailable)
  /// belongs to, so Next does not fire a second GET for the same code.
  String? _resolvedCode;

  /// Bumped by [abandonLookup] so a clipboard read that was already in
  /// flight cannot write the field after Skip.
  int _inputGeneration = 0;
  Future<void>? _inFlightPaste;
  Timer? _clipboardTimeout;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    unawaited(_hydrateFromPendingOrClipboard());
  }

  /// Existing text > deeplink stash > landing clipboard. Never overwrites
  /// a code the user or a stash already put in the field.
  Future<void> _hydrateFromPendingOrClipboard() async {
    if (referralCodeFromInput(widget.controller.text) != null) {
      _scheduleLookup();
      return;
    }
    if (widget.pendingCode != null) {
      try {
        final pending = await widget.pendingCode!();
        if (!mounted) return;
        if (referralCodeFromInput(widget.controller.text) != null) {
          _scheduleLookup();
          return;
        }
        if (pending != null && pending.isNotEmpty && widget.enabled) {
          final next = referralPasteFieldText(pending) ?? referralCodeFromInput(pending);
          if (next != null && next.isNotEmpty) {
            widget.controller.value = TextEditingValue(
              text: next,
              selection: TextSelection.collapsed(offset: next.length),
            );
            await _runLookup();
            return;
          }
        }
      } catch (_) {}
    }
    if (!mounted) return;
    if (referralCodeFromInput(widget.controller.text) != null) {
      _scheduleLookup();
      return;
    }
    if (widget.autoPasteOnEmpty && widget.enabled) {
      await _pasteFromClipboard(onlyIfEmpty: true);
    }
  }

  @override
  void didUpdateWidget(ReferralCodeField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
    if (!widget.enabled) {
      _debounce?.cancel();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _clipboardTimeout?.cancel();
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  Future<T?> _readWithTimeout<T>(Future<T?> future, Duration duration) {
    final done = Completer<T?>();
    _clipboardTimeout?.cancel();
    _clipboardTimeout = Timer(duration, () {
      if (!done.isCompleted) done.complete(null);
    });
    future.then(
      (value) {
        _clipboardTimeout?.cancel();
        if (!done.isCompleted) done.complete(value);
      },
      onError: (Object _, StackTrace _) {
        _clipboardTimeout?.cancel();
        if (!done.isCompleted) done.complete(null);
      },
    );
    return done.future;
  }

  void _onControllerChanged() {
    if (!widget.enabled) {
      _debounce?.cancel();
      return;
    }
    _scheduleLookup();
  }

  void _scheduleLookup() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _runLookup);
  }

  Future<void> _pasteFromClipboard({bool onlyIfEmpty = false}) {
    if (_pasting || !widget.enabled) return Future<void>.value();
    setState(() => _pasting = true);
    final generation = _inputGeneration;
    final future = _pasteBody(generation, onlyIfEmpty: onlyIfEmpty);
    _inFlightPaste = future;
    return future.whenComplete(() {
      if (identical(_inFlightPaste, future)) {
        _inFlightPaste = null;
      }
    });
  }

  Future<void> _pasteBody(int generation, {bool onlyIfEmpty = false}) async {
    String? raw;
    try {
      const timeout = Duration(seconds: 2);
      raw = widget.readClipboard != null
          ? await _readWithTimeout(widget.readClipboard!(), timeout)
          : (await _readWithTimeout(
              Clipboard.getData(Clipboard.kTextPlain),
              timeout,
            ))?.text;
    } catch (_) {
      return;
    } finally {
      if (mounted) {
        setState(() => _pasting = false);
      } else {
        _pasting = false;
      }
    }
    if (!mounted || raw == null) return;
    if (generation != _inputGeneration || !widget.enabled) return;
    if (onlyIfEmpty && referralCodeFromInput(widget.controller.text) != null) {
      return;
    }
    final next = referralPasteFieldText(raw);
    if (next == null || next.isEmpty) return;
    widget.controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    _debounce?.cancel();
    final inFlight = _inFlightLookup;
    if (inFlight != null && next == _inFlightCode) {
      await inFlight;
      return;
    }
    await _runLookup();
  }

  void _lookupNow() {
    if (_loading) {
      final code = referralCodeFromInput(widget.controller.text);
      if (code != null && code == _inFlightCode) return;
    }
    _debounce?.cancel();
    unawaited(_runLookup());
  }

  /// Finish an in-flight debounce so Next can stash only after lookup.
  /// Joins an in-flight GET of the same code instead of stacking another.
  /// Awaits an in-flight paste first so Next does not skip a clipboard
  /// that was already being read.
  Future<void> commitLookup() async {
    _debounce?.cancel();
    final paste = _inFlightPaste;
    if (paste != null) await paste;
    if (!mounted) return;
    final inFlight = _inFlightLookup;
    final code = referralCodeFromInput(widget.controller.text);
    if (inFlight != null && code != null && code == _inFlightCode) {
      await inFlight;
      return;
    }
    if (code != null &&
        !_loading &&
        code == _resolvedCode &&
        (_result != null || _invalid || _unavailable)) {
      return;
    }
    await _runLookup();
  }

  /// Drop an in-flight paste or lookup so Skip cannot stash a late result.
  void abandonLookup() {
    _debounce?.cancel();
    _clipboardTimeout?.cancel();
    _lookupGeneration++;
    _inputGeneration++;
    _inFlightLookup = null;
    _inFlightCode = null;
    _resolvedCode = null;
    if (!mounted) return;
    setState(() {
      _result = null;
      _invalid = false;
      _invalidMessage = null;
      _unavailable = false;
      _loading = false;
    });
  }

  /// Close the campaign dialog so Skip does not leave it over the next step.
  void dismissPromoDialog() {
    if (!_promoDialogOpen || !mounted) return;
    Navigator.of(context).pop();
  }

  /// Replace a pasted invite/promo URL with the extracted code so the field
  /// shows what will be looked up and bound.
  void _syncFieldToExtractedCode(String code) {
    if (widget.controller.text == code) return;
    widget.controller.removeListener(_onControllerChanged);
    widget.controller.value = TextEditingValue(
      text: code,
      selection: TextSelection.collapsed(offset: code.length),
    );
    widget.controller.addListener(_onControllerChanged);
  }

  Future<ReferralCodeLookupDto?> _lookup(String code) async {
    final Future<ReferralCodeLookupDto?> future;
    if (widget.lookup != null) {
      future = widget.lookup!(code);
    } else if (getIt.isRegistered<RealUnitReferralService>()) {
      future = getIt<RealUnitReferralService>().lookupCode(code);
    } else {
      return null;
    }
    return future.timeout(RealUnitReferralService.lookupTimeout);
  }

  bool _isCurrentLookup(int generation, String code) {
    return mounted &&
        generation == _lookupGeneration &&
        referralCodeFromInput(widget.controller.text) == code;
  }

  Future<void> _runLookup() {
    final future = _runLookupBody();
    _inFlightLookup = future;
    return future.whenComplete(() {
      if (identical(_inFlightLookup, future)) {
        _inFlightLookup = null;
        _inFlightCode = null;
      }
    });
  }

  Future<void> _runLookupBody() async {
    final generation = ++_lookupGeneration;
    final code = referralCodeFromInput(widget.controller.text);
    if (code == null) {
      _inFlightCode = null;
      _resolvedCode = null;
      widget.onResolved?.call(null);
      if (mounted) {
        setState(() {
          _result = null;
          _invalid = false;
          _invalidMessage = null;
          _unavailable = false;
          _loading = false;
        });
      }
      return;
    }

    _inFlightCode = code;
    _syncFieldToExtractedCode(code);
    widget.onResolved?.call(code);
    if (mounted) {
      setState(() {
        _loading = true;
        _result = null;
        _invalid = false;
        _invalidMessage = null;
        if (code != _resolvedCode) {
          _unavailable = false;
        }
      });
    }
    try {
      final result = await _lookup(code);
      if (!_isCurrentLookup(generation, code)) return;
      setState(() {
        _result = result;
        _invalid = false;
        _invalidMessage = null;
        _unavailable = result == null;
        _loading = false;
      });
      _resolvedCode = code;
      widget.onResolved?.call(code);
      if (result != null && result.isPromo) {
        if (!_isCurrentLookup(generation, code)) return;
        await _maybeShowPromo(code, result);
      }
    } on ApiException catch (error) {
      if (!_isCurrentLookup(generation, code)) return;
      final invalid = isReferralLookupInvalid(error);
      setState(() {
        _result = null;
        _invalid = invalid;
        _invalidMessage = invalid ? referralErrorMessage(error) : null;
        _unavailable = !invalid;
        _loading = false;
      });
      _resolvedCode = code;
      widget.onResolved?.call(invalid ? null : code);
    } catch (_) {
      if (!_isCurrentLookup(generation, code)) return;
      setState(() {
        _result = null;
        _invalid = false;
        _invalidMessage = null;
        _unavailable = true;
        _loading = false;
      });
      _resolvedCode = code;
      widget.onResolved?.call(code);
    }
  }

  Future<void> _maybeShowPromo(
    String code,
    ReferralCodeLookupDto result,
  ) async {
    if (!mounted) return;
    if (referralCodeFromInput(widget.controller.text) != code) return;
    if (_shownPromoFor == code) return;
    final lang = Localizations.localeOf(context).languageCode;
    final text = result.campaignTextForLocale(lang);
    if (text == null || text.isEmpty) return;
    if (!mounted) return;
    if (referralCodeFromInput(widget.controller.text) != code) return;
    final textLang = result.campaignTextLang(lang);
    final s = S.of(context);
    _shownPromoFor = code;
    _promoDialogOpen = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: Text(s.referralPromoTitle),
          content: SingleChildScrollView(
            child: Text(text, locale: Locale(textLang)),
          ),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(s.close),
            ),
          ],
        ),
      );
    } finally {
      _promoDialogOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final inviter = _result?.displayInviterName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        if (widget.showHeading)
          Text(
            s.referralCodeHeading,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        Text(
          s.referralCodeDescription,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: RealUnitColors.neutral500,
          ),
        ),
        LabeledTextField(
          label: s.referralCodeOptional,
          hintText: s.referralCodeHint,
          controller: widget.controller,
          onTap: () {
            final text = widget.controller.text;
            if (text.isEmpty) return;
            widget.controller.selection = TextSelection(
              baseOffset: 0,
              extentOffset: text.length,
            );
          },
          textCapitalization: TextCapitalization.characters,
          smartDashesType: SmartDashesType.disabled,
          smartQuotesType: SmartQuotesType.disabled,
          spellCheckConfiguration: const SpellCheckConfiguration.disabled(),
          enableIMEPersonalizedLearning: false,
          autofocus: widget.autofocus,
          enabled: widget.enabled,
          autofillHints: const <String>[],
          textInputAction: TextInputAction.done,
          onFieldSubmitted: widget.enabled ? (_) => _lookupNow() : null,
          inputFormatters: [
            FilteringTextInputFormatter.deny(invisibleReferralChars),
            FilteringTextInputFormatter.deny(
              RegExp(r'\s+'),
              replacementString: '',
            ),
            // Room for a pasted invite URL; the extracted code is still 32.
            LengthLimitingTextInputFormatter(1024),
          ],
          suffixIcon: widget.enabled
              ? IconButton(
                  icon: const Icon(Icons.paste_rounded),
                  tooltip: s.sendPaste,
                  onPressed: _pasting ? null : _pasteFromClipboard,
                )
              : null,
        ),
        if (_loading && !_unavailable)
          Semantics(
            container: true,
            liveRegion: true,
            child: Row(
              spacing: 8,
              children: [
                const ExcludeSemantics(child: CupertinoActivityIndicator()),
                Text(
                  s.referralCodeChecking,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: RealUnitColors.neutral500,
                  ),
                ),
              ],
            ),
          ),
        if (!_loading && _invalid)
          Semantics(
            container: true,
            liveRegion: true,
            child: Text(
              localizedReferralError(
                context,
                _invalidMessage ?? referralInvalidMessage,
              ),
              style: TextStyle(color: RealUnitColors.status.red600),
            ),
          ),
        if (_unavailable) ...[
          Semantics(
            container: true,
            liveRegion: true,
            child: Text(
              s.referralCodeUnavailable,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: RealUnitColors.neutral500,
              ),
            ),
          ),
          if (widget.enabled)
            AppFilledButton(
              label: s.retry,
              variant: FilledButtonVariant.secondary,
              state: _loading ? FilledButtonState.loading : FilledButtonState.idle,
              onPressed: _loading ? null : _lookupNow,
            ),
        ],
        if (!_loading && _result != null && _result!.isInvite && inviter != null)
          Semantics(
            container: true,
            liveRegion: true,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: RealUnitColors.brand700,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                s.referralInviteRecognized(inviter),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: RealUnitColors.darkBlue,
                ),
              ),
            ),
          ),
        if (!_loading && _result != null && _result!.isPromo)
          Builder(
            builder: (context) {
              final lang = Localizations.localeOf(context).languageCode;
              final text = _result!.campaignTextForLocale(lang);
              if (text == null || text.isEmpty) return const SizedBox.shrink();
              return Semantics(
                container: true,
                liveRegion: true,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: RealUnitColors.brand700,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    text,
                    locale: Locale(_result!.campaignTextLang(lang)),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: RealUnitColors.darkBlue,
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}
