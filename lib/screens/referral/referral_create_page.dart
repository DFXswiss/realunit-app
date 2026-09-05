import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/io/normalize_referral_code.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_referral_service.dart';
import 'package:realunit_wallet/screens/referral/cubit/referral_cubit.dart';
import 'package:realunit_wallet/screens/referral/referral_error_message.dart';
import 'package:realunit_wallet/screens/referral/referral_limits.dart';
import 'package:realunit_wallet/screens/referral/referral_share_text.dart';
import 'package:realunit_wallet/screens/referral/widgets/referral_copy_invite_button.dart';
import 'package:realunit_wallet/screens/referral/widgets/referral_loading_status.dart';
import 'package:realunit_wallet/screens/referral/widgets/referral_share_invite_button.dart';
import 'package:realunit_wallet/setup/di.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';
import 'package:realunit_wallet/widgets/form/labeled_text_field.dart';
import 'package:realunit_wallet/widgets/scrollable_actions_layout.dart';

class ReferralCreatePage extends StatelessWidget {
  const ReferralCreatePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) {
        final cubit = ReferralCubit(getIt<RealUnitReferralService>());
        // Seed create-ready after a summary load so guest-name submit can run.
        cubit.load().then((_) {
          if (!cubit.isClosed) cubit.openCreate();
        });
        return cubit;
      },
      child: const ReferralCreateView(),
    );
  }
}

class ReferralCreateView extends StatefulWidget {
  const ReferralCreateView({super.key});

  @override
  State<ReferralCreateView> createState() => _ReferralCreateViewState();
}

class _ReferralCreateViewState extends State<ReferralCreateView> {
  final _nameCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _submitting = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit(BuildContext context) async {
    if (_submitting) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final cubit = context.read<ReferralCubit>();
    final state = cubit.state;
    final canSubmit =
        state is ReferralCreateReady ||
        state is ReferralOverviewLoaded ||
        state is ReferralCreating;
    if (!canSubmit || state is ReferralCreating) return;
    final name = sanitizeReferralGuestName(_nameCtrl.text);
    if (_nameCtrl.text != name) {
      _nameCtrl.value = TextEditingValue(
        text: name,
        selection: TextSelection.collapsed(offset: name.length),
      );
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (state is ReferralOverviewLoaded) {
      cubit.openCreate();
    }
    setState(() => _submitting = true);
    try {
      await cubit.createInvite(guestName: name);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _shareText({
    required String guestName,
    required String url,
    required String? copyText,
    String? hostName,
  }) {
    return referralShareText(
      fromApi: copyText,
      guestName: guestName,
      url: url,
      hostName: hostName,
      fallback: S.of(context).referralShareText,
      fallbackNoName: S.of(context).referralShareTextNoName,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (!context.mounted) return;
        final created =
            context.read<ReferralCubit>().state is ReferralInviteCreated;
        Navigator.of(context).pop(created);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(s.referralCreateInvite)),
        body: SafeArea(
          child: BlocBuilder<ReferralCubit, ReferralState>(
            builder: (context, state) {
              if (state is ReferralLoading || state is ReferralInitial) {
                return const ReferralLoadingStatus();
              }

              if (state is ReferralNotEligible) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 16,
                      children: [
                        Semantics(
                          container: true,
                          liveRegion: true,
                          child: Text(
                            s.referralNotEligible,
                            textAlign: TextAlign.center,
                          ),
                        ),
                        AppFilledButton(
                          label: s.close,
                          autofocus: true,
                          onPressed: () => Navigator.of(context).pop(false),
                        ),
                      ],
                    ),
                  ),
                );
              }

              if (state is ReferralFailure || state is ReferralNeedsTerms) {
                final message = state is ReferralFailure
                    ? state.message
                    : (state as ReferralNeedsTerms).errorMessage;
                final localized = message != null && message.isNotEmpty
                    ? localizedReferralError(context, message)
                    : null;
                final text = localized ??
                    (state is ReferralNeedsTerms
                        ? s.referralTermsRequired
                        : null);
                final retrying =
                    (state is ReferralFailure && state.retrying) ||
                    (state is ReferralNeedsTerms && state.retrying);
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      spacing: 16,
                      children: [
                        if (text != null)
                          Semantics(
                            container: true,
                            liveRegion: true,
                            child: Text(
                              text,
                              textAlign: TextAlign.center,
                              style: message != null && message.isNotEmpty
                                  ? TextStyle(
                                      color: RealUnitColors.status.red600,
                                    )
                                  : null,
                            ),
                          ),
                        AppFilledButton(
                          label: s.retry,
                          autofocus: !retrying,
                          state: retrying
                              ? FilledButtonState.loading
                              : FilledButtonState.idle,
                          onPressed: retrying
                              ? null
                              : () {
                                  final cubit = context.read<ReferralCubit>();
                                  cubit.load().then((_) {
                                    if (!cubit.isClosed) cubit.openCreate();
                                  });
                                },
                        ),
                      ],
                    ),
                  ),
                );
              }

