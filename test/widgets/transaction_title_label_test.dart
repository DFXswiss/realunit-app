import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/models/asset.dart';
import 'package:realunit_wallet/models/dfx_transaction.dart';
import 'package:realunit_wallet/models/transaction.dart';
import 'package:realunit_wallet/widgets/transaction_title_label.dart';

import '../helper/helper.dart';

const _wallet = '0x000000000000000000000000000000000000bEEF';
const _other = '0x0000000000000000000000000000000000001234';

const _asset = Asset(chainId: 1, address: '0xToken', name: 'RealUnit', symbol: 'REALU', decimals: 0);

Transaction _tx({TransferCategory? category, String sender = _other, String receiver = _wallet}) => Transaction(
      height: 1,
      txId: '0xabc',
      chainId: 1,
      senderAddress: sender,
      receiverAddress: receiver,
      amount: BigInt.from(20),
      asset: _asset,
      type: TransactionTypes.tokenTransfer,
      category: category,
      note: '',
      data: null,
      timestamp: DateTime.utc(2026, 9, 1),
    );

DfxTransaction _dfxTx({
  TransferCategory? category,
  String sender = _wallet,
  String receiver = _other,
}) =>
    DfxTransaction(
      dfxId: 42,
      height: 1,
      txId: '0xabc',
      chainId: 1,
      senderAddress: sender,
      receiverAddress: receiver,
      amount: BigInt.from(20),
      asset: _asset,
      type: TransactionTypes.tokenTransfer,
      category: category,
      note: '',
      data: null,
      timestamp: DateTime.utc(2026, 9, 1),
    );

void main() {
  Future<(S, String)> label(WidgetTester tester, Transaction tx, {required bool isOutbound}) async {
    late S s;
    late String result;
    await tester.pumpApp(Builder(
      builder: (context) {
        s = S.of(context);
        result = transactionTitleLabel(context, tx, isOutbound: isOutbound);
        return const SizedBox.shrink();
      },
    ));
    return (s, result);
  }

  group('transactionTitleLabel', () {
    testWidgets('labels a Brokerbot purchase as a buy', (tester) async {
      final (sBuy, buy) = await label(tester, _tx(category: TransferCategory.purchase), isOutbound: false);
      final (sSale, sale) = await label(
        tester,
        _tx(category: TransferCategory.sale, sender: _wallet, receiver: _other),
        isOutbound: true,
      );
      expect(buy, sBuy.transactionBuy);
      expect(sale, sSale.transactionSell);
    });

    testWidgets('labels plain transfers as received/sent, not as buy/sell', (tester) async {
      final (s, received) = await label(tester, _tx(category: TransferCategory.transferIn), isOutbound: false);
      final (_, sent) = await label(
        tester,
        _tx(category: TransferCategory.transferOut, sender: _wallet, receiver: _other),
        isOutbound: true,
      );
      expect(received, s.transactionReceived);
      expect(sent, s.transactionSent);
      expect(received, isNot(s.transactionBuy));
      expect(sent, isNot(s.transactionSell));
    });

    testWidgets('falls back to direction labels without a category (legacy rows, older API)',
        (tester) async {
      final (s, inbound) = await label(tester, _tx(), isOutbound: false);
      expect(inbound, s.transactionBuy);
    });

    testWidgets('keeps direction labels for DFX-backed transactions regardless of category',
        (tester) async {
      final (s, outbound) = await label(
        tester,
        _dfxTx(category: TransferCategory.purchase),
        isOutbound: true,
      );
      expect(outbound, s.transactionSell);
    });
  });
}
