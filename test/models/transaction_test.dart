import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/models/transaction.dart';
import 'package:realunit_wallet/packages/utils/default_assets.dart';

const _wallet = '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266';

Transaction _tx({
  String sender = '0x0000000000000000000000000000000000000001',
  String receiver = '0x0000000000000000000000000000000000000002',
}) =>
    Transaction(
      height: 1,
      txId: '0xabc',
      chainId: realUnitAsset.chainId,
      senderAddress: sender,
      receiverAddress: receiver,
      amount: BigInt.one,
      asset: realUnitAsset,
      type: TransactionTypes.tokenTransfer,
      note: '',
      data: null,
      timestamp: DateTime.utc(2026, 1, 1),
    );

void main() {
  group('$Transaction', () {
    test('isOutbound is true when sender matches the wallet (EIP-55 normalised)', () {
      // Pass a lowercase wallet; the helper EIP-55-normalises both sides.
      final tx = _tx(sender: _wallet.toLowerCase());

      expect(tx.isOutbound(_wallet), isTrue);
    });

    test('isOutbound is false when sender differs from the wallet', () {
      final tx = _tx(sender: '0x0000000000000000000000000000000000000005');

      expect(tx.isOutbound(_wallet), isFalse);
    });

    test('isOutbound is false for a referral payout with empty sender', () {
      final tx = Transaction(
        height: 0,
        txId: 'referral-payout-1',
        chainId: realUnitAsset.chainId,
        senderAddress: '',
        receiverAddress: _wallet,
        amount: BigInt.from(20),
        asset: realUnitAsset,
        type: TransactionTypes.referralPayout,
        note: '',
        data: '246.50',
        timestamp: DateTime.utc(2026, 8, 24, 10),
      );
      expect(tx.isOutbound(_wallet), isFalse);
    });

    test('isOutbound is false for a referral payout from the zero address', () {
      final tx = Transaction(
        height: 0,
        txId: 'referral-payout-1',
        chainId: realUnitAsset.chainId,
        senderAddress: kReferralPayoutSenderAddress,
        receiverAddress: _wallet,
        amount: BigInt.from(20),
        asset: realUnitAsset,
        type: TransactionTypes.referralPayout,
        note: '',
        data: '246.50',
        timestamp: DateTime.utc(2026, 8, 24, 10),
      );
      expect(tx.isOutbound(_wallet), isFalse);
    });

    test('isOutbound normalises hex-digit case via EIP-55 on both sides', () {
      // EIP-55 keeps the literal `0x` prefix but mixes hex-digit case
      // deterministically. The helper round-trips through fromHex/hexEip55
      // so all-lowercase, all-mixed, and properly-EIP-55-cased variants
      // of the SAME address compare equal.
      final tx = _tx(sender: _wallet.toLowerCase());

      expect(tx.isOutbound(_wallet), isTrue);
      expect(tx.isOutbound(_wallet.toLowerCase()), isTrue);
    });
  });

  group('$TransactionTypes', () {
    test('exposes the six expected entries (catches accidental additions)', () {
      // A new type added without updating the rendering switch would
      // silently break the UI. Pin the count.
      expect(TransactionTypes.values, hasLength(6));
      expect(TransactionTypes.values, contains(TransactionTypes.transfer));
      expect(TransactionTypes.values, contains(TransactionTypes.tokenTransfer));
      expect(TransactionTypes.values, contains(TransactionTypes.savingsAdd));
      expect(TransactionTypes.values, contains(TransactionTypes.savingsRemove));
      expect(TransactionTypes.values, contains(TransactionTypes.genericContractCall));
      expect(TransactionTypes.values, contains(TransactionTypes.referralPayout));
    });
  });
}
