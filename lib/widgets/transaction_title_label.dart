import 'package:flutter/widgets.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/models/dfx_transaction.dart';
import 'package:realunit_wallet/models/transaction.dart';

/// Resolves the list title of a transaction.
///
/// DFX-backed transactions (bank buys and sells) keep the direction-based Buy/Sell labels.
/// For pure on-chain transfers the API-provided [TransferCategory] decides: Brokerbot
/// counterparty means a share purchase or sale, everything else is a plain received/sent
/// token movement. Without a category (legacy rows, older API) the previous direction-based
/// labels remain, so nothing breaks while backend and app roll out independently.
String transactionTitleLabel(BuildContext context, Transaction transaction, {required bool isOutbound}) {
  final s = S.of(context);

  if (transaction is! DfxTransaction) {
    switch (transaction.category) {
      case TransferCategory.purchase:
        return s.transactionBuy;
      case TransferCategory.sale:
        return s.transactionSell;
      case TransferCategory.transferIn:
        return s.transactionReceived;
      case TransferCategory.transferOut:
        return s.transactionSent;
      case null:
        break;
    }
  }

  return isOutbound ? s.transactionSell : s.transactionBuy;
}
