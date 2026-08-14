import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/models/transactions/dto/transactions_dto.dart';
import 'package:realunit_wallet/styles/colors.dart';

class PendingTransactionRow extends StatefulWidget {
  final TransactionDto transaction;
  final Future<void> Function()? onDeactivate;

  const PendingTransactionRow({
    super.key,
    required this.transaction,
    this.onDeactivate,
  });

  @override
  State<PendingTransactionRow> createState() => _PendingTransactionRowState();
}

class _PendingTransactionRowState extends State<PendingTransactionRow> {
  bool _busy = false;

  bool get _isBuy => widget.transaction.type == TransactionType.buy;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: .circular(20),
        color: RealUnitColors.basic.white,
      ),
      child: Row(
        crossAxisAlignment: .center,
        spacing: 10.0,
        children: [
          Container(
            height: 32,
            width: 32,
            decoration: BoxDecoration(
              color: RealUnitColors.brand200,
              borderRadius: .circular(24.0),
            ),
            child: const CupertinoActivityIndicator(),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              children: [
                Text(
                  _isBuy ? S.of(context).transactionBuy : S.of(context).transactionSell,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: .w600,
                  ),
                ),
                Text(
                  widget.transaction.state == .waitingForPayment
                      ? S.of(context).transactionWaitingForPayment
                      : S.of(context).transactionPending,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: RealUnitColors.neutral500,
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: Column(
              crossAxisAlignment: .end,
              children: [
                if (widget.transaction.inputAmount != null && widget.transaction.inputAsset != null)
                  Text(
                    '${_formatAmount(widget.transaction.inputAmount!)} ${widget.transaction.inputAsset}',
                    textAlign: .end,
                    maxLines: 2,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: .w600,
                    ),
                  ),
                if (widget.transaction.date != null)
                  Text(
                    DateFormat('MMM dd, yyyy').format(widget.transaction.date!.toLocal()),
                    textAlign: .end,
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: RealUnitColors.neutral500,
                    ),
                  ),
              ],
            ),
          ),
          if (_isBuy && widget.onDeactivate != null)
            IconButton(
              tooltip: S.of(context).pendingTransactionDeactivate,
              icon: const Icon(Icons.close),
              onPressed: _busy ? null : () => _confirmAndDeactivate(context),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmAndDeactivate(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: Text(S.of(dialogContext).pendingTransactionDeactivateConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(S.of(dialogContext).cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(S.of(dialogContext).pendingTransactionDeactivate),
          ),
        ],
      ),
    );
    if (confirmed != true || widget.onDeactivate == null) return;
    setState(() => _busy = true);
    try {
      await widget.onDeactivate!();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).pendingTransactionDeactivateFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _formatAmount(double amount) {
    if (amount == amount.roundToDouble()) {
      return amount.toInt().toString();
    }
    return amount.toStringAsFixed(2);
  }
}
