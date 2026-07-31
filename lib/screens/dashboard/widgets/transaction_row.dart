import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/models/transaction.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/styles/icons.dart';
import 'package:realunit_wallet/widgets/hide_amount_text.dart';

class TransactionRow extends StatelessWidget {
  final Transaction transaction;
  final String walletAddress;
  final Color firstRowTextColor;
  final Color secondRowTextColor;
  final bool showBlockchainIcon;

  const TransactionRow({
    super.key,
    required this.transaction,
    required this.walletAddress,
    this.firstRowTextColor = RealUnitColors.realUnitBlack,
    this.secondRowTextColor = RealUnitColors.neutral400,
    this.showBlockchainIcon = false,
  });

  bool get _isOutbound => transaction.isOutbound(walletAddress);

  @override
  Widget build(BuildContext context) =>
      [TransactionTypes.savingsAdd, TransactionTypes.savingsRemove].contains(transaction.type)
      ? SavingsTransactionRow(
          transaction: transaction,
          firstRowTextColor: firstRowTextColor,
          secondRowTextColor: secondRowTextColor,
          showBlockchainIcon: showBlockchainIcon,
        )
      : InkWell(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: RealUnitColors.basic.white,
            ),
            child: Column(
              children: [
                Row(
                  mainAxisSize: MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  spacing: 10.0,
                  children: [
                    _isOutbound
                        ? Container(
                            height: 32,
                            width: 32,
                            decoration: BoxDecoration(
                              color: RealUnitColors.brand200,
                              borderRadius: BorderRadius.circular(24.0),
                            ),
                            child: const Icon(
                              Icons.horizontal_rule_rounded,
                              color: RealUnitColors.darkBlue,
                            ),
                          )
                        : Container(
                            height: 32,
                            width: 32,
                            decoration: BoxDecoration(
                              color: RealUnitColors.brand200,
                              borderRadius: BorderRadius.circular(24.0),
                            ),
                            child: const Icon(
                              Icons.add,
                              color: RealUnitColors.darkBlue,
                            ),
                          ),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.max,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isOutbound
                                ? S.of(context).transactionSell
                                : S.of(context).transactionBuy,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              height: 20 / 16,
                            ),
                          ),
                          Text(
                            DateFormat('MMM dd, yyyy | H:mm').format(transaction.timestamp.toLocal()),
                            style: const TextStyle(
                              fontSize: 12,
                              height: 16 / 12,
                              color: RealUnitColors.neutral500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    HideAmountText(
                      leadingSymbol: _isOutbound ? '-' : '+',
                      amount: transaction.amount,
                      decimals: transaction.asset.decimals,
                      fractionalDigits: 0,
                      trimZeros: false,
                      trailingSymbol: transaction.asset.symbol,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        height: 20 / 16,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
}

class SavingsTransactionRow extends StatelessWidget {
  final Transaction transaction;
  final Color firstRowTextColor;
  final Color secondRowTextColor;
  final bool showBlockchainIcon;

  const SavingsTransactionRow({
    super.key,
    required this.transaction,
    this.firstRowTextColor = RealUnitColors.realUnitBlack,
    this.secondRowTextColor = RealUnitColors.neutral400,
    this.showBlockchainIcon = false,
  });

  TextStyle get _firstRowTextStyle =>
      TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: firstRowTextColor);

  TextStyle get _secondRowTextStyle => TextStyle(fontSize: 12, color: secondRowTextColor);

  @override
  Widget build(BuildContext context) => InkWell(
    child: Container(
      margin: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: RealUnitColors.basic.white,
      ),
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (transaction.type == TransactionTypes.savingsRemove)
                const CollectInterestIcon(size: 24),
              if (transaction.type == TransactionTypes.savingsAdd)
                const Icon(Icons.savings, size: 24),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.max,
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            transaction.type == TransactionTypes.savingsAdd
                                ? S.of(context).savingsAdd
                                : S.of(context).savingsRemove,
                            style: _firstRowTextStyle,
                          ),
                          const Spacer(),
                          HideAmountText(
                            leadingSymbol: '',
                            amount: transaction.amount,
                            decimals: transaction.asset.decimals,
                            fractionalDigits: 2,
                            trimZeros: false,
                            trailingSymbol: transaction.asset.symbol,
                            style: _firstRowTextStyle,
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Text(
                            DateFormat('MMM dd, yyyy').format(transaction.timestamp.toLocal()),
                            style: _secondRowTextStyle,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
