import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/models/transaction.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_payout_dto.dart';
import 'package:realunit_wallet/packages/service/referral_payout_merger.dart';
import 'package:realunit_wallet/packages/utils/default_assets.dart';

const _wallet = '0x0000000000000000000000000000000000000001';

Transaction _onChain(String txId) => Transaction(
  height: 1,
  txId: txId,
  chainId: realUnitAsset.chainId,
  senderAddress: '0xprize',
  receiverAddress: _wallet,
  amount: BigInt.from(20),
  asset: realUnitAsset,
  type: TransactionTypes.tokenTransfer,
  note: '',
  data: null,
  timestamp: DateTime.utc(2026, 8, 1),
);

void main() {
  group('mergeReferralPayouts', () {
    test(
      'keeps frozen chfValue on the payout row and drops the matching on-chain transfer',
      () {
        final payout = ReferralPayoutDto(
          id: 7,
          amount: 20,
          chfValue: 246.5,
          created: DateTime.utc(2026, 8, 24, 10),
          kind: 'Invite',
          status: 'Complete',
          txHash: '0xabc',
        );

        final merged = mergeReferralPayouts(
          onChain: [_onChain('0xabc'), _onChain('0xother')],
          payouts: [payout],
          asset: realUnitAsset,
          walletAddress: _wallet,
        );

        expect(merged.map((t) => t.txId), ['0xabc', '0xother']);
        final prize = merged.firstWhere((t) => t.txId == '0xabc');
        expect(prize.type, TransactionTypes.referralPayout);
        expect(prize.amount, BigInt.from(20));
        expect(prize.data, '246.5');
        expect(prize.timestamp, DateTime.utc(2026, 8, 24, 10));
      },
    );

    test('uses a synthetic txId when the payout has no hash yet', () {
      final payout = ReferralPayoutDto(
        id: 3,
        amount: 20,
        chfValue: 10,
        created: DateTime.utc(2026, 8, 24),
        kind: 'Promo',
        status: 'Pending',
      );

      final merged = mergeReferralPayouts(
        onChain: const [],
        payouts: [payout],
        asset: realUnitAsset,
        walletAddress: _wallet,
      );

      expect(merged.single.txId, 'referral-payout-3');
      expect(merged.single.type, TransactionTypes.referralPayout);
    });
  });
}
