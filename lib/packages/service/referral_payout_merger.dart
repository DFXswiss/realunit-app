import 'package:realunit_wallet/models/asset.dart';
import 'package:realunit_wallet/models/transaction.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_payout_dto.dart';

/// Converts referral payouts into [Transaction] rows and drops on-chain
/// transfers that share a `txHash` with a payout (dedupe — payout wins).
List<Transaction> mergeReferralPayouts({
  required List<Transaction> onChain,
  required List<ReferralPayoutDto> payouts,
  required Asset asset,
  required String walletAddress,
}) {
  final payoutTxHashes = <String>{};
  final payoutTxs = <Transaction>[];

  for (final payout in payouts) {
    final hash = payout.txHash;
    if (hash != null && hash.isNotEmpty) {
      payoutTxHashes.add(hash.toLowerCase());
    }
    payoutTxs.add(
      Transaction(
        height: 0,
        txId: hash?.isNotEmpty == true ? hash! : 'referral-payout-${payout.id}',
        chainId: asset.chainId,
        senderAddress: '',
        receiverAddress: walletAddress,
        amount: BigInt.from(payout.amount.round()),
        asset: asset,
        type: TransactionTypes.referralPayout,
        note: '',
        // CHF frozen at credit — display only; never recompute from price.
        data: payout.chfValue.toString(),
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
