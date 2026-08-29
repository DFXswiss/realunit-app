import 'package:realunit_wallet/models/asset.dart';
import 'package:realunit_wallet/models/transaction.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_payout_dto.dart';
import 'package:realunit_wallet/screens/referral/format_frozen_chf.dart';

/// Converts referral payouts into [Transaction] rows and drops on-chain
/// transfers that share a `txHash` with a payout (dedupe — payout wins).
/// Duplicate API rows with the same id or tx hash are kept once.
List<Transaction> mergeReferralPayouts({
  required List<Transaction> onChain,
  required List<ReferralPayoutDto> payouts,
  required Asset asset,
  required String walletAddress,
}) {
  final payoutTxHashes = <String>{};
  final seenIds = <int>{};
  final payoutTxs = <Transaction>[];

  for (final payout in payouts) {
    if (!payout.isSettled) continue;
    final hash = payout.txHash;
    final hashKey = hash != null && hash.isNotEmpty ? hash.toLowerCase() : null;
    if (payout.id == 0 && hashKey == null) continue;
    if (payout.id != 0 && !seenIds.add(payout.id)) continue;
    if (hashKey != null && !payoutTxHashes.add(hashKey)) continue;
    payoutTxs.add(
      Transaction(
        height: 0,
        txId: hash != null && hash.isNotEmpty
            ? hash.toLowerCase()
            : 'referral-payout-${payout.id}',
        chainId: asset.chainId,
        senderAddress: kReferralPayoutSenderAddress,
        receiverAddress: walletAddress,
        amount: BigInt.from(payout.amount.truncate()),
        asset: asset,
        type: TransactionTypes.referralPayout,
        note: '',
        // CHF frozen at credit — two decimals; never recompute from price.
        data: formatFrozenChfAmount(payout.chfValue.toString()),
        timestamp: payout.created,
      ),
    );
  }

  final filteredOnChain = onChain.where((tx) {
    if (payoutTxHashes.isEmpty) return true;
    return !payoutTxHashes.contains(tx.txId.toLowerCase());
  });

  final merged = [...filteredOnChain, ...payoutTxs]
    ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  return merged;
}
