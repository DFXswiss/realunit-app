import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_transfer_service.dart';
import 'package:realunit_wallet/screens/migrate_bitbox/cubits/migrate_bitbox/migrate_bitbox_cubit.dart';
import 'package:realunit_wallet/screens/send/cubits/send_process/send_process_cubit.dart';
import 'package:realunit_wallet/setup/di.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';
import 'package:realunit_wallet/widgets/scrollable_actions_layout.dart';

class MigrateTransferReadyView extends StatelessWidget {
  const MigrateTransferReadyView({
    super.key,
    required this.fromAddress,
    required this.toAddress,
    required this.amount,
  });

  final String fromAddress;
  final String toAddress;
  final int amount;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(S.of(context).migrateBitbox)),
    body: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SafeArea(
        child: ScrollableActionsLayout(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 16,
            children: [
              Text(
                S.of(context).migrateBitboxTransferTitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              Text(
                S.of(context).migrateBitboxTransferDescription,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: RealUnitColors.neutral500),
              ),
              _MigrateTransferInfoRow(
                label: S.of(context).from,
                value: _truncateAddress(fromAddress),
              ),
              _MigrateTransferInfoRow(
                label: S.of(context).to,
                value: _truncateAddress(toAddress),
              ),
              _MigrateTransferInfoRow(
                label: S.of(context).sendConfirmAmount,
                value: '$amount REALU',
              ),
            ],
          ),
          actions: [
            AppFilledButton(
              label: S.of(context).migrateBitboxTransferCta,
              onPressed: () => context.read<MigrateBitboxCubit>().startTransfer(),
            ),
          ],
        ),
      ),
    ),
  );
}

class MigrateTransferringView extends StatelessWidget {
  const MigrateTransferringView({
    super.key,
    required this.toAddress,
    required this.amount,
  });

  final String toAddress;
  final int amount;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => SendProcessCubit(
      transferService: getIt<RealUnitTransferService>(),
      appStore: getIt<AppStore>(),
      recipient: toAddress,
      amount: amount,
    )..start(),
    child: Scaffold(
      appBar: AppBar(title: Text(S.of(context).migrateBitbox)),
      body: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: SafeArea(child: _EmbeddedSendProcessView()),
      ),
    ),
  );
}

class _EmbeddedSendProcessView extends StatelessWidget {
  const _EmbeddedSendProcessView();

  @override
  Widget build(BuildContext context) => BlocConsumer<SendProcessCubit, SendProcessState>(
    listenWhen: (_, current) => switch (current) {
      SendProcessSuccess() || SendProcessFailure(canRetry: false) => true,
      _ => false,
    },
    listener: (context, state) {
      if (state is SendProcessSuccess) {
        context.read<MigrateBitboxCubit>().finishMigration();
      }
      if (state case SendProcessFailure(:final reason, canRetry: false)) {
        context.read<MigrateBitboxCubit>().onTransferFailedTerminally(
          _failureMessage(context, reason),
        );
      }
    },
    builder: (context, state) => switch (state) {
      SendProcessInitial() || SendProcessPreparing() => _progressLayout(
        context,
        S.of(context).sendPreparing,
      ),
      SendProcessSigning() => _progressLayout(context, S.of(context).sendSigning),
      SendProcessFailure(:final reason, :final canRetry) => ScrollableActionsLayout(
        centerBody: true,
        body: Column(
          spacing: 16,
          children: [
            Icon(
              Icons.error_rounded,
              size: 64,
              color: RealUnitColors.status.red600,
            ),
            Text(
              _failureMessage(context, reason),
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: RealUnitColors.neutral500),
            ),
          ],
        ),
        actions: [
          AppFilledButton(
            label: S.of(context).retry,
            onPressed: canRetry
                ? () => context.read<SendProcessCubit>().retryConfirm()
                : null,
          ),
        ],
      ),
      SendProcessSuccess() => _progressLayout(context, S.of(context).sendPreparing),
    },
  );

  Widget _progressLayout(BuildContext context, String label) => ScrollableActionsLayout(
    centerBody: true,
    body: Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 16,
      children: [
        const CupertinoActivityIndicator(radius: 16),
        Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ],
    ),
  );

  String _failureMessage(BuildContext context, SendProcessFailureReason reason) => switch (reason) {
    SendProcessFailureReason.signatureUnsupported => S.of(context).sendFailureSignatureUnsupported,
    SendProcessFailureReason.signatureCancelled => S.of(context).sendFailureSignatureCancelled,
    SendProcessFailureReason.gasFundingUnavailable => S.of(context).sendFailureGasUnavailable,
    SendProcessFailureReason.invalidRequest => S.of(context).sendFailureInvalidRequest,
    SendProcessFailureReason.registrationOrKycRequired =>
      S.of(context).sendFailureRegistrationOrKycRequired,
    SendProcessFailureReason.confirmMismatch => S.of(context).sendFailureConfirmMismatch,
    SendProcessFailureReason.generic => S.of(context).sendFailureGeneric,
  };
}

class _MigrateTransferInfoRow extends StatelessWidget {
  const _MigrateTransferInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 16,
    children: [
      Flexible(
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: RealUnitColors.neutral500),
        ),
      ),
      Flexible(
        child: Text(
          value,
          textAlign: TextAlign.end,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    ],
  );
}

String _truncateAddress(String address) {
  if (address.length <= 12) return address;
  return '${address.substring(0, 6)}…${address.substring(address.length - 4)}';
}
