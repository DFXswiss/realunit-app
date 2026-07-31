import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/models/transaction.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_pdf_service.dart';
import 'package:realunit_wallet/screens/settings/bloc/settings_bloc.dart';
import 'package:realunit_wallet/screens/transaction_history/cubits/receipt/transaction_history_receipt_cubit.dart';
import 'package:realunit_wallet/setup/di.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/hide_amount_text.dart';

class TransactionHistoryRow extends StatelessWidget {
  final Transaction transaction;
  final String walletAddress;

  const TransactionHistoryRow({
    super.key,
    required this.transaction,
    required this.walletAddress,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => TransactionHistoryReceiptCubit(
        getIt<RealUnitPdfService>(),
      ),
      child: TransactionHistoryRowView(
        transaction: transaction,
        isOutbound: transaction.isOutbound(walletAddress),
      ),
    );
  }
}

class TransactionHistoryRowView extends StatelessWidget {
  const TransactionHistoryRowView({
    super.key,
    required this.transaction,
    required this.isOutbound,
  });

  final Transaction transaction;
  final bool isOutbound;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<TransactionHistoryReceiptCubit, TransactionHistoryReceiptState>(
      listener: (context, state) async {
        if (state is TransactionHistoryReceiptFailure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: RealUnitColors.status.red600,
            ),
          );
        }
        if (state is TransactionHistoryReceiptSuccess) {
          await OpenFile.open(state.receiptPath);
        }
      },
      builder: (context, state) {
        return InkWell(
          child: Column(
            children: [
              Row(
                mainAxisSize: MainAxisSize.max,
                crossAxisAlignment: CrossAxisAlignment.center,
                spacing: 10.0,
                children: [
                  isOutbound
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
                          isOutbound ? S.of(context).transactionSell : S.of(context).transactionBuy,
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
                    leadingSymbol: isOutbound ? '-' : '+',
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
                  state is TransactionHistoryReceiptLoading
                      ? const Padding(
                          padding: EdgeInsets.all(4.0),
                          child: SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: RealUnitColors.realUnitBlue,
                            ),
                          ),
                        )
                      : GestureDetector(
                          onTap: () {
                            context.read<TransactionHistoryReceiptCubit>().generateReceipt(
                              transaction.txId,
                              currency: context.read<SettingsBloc>().state.currency,
                              language: context.read<SettingsBloc>().state.language,
                            );
                          },
                          child: const Icon(
                            size: 20,
                            Icons.file_download_outlined,
                            color: RealUnitColors.realUnitBlue,
                          ),
                        ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
