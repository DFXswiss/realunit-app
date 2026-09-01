import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_referral_service.dart';
import 'package:realunit_wallet/screens/referral/cubit/referral_cubit.dart';
import 'package:realunit_wallet/setup/di.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';
import 'package:realunit_wallet/widgets/form/labeled_text_field.dart';
import 'package:realunit_wallet/widgets/scrollable_actions_layout.dart';
import 'package:share_plus/share_plus.dart';

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

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  String _shareText({
    required String guestName,
    required String url,
    required String? copyText,
  }) {
    final s = S.of(context);
    final hostName = 'RealUnit';
    return s.referralShareText(guestName, hostName, url).isNotEmpty
        ? s.referralShareText(guestName, hostName, url)
        : (copyText ?? url);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.referralCreateInvite)),
      body: SafeArea(
        child: BlocBuilder<ReferralCubit, ReferralState>(
          builder: (context, state) {
            if (state is ReferralLoading || state is ReferralInitial) {
              return const Center(child: CircularProgressIndicator());
            }

            if (state is ReferralInviteCreated) {
              final text = _shareText(
                guestName: state.invite.guestName,
                url: state.invite.url,
                copyText: state.invite.copyText,
              );
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ScrollableActionsLayout(
                  body: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 16,
                    children: [
                      Text(
                        s.referralInviteUrlLabel,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      SelectableText(
                        state.invite.url,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: RealUnitColors.realUnitBlue,
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    AppFilledButton(
                      label: s.referralCopyInviteLink,
                      variant: FilledButtonVariant.secondary,
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: state.invite.url),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(s.copyClipboard)),
                          );
                        }
                      },
                    ),
                    AppFilledButton(
                      label: s.referralShareInviteLink,
                      onPressed: () => Share.share(text),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: AppFilledButton(
                        label: s.done,
                        variant: FilledButtonVariant.secondary,
                        onPressed: () => context.pop(true),
                      ),
                    ),
                  ],
                ),
              );
            }

            final creating = state is ReferralCreating;
            final error = state is ReferralCreateReady
                ? state.errorMessage
                : null;
            final canSubmit =
                state is ReferralCreateReady ||
                state is ReferralOverviewLoaded ||
                state is ReferralCreating;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ScrollableActionsLayout(
                body: Form(
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
                        textCapitalization: TextCapitalization.words,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return '';
                          return null;
                        },
                      ),
                      if (error != null && error.isNotEmpty)
                        Text(
                          error,
                          style: TextStyle(color: RealUnitColors.status.red600),
                        ),
                    ],
                  ),
                ),
                actions: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: AppFilledButton(
                      label: s.referralCreateInvite,
                      state: creating
                          ? FilledButtonState.loading
                          : FilledButtonState.idle,
                      onPressed: !canSubmit || creating
                          ? null
                          : () {
                              FocusManager.instance.primaryFocus?.unfocus();
                              if (_formKey.currentState?.validate() ?? false) {
                                final cubit = context.read<ReferralCubit>();
                                if (cubit.state is ReferralOverviewLoaded) {
                                  cubit.openCreate();
                                }
                                cubit.createInvite(
                                  guestName: _nameCtrl.text.trim(),
                                );
                              }
                            },
                    ),
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
