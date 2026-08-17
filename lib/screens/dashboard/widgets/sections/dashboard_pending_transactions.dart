import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/models/transactions/dto/transactions_dto.dart';
import 'package:realunit_wallet/screens/dashboard/bloc/pending_transactions_cubit.dart';
import 'package:realunit_wallet/screens/dashboard/widgets/pending_transaction_row.dart';
import 'package:realunit_wallet/setup/routing/routes/app_routes.dart';
import 'package:realunit_wallet/styles/colors.dart';

class DashboardPendingTransactionsView extends StatelessWidget {
  const DashboardPendingTransactionsView({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PendingTransactionsCubit, List<TransactionDto>>(
      builder: (context, transactions) {
        if (transactions.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: .start,
          spacing: 8.0,
          children: [
            Text(
              S.of(context).pendingTransactions,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: RealUnitColors.neutral500,
              ),
            ),
            Container(
              padding: const .all(12),
              decoration: BoxDecoration(
                color: RealUnitColors.basic.white,
                borderRadius: .circular(16.0),
              ),
              child: Column(
                spacing: 12.0,
                children: transactions
                    .map(
                      (t) => PendingTransactionRow(
                        key: ValueKey('pendingTx-${t.id?.toString() ?? t.uid}'),
                        transaction: t,
                        onTap: () async {
                          final pending = context.read<PendingTransactionsCubit>();
                          final removed = await context.pushNamed<String>(
                            AppRoutes.pendingTransaction,
                            extra: t,
                          );
                          await pending.applyDetailReturn(removed);
                        },
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        );
      },
    );
  }
}
