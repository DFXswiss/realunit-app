import 'package:realunit_wallet/models/asset.dart';
import 'package:realunit_wallet/packages/service/transaction_history_service.dart';

enum TransactionTypes { transfer, genericContractCall, tokenTransfer, savingsAdd, savingsRemove }

/// Business classification of a REALU transfer, resolved by the API (decision authority):
/// the Brokerbot as counterparty marks a share purchase or sale, everything else is a plain
/// token movement. Unknown or missing values stay null, so the UI falls back to the
/// direction-based labels used before the category existed.
enum TransferCategory {
  purchase('purchase'),
  sale('sale'),
  transferIn('transferIn'),
  transferOut('transferOut');

  final String value;
  const TransferCategory(this.value);

  static TransferCategory? fromValue(String? value) {
    if (value == null) return null;
    return TransferCategory.values.cast<TransferCategory?>().firstWhere(
          (e) => e?.value == value,
          orElse: () => null,
        );
  }
}

/// Transaction with on-chain metadata
class Transaction {
  final int height;
  final String txId;
  final int chainId;
  final String senderAddress;
  final String receiverAddress;
  final BigInt amount;
  final Asset asset;
  final TransactionTypes type;
  final TransferCategory? category;
  final String? note;
  final String? data;
  final DateTime timestamp;

  const Transaction({
    required this.height,
    required this.txId,
    required this.chainId,
    required this.senderAddress,
    required this.receiverAddress,
    required this.amount,
    required this.asset,
    required this.type,
    this.category,
    required this.note,
    required this.data,
    required this.timestamp,
  });

  bool isOutbound(String walletAddress) => senderAddress.asHexEip55 == walletAddress.asHexEip55;
}
