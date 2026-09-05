import 'package:realunit_wallet/models/asset.dart';
import 'package:realunit_wallet/packages/service/transaction_history_service.dart';

enum TransactionTypes {
  transfer,
  genericContractCall,
  tokenTransfer,
  savingsAdd,
  savingsRemove,
  /// Referral/promo payout credited via the API. [Transaction.data] holds the
  /// CHF value frozen at credit (decimal string); never recompute from price.
  referralPayout,
}

/// Prize rows have no on-chain counterparty until the transfer hash lands.
/// Never persist `''` — `EthereumAddress.fromHex('')` throws on history and
/// the dashboard. The zero address is inbound (`isOutbound` is false).
const kReferralPayoutSenderAddress =
    '0x0000000000000000000000000000000000000000';

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
    required this.note,
    required this.data,
    required this.timestamp,
  });

  bool isOutbound(String walletAddress) {
    if (type == TransactionTypes.referralPayout) return false;
    if (senderAddress.isEmpty || walletAddress.isEmpty) return false;
    return senderAddress.asHexEip55 == walletAddress.asHexEip55;
  }
}
