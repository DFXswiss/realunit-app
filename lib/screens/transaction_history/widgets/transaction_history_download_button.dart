import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:open_file/open_file.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/models/transaction.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_pdf_service.dart';
import 'package:realunit_wallet/screens/settings/bloc/settings_bloc.dart';
import 'package:realunit_wallet/screens/transaction_history/cubits/multi_receipt/transaction_history_multi_receipt_cubit.dart';
import 'package:realunit_wallet/setup/di.dart';
import 'package:realunit_wallet/styles/colors.dart';

class TransactionHistoryDownloadButton extends StatelessWidget {
  final List<Transaction> transactions;

  const TransactionHistoryDownloadButton({super.key, required this.transactions});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => TransactionHistoryMultiReceiptCubit(
        getIt<RealUnitPdfService>(),
      ),
      child: TransactionHistoryDownloadButtonView(
        transactions: transactions,
      ),
    );
  }
}

/// DFX Beleg PDF is buy/sell only. Prize rows already show Anzahl, Datum
/// and frozen CHF on the history line (Offerte Punkt 2) and have no DFX id.
List<String> receiptTxIdsForDownload(Iterable<Transaction> transactions) => [
  for (final t in transactions)
    if (t.type != TransactionTypes.referralPayout) t.txId,
];

class TransactionHistoryDownloadButtonView extends StatelessWidget {
  final List<Transaction> transactions;

  const TransactionHistoryDownloadButtonView({super.key, required this.transactions});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<TransactionHistoryMultiReceiptCubit, TransactionHistoryMultiReceiptState>(
      listener: (context, state) async {
        if (state is TransactionHistoryMultiReceiptFailure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: RealUnitColors.status.red600,
            ),
          );
        }
        if (state is TransactionHistoryMultiReceiptSuccess) {
          await OpenFile.open(state.receiptPath);
        }
      },
      builder: (context, state) {
        final transactionsIds = receiptTxIdsForDownload(transactions);
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: Text(
                S.of(context).pdf,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  height: 16 / 12,
                  color: RealUnitColors.neutral500,
                ),
              ),
            ),
            state is TransactionHistoryMultiReceiptLoading
                ? Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: RealUnitColors.realUnitBlue,
                      borderRadius: BorderRadius.circular(12.0),
                    ),
                    child: CircularProgressIndicator(
                      padding: const EdgeInsets.all(12.0),
                      strokeWidth: 1.5,
                      color: RealUnitColors.basic.white,
                    ),
                  )
                : transactionsIds.isNotEmpty
                ? GestureDetector(
                    onTap: () =>
                        context.read<TransactionHistoryMultiReceiptCubit>().generateReceipt(
                          transactionsIds,
                          currency: context.read<SettingsBloc>().state.currency,
                          language: context.read<SettingsBloc>().state.language,
                        ),
                    child: Container(
                      height: 44,
                      width: 44,
                      decoration: BoxDecoration(
                        color: RealUnitColors.realUnitBlue,
                        borderRadius: BorderRadius.circular(12.0),
                      ),
                      child: Icon(
                        Icons.file_download_outlined,
                        color: RealUnitColors.basic.white,
                      ),
                    ),
                  )
                : Container(
                    height: 44,
                    width: 44,
                    decoration: BoxDecoration(
                      color: RealUnitColors.neutral300,
                      borderRadius: BorderRadius.circular(12.0),
                    ),
                    child: Icon(
                      Icons.file_download_outlined,
                      color: RealUnitColors.basic.white,
                    ),
                  ),
          ],
        );
      },
    );
  }
}
