import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/models/transactions/dto/transactions_dto.dart';
import 'package:realunit_wallet/screens/dashboard/cubits/pending_transaction_detail/pending_transaction_detail_cubit.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';
import 'package:realunit_wallet/widgets/scrollable_actions_layout.dart';

/// Detail page for a single pending transaction from the dashboard list.
///
/// Quote cancellation is available only for binding buys that are still
/// waiting for payment (`type == buy` and `state == waitingForPayment`).
class PendingTransactionDetailPage extends StatelessWidget {
  final TransactionDto transaction;

  const PendingTransactionDetailPage({
    super.key,
    required this.transaction,
  });

  @override
  Widget build(BuildContext context) {
    return PendingTransactionDetailView(transaction: transaction);
  }
}

class PendingTransactionDetailView extends StatelessWidget {
  final TransactionDto transaction;

  const PendingTransactionDetailView({
    super.key,
    required this.transaction,
  });

  bool get _isCancellable =>
      transaction.type == TransactionType.buy &&
      transaction.state == TransactionState.waitingForPayment;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PendingTransactionDetailCubit, PendingTransactionDetailState>(
      listener: (context, state) {
        if (state is PendingTransactionDetailSuccess) {
          context.pop();
        }
        if (state is PendingTransactionDetailFailure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(S.of(context).pendingTransactionDeactivateFailed)),
          );
        }
      },
      builder: (context, state) {
        final loading = state is PendingTransactionDetailLoading;
        final idOrUid = transaction.id?.toString() ?? transaction.uid;
        return Scaffold(
          appBar: AppBar(
            title: Text(
              S.of(context).pendingTransactionDetailTitle,
              key: const ValueKey('pendingTxDetailTitle'),
            ),
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: ScrollableActionsLayout(
                body: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 16,
                  children: [
                    Text(
                      _typeLabel(context),
                      key: const ValueKey('pendingTxDetailType'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      _statusLabel(context),
                      key: const ValueKey('pendingTxDetailStatus'),
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: RealUnitColors.neutral500,
                      ),
                    ),
                    if (transaction.inputAmount != null && transaction.inputAsset != null)
                      Text(
                        '${_formatAmount(transaction.inputAmount!)} ${transaction.inputAsset}',
                        key: const ValueKey('pendingTxDetailAmount'),
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    else ...[
                      if (transaction.inputAmount != null)
                        Text(
                          _formatAmount(transaction.inputAmount!),
                          key: const ValueKey('pendingTxDetailAmount'),
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      if (transaction.inputAsset != null)
                        Text(
                          transaction.inputAsset!,
                          key: const ValueKey('pendingTxDetailAsset'),
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                    if (transaction.date != null)
                      Text(
                        DateFormat('MMM dd, yyyy').format(transaction.date!.toLocal()),
                        key: const ValueKey('pendingTxDetailDate'),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: RealUnitColors.neutral500,
                        ),
                      ),
                    if (idOrUid != null && idOrUid.isNotEmpty)
                      Text(
                        idOrUid,
                        key: const ValueKey('pendingTxDetailId'),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: RealUnitColors.neutral500,
                        ),
                      ),
                  ],
                ),
                actions: _isCancellable
                    ? [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: AppFilledButton(
                            variant: FilledButtonVariant.secondary,
                            label: S.of(context).pendingTransactionDeactivate,
                            state: loading ? .loading : .idle,
                            onPressed: loading
                                ? null
                                : () => _confirmAndDeactivate(context),
                          ),
                        ),
                      ]
                    : const [],
              ),
            ),
          ),
        );
      },
    );
  }

  String _typeLabel(BuildContext context) {
    return switch (transaction.type) {
      TransactionType.buy => S.of(context).transactionBuy,
      TransactionType.sell => S.of(context).transactionSell,
      _ => transaction.type?.value ?? '—',
    };
  }

  String _statusLabel(BuildContext context) {
    if (transaction.state == TransactionState.waitingForPayment) {
      return S.of(context).transactionWaitingForPayment;
    }
    return S.of(context).transactionPending;
  }

  String _formatAmount(double amount) {
    if (amount == amount.roundToDouble()) {
      return amount.toInt().toString();
    }
    return amount.toStringAsFixed(2);
  }

  Future<void> _confirmAndDeactivate(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => CancelQuoteConfirmDialog(
        strings: S.of(context),
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await context.read<PendingTransactionDetailCubit>().deactivate(transaction);
  }
}

/// Confirm dialog for cancelling a waiting buy quote.
///
/// Takes [S] from the page context so Alchemist overlay routes (which do not
/// inherit localizations) can still golden the same widget.
class CancelQuoteConfirmDialog extends StatelessWidget {
  final S strings;

  const CancelQuoteConfirmDialog({
    super.key,
    required this.strings,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: Text(strings.pendingTransactionDeactivateConfirm),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(strings.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(strings.pendingTransactionDeactivate),
        ),
      ],
    );
  }
}
