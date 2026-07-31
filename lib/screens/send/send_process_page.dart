import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_transfer_service.dart';
import 'package:realunit_wallet/screens/send/cubits/send_process/send_process_cubit.dart';
import 'package:realunit_wallet/setup/di.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/scrollable_actions_layout.dart';

/// Final step: prepare → sign (EIP-712 delegation + EIP-7702 authorization) →
/// confirm, then render the txHash success or a typed failure. The cubit drives
/// every outcome as a state — no error-string parsing in the view.
class SendProcessPage extends StatelessWidget {
  final String recipient;
  final int amount;

  const SendProcessPage({super.key, required this.recipient, required this.amount});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => SendProcessCubit(
        transferService: getIt<RealUnitTransferService>(),
        appStore: getIt<AppStore>(),
        recipient: recipient,
        amount: amount,
      )..start(),
      child: const SendProcessView(),
    );
  }
}

class SendProcessView extends StatelessWidget {
  const SendProcessView({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<SendProcessCubit, SendProcessState>(
      listenWhen: (previous, current) =>
          current is SendProcessSuccess || current is SendProcessFailure,
      listener: (context, state) async {
        if (state is SendProcessSuccess) {
          await _showResultSheet(
            context,
            icon: Icons.check_circle_rounded,
            title: S.of(context).sendSuccess,
            description: S.of(context).sendSuccessDescription,
          );
        } else if (state is SendProcessFailure) {
          await _showResultSheet(
            context,
            icon: Icons.error_rounded,
            title: S.of(context).sendFailureTitle,
            description: _failureMessage(context, state),
            canRetry: state.canRetry,
          );
        }
      },
      builder: (context, state) {
        final canPop = state is SendProcessSuccess;
        return PopScope(
          canPop: canPop,
          child: Scaffold(
            appBar: AppBar(title: Text(S.of(context).sendProcessTitle)),
            body: SafeArea(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 24,
                  children: [
                    const CupertinoActivityIndicator(radius: 16),
                    Text(
                      _progressLabel(context, state),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _progressLabel(BuildContext context, SendProcessState state) => switch (state) {
    SendProcessInitial() || SendProcessPreparing() => S.of(context).sendPreparing,
    SendProcessSigning() => S.of(context).sendSigning,
    SendProcessSuccess() => S.of(context).sendSuccess,
    SendProcessFailure() => S.of(context).sendFailureTitle,
  };

  String _failureMessage(BuildContext context, SendProcessFailure state) => switch (state.reason) {
    SendProcessFailureReason.signatureUnsupported => S.of(context).sendFailureSignatureUnsupported,
    SendProcessFailureReason.signatureCancelled => S.of(context).sendFailureSignatureCancelled,
    SendProcessFailureReason.gasFundingUnavailable => S.of(context).sendFailureGasUnavailable,
    SendProcessFailureReason.invalidRequest => S.of(context).sendFailureInvalidRequest,
    SendProcessFailureReason.registrationOrKycRequired =>
      S.of(context).sendFailureRegistrationOrKycRequired,
    SendProcessFailureReason.confirmMismatch => S.of(context).sendFailureConfirmMismatch,
    SendProcessFailureReason.generic => S.of(context).sendFailureGeneric,
  };

  /// Shows the terminal result sheet. Returns after the sheet is dismissed.
  ///
  /// For success and non-retryable failures, Close pops the sheet then this
  /// method pops the [SendProcessPage] route (today's behaviour).
  ///
  /// For retryable failures, Retry dismisses only the sheet and re-invokes
  /// [SendProcessCubit.retryConfirm] without popping the page — the stored
  /// prepared transfer `id` must stay alive for the same-intent retry.
  Future<void> _showResultSheet(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    bool canRetry = false,
  }) async {
    final shouldPopPage = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      builder: (sheetContext) => _SendProcessResultSheet(
        icon: icon,
        title: title,
        description: description,
        canRetry: canRetry,
      ),
    );
    if (!context.mounted) {
      return;
    }
    if (shouldPopPage == false) {
      // Retry was chosen — stay on this page and re-confirm the same id.
      await context.read<SendProcessCubit>().retryConfirm();
      return;
    }
    // Close (or null) — leave the send-process route.
    Navigator.of(context).pop();
  }
}

/// Terminal result sheet content. Isolates the double-tap lock for Retry so the
/// parent view stays a [StatelessWidget].
class _SendProcessResultSheet extends StatefulWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool canRetry;

  const _SendProcessResultSheet({
    required this.icon,
    required this.title,
    required this.description,
    required this.canRetry,
  });

  @override
  State<_SendProcessResultSheet> createState() => _SendProcessResultSheetState();
}

class _SendProcessResultSheetState extends State<_SendProcessResultSheet> {
  /// Once the user taps Retry, remove the button so a second tap cannot fire
  /// another concurrent confirm (mirrors the double-tap-lock discipline used
  /// elsewhere in this flow).
  bool _retryConsumed = false;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.9,
          ),
          child: ScrollableActionsLayout(
            shrinkWrap: true,
            body: Column(
              mainAxisSize: MainAxisSize.min,
              spacing: 24,
              children: [
                Icon(widget.icon, color: RealUnitColors.realUnitBlue, size: 64),
                Text(widget.title, style: Theme.of(context).textTheme.headlineMedium),
                Text(
                  widget.description,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: RealUnitColors.neutral500,
                  ),
                ),
              ],
            ),
            actions: [
              if (widget.canRetry && !_retryConsumed)
                FilledButton(
                  onPressed: () {
                    // Fail-closed double-tap lock: consume before the pop so a
                    // second tap cannot schedule another concurrent confirm.
                    if (_retryConsumed) {
                      return;
                    }
                    setState(() {
                      _retryConsumed = true;
                    });
                    // false → parent must NOT pop the SendProcessPage route.
                    Navigator.of(context).pop(false);
                  },
                  child: Text(S.of(context).retry),
                ),
              FilledButton(
                // true → parent pops the SendProcessPage route after the sheet.
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(S.of(context).close),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