              if (state is ReferralInviteCreated) {
                final lang = Localizations.localeOf(context).languageCode;
                final text = _shareText(
                  guestName: state.invite.guestName,
                  url: state.invite.url,
                  copyText: state.invite.copyTextForLocale(lang),
                  hostName: state.invite.inviterName,
                );
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: ScrollableActionsLayout(
                    body: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: 16,
                      children: [
                        Text(
                          state.invite.guestName.trim().isEmpty
                              ? s.referralYourInvite
                              : s.referralYourInviteFor(
                                  state.invite.guestName.trim(),
                                ),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          s.referralInviteUrlLabel,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: RealUnitColors.neutral500,
                          ),
                        ),
                        SelectableText(
                          text,
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: RealUnitColors.realUnitBlue,
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      ReferralCopyInviteButton(text: text),
                      ReferralShareInviteButton(text: text, autofocus: true),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: AppFilledButton(
                          label: s.done,
                          variant: FilledButtonVariant.secondary,
                          onPressed: () => Navigator.of(context).pop(true),
                        ),
                      ),
                    ],
                  ),
                );
              }

              final creating = state is ReferralCreating || _submitting;
              final error = state is ReferralCreateReady
                  ? state.errorMessage
                  : state is ReferralCreating
                  ? state.errorMessage
                  : null;
              final canSubmit =
                  state is ReferralCreateReady ||
                  state is ReferralOverviewLoaded ||
                  state is ReferralCreating;

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ScrollableActionsLayout(
                  body: AutofillGroup(
                    onDisposeAction: AutofillContextAction.commit,
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 16,
                        children: [
                          Text(
                            s.referralCreateInviteDescription,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: RealUnitColors.neutral500,
                            ),
                          ),
                          LabeledTextField(
                            label: s.referralGuestName,
                            hintText: s.name,
                            controller: _nameCtrl,
                            enabled: !creating,
                            textCapitalization: TextCapitalization.words,
                            keyboardType: TextInputType.name,
                            autocorrect: true,
                            enableSuggestions: true,
                            hideErrorText: false,
                            autofocus: error == null || error.isEmpty,
                            autofillHints: const [
                              AutofillHints.givenName,
                              AutofillHints.name,
                            ],
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: creating
                                ? null
                                : (_) => _submit(context),
                            inputFormatters: [
                              FilteringTextInputFormatter.deny(
                                invisibleReferralChars,
                              ),
                              FilteringTextInputFormatter.deny(
                                referralGuestNameSpaceChars,
                                replacementString: ' ',
                              ),
                              LengthLimitingTextInputFormatter(
                                maxReferralGuestNameLength,
                              ),
                            ],
                            validator: (v) {
                              if (sanitizeReferralGuestName(v ?? '').isEmpty) {
                                return s.referralGuestNameRequired;
                              }
                              return null;
                            },
                          ),
                          if (creating && (error == null || error.isEmpty))
                            Semantics(
                              container: true,
                              liveRegion: true,
                              child: Row(
                                spacing: 8,
                                children: [
                                  const ExcludeSemantics(
                                    child: CupertinoActivityIndicator(),
                                  ),
                                  Expanded(
                                    child: Text(
                                      s.referralCreating,
                                      style: Theme.of(context).textTheme.bodySmall
                                          ?.copyWith(
                                            color: RealUnitColors.neutral500,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else if (error != null && error.isNotEmpty)
                            Semantics(
                              container: true,
                              liveRegion: true,
                              child: Text(
                                localizedReferralError(context, error),
                                style: TextStyle(
                                  color: RealUnitColors.status.red600,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  actions: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: AppFilledButton(
                        label: s.referralCreateInvite,
                        autofocus:
                            error != null && error.isNotEmpty && !creating,
                        state: creating
                            ? FilledButtonState.loading
                            : FilledButtonState.idle,
                        onPressed: !canSubmit || creating
                            ? null
                            : () => _submit(context),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
