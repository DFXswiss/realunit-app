import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_invite_dto.dart';
import 'package:realunit_wallet/screens/referral/cubit/referral_cubit.dart';
import 'package:realunit_wallet/screens/referral/referral_error_message.dart';
import 'package:realunit_wallet/screens/referral/open_referral_create.dart';
import 'package:realunit_wallet/screens/referral/open_referral_terms.dart';
import 'package:realunit_wallet/screens/referral/referral_share_text.dart';
import 'package:realunit_wallet/screens/referral/widgets/referral_copy_invite_button.dart';
import 'package:realunit_wallet/screens/referral/widgets/referral_share_invite_button.dart';
import 'package:realunit_wallet/screens/referral/widgets/referral_loading_status.dart';
import 'package:realunit_wallet/screens/settings/bloc/settings_bloc.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';
import 'package:realunit_wallet/widgets/scrollable_actions_layout.dart';

class ReferralOverviewPage extends StatelessWidget {
  const ReferralOverviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Tooltip(
          message: s.referralTermsTitle,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => openReferralTerms(context),
            child: Semantics(
              button: true,
              label: s.referralTermsTitle,
              excludeSemantics: true,
              child: Text(s.referralOverviewTitle),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: BlocBuilder<ReferralCubit, ReferralState>(
          builder: (context, state) {
            if (state is ReferralLoading || state is ReferralInitial) {
              return const ReferralLoadingStatus();
            }
            if (state is ReferralFailure) {
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
                          localizedReferralError(context, state.message),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: RealUnitColors.status.red600),
                        ),
                      ),
                      AppFilledButton(
                        label: s.retry,
                        autofocus: !state.retrying,
                        state: state.retrying
                            ? FilledButtonState.loading
                            : FilledButtonState.idle,
                        onPressed: state.retrying
                            ? null
                            : () => context.read<ReferralCubit>().load(),
                      ),
                    ],
                  ),
                ),
              );
            }
            if (state is! ReferralOverviewLoaded) {
              return const SizedBox.shrink();
            }

            final summary = state.summary;
            final openInvites = state.invites
                .where((invite) => invite.isOpen)
                .toList();
            final listError =
                state.invitesError != null && state.invitesError!.isNotEmpty;
            final showListRetry =
                listError ||
                (summary.openCount > 0 && openInvites.isEmpty);
            final chfFormat = NumberFormat.currency(
              locale: 'de_CH',
              symbol: 'CHF',
            );

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ScrollableActionsLayout(
                body: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 20,
                  children: [
                    BlocBuilder<SettingsBloc, SettingsState>(
                      builder: (context, settings) {
                        final chf = settings.hideAmounts
                            ? '***.**'
                            : chfFormat.format(summary.tileChf);
                        return _TotalReceivedTile(
                          realu: summary.realuSum,
                          hideAmounts: settings.hideAmounts,
                          chfLabel: s.referralChfAtSharePrice(
                            chf,
                            summary.tileSharePriceLabel ?? s.referralSharePrice,
                          ),
                          title: s.referralTotalReceived,
                        );
                      },
                    ),
                    Row(
                      spacing: 12,
                      children: [
                        Expanded(
                          child: _CountTile(
                            label: s.referralStatusOpen,
                            count: summary.openCount,
                          ),
                        ),
                        Expanded(
                          child: _CountTile(
                            label: s.referralStatusCredited,
                            count: summary.creditedCount,
                          ),
                        ),
                      ],
                    ),
                    for (final invite in openInvites)
                      _OpenInviteTile(
                        key: ValueKey('${invite.id}:${invite.code}'),
                        invite: invite,
                      ),
                    if (state.invitesLoading && !listError)
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
                                s.referralInvitesLoading,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: RealUnitColors.neutral500),
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (listError)
                      Semantics(
                        container: true,
                        liveRegion: true,
                        child: Text(
                          localizedReferralError(context, state.invitesError!),
                          style: TextStyle(color: RealUnitColors.status.red600),
                        ),
                      ),
                    if (showListRetry)
                      AppFilledButton(
                        label: s.retry,
                        autofocus: openInvites.isEmpty && !state.invitesLoading,
                        variant: FilledButtonVariant.secondary,
                        state: state.invitesLoading
                            ? FilledButtonState.loading
                            : FilledButtonState.idle,
                        onPressed: state.invitesLoading
                            ? null
                            : () => context.read<ReferralCubit>().reloadInvites(),
                      ),
                    Text(
                      s.referralOpenInvitesExpire,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: RealUnitColors.neutral500,
                      ),
                    ),
                    Text(
                      s.referralOverviewHint,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: RealUnitColors.neutral500,
                      ),
                    ),
                  ],
                ),
                actions: [
                  _CreateInviteAction(
                    autofocus:
                        openInvites.isEmpty &&
                        !showListRetry &&
                        !state.invitesLoading,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CreateInviteAction extends StatefulWidget {
  final bool autofocus;

  const _CreateInviteAction({required this.autofocus});

  @override
  State<_CreateInviteAction> createState() => _CreateInviteActionState();
}

class _CreateInviteActionState extends State<_CreateInviteAction> {
  bool _opening = false;

  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await openReferralCreateAndRefresh(context);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: AppFilledButton(
        label: S.of(context).referralCreateInvite,
        autofocus: widget.autofocus && !_opening,
        state: _opening ? FilledButtonState.loading : FilledButtonState.idle,
        onPressed: _opening ? null : _open,
      ),
    );
  }
}

class _TotalReceivedTile extends StatelessWidget {
  final num realu;
  final bool hideAmounts;
  final String chfLabel;
  final String title;

  const _TotalReceivedTile({
    required this.realu,
    required this.hideAmounts,
    required this.chfLabel,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final realuLabel = hideAmounts
        ? '*** REALU'
        : '${realu.truncate()} REALU';
    return Semantics(
      container: true,
      label: '$title. $realuLabel. $chfLabel',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: RealUnitColors.brand700,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 4,
            children: [
              Text(
                title.toUpperCase(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: RealUnitColors.realUnitBlue,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                realuLabel,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                chfLabel,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: RealUnitColors.neutral500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OpenInviteTile extends StatelessWidget {
  final ReferralInviteDto invite;

  const _OpenInviteTile({super.key, required this.invite});

  String _shareText(BuildContext context) {
    final lang = Localizations.localeOf(context).languageCode;
    return referralShareText(
      fromApi: invite.copyTextForLocale(lang),
      guestName: invite.guestName,
      url: invite.url,
      hostName: invite.inviterName,
      fallback: S.of(context).referralShareText,
      fallbackNoName: S.of(context).referralShareTextNoName,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: RealUnitColors.neutral200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          Text(
            invite.guestName.trim().isEmpty
                ? s.referralYourInvite
                : s.referralYourInviteFor(invite.guestName.trim()),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            s.referralInviteUrlLabel,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: RealUnitColors.neutral500,
            ),
          ),
          SelectableText(
            _shareText(context),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: RealUnitColors.realUnitBlue,
            ),
          ),
          ReferralCopyInviteButton(text: _shareText(context)),
          ReferralShareInviteButton(text: _shareText(context)),
        ],
      ),
    );
  }
}

class _CountTile extends StatelessWidget {
  final String label;
  final int count;

  const _CountTile({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '$count $label',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: RealUnitColors.neutral200),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 4,
            children: [
              Text(
                '$count',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: RealUnitColors.neutral500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
