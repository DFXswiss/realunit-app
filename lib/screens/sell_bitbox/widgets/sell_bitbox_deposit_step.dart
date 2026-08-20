import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/sell_payment_info.dart';
import 'package:realunit_wallet/screens/sell_bitbox/cubit/sell_bitbox_cubit.dart';
import 'package:realunit_wallet/styles/colors.dart';

class SellBitboxDepositStep extends StatelessWidget {
  final SellPaymentInfo paymentInfo;

  const SellBitboxDepositStep({super.key, required this.paymentInfo});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SellBitboxCubit, SellBitboxState>(
      builder: (context, state) {
        if (state is SellBitboxAwaitingDepositConfirm) {
          return Column(
            mainAxisAlignment: .center,
            spacing: 24,
            children: [
              Text(
                S.of(context).sellBitboxDepositTitle,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: .bold,
                ),
                textAlign: .center,
              ),
              Container(
                decoration: BoxDecoration(
                  border: .all(color: RealUnitColors.neutral200),
                  borderRadius: .circular(16),
                ),
                child: Column(
                  children: [
                    _row(
                      context,
                      label: S.of(context).sellBitboxDepositFrom,
                      value: '${paymentInfo.estimatedAmount.toStringAsFixed(2)} ZCHF',
                    ),
                    const Divider(color: RealUnitColors.neutral200, height: 1),
                    _row(
                      context,
                      label: S.of(context).sellBitboxDepositTo,
                      value: _truncateAddress(paymentInfo.depositAddress),
                    ),
                  ],
                ),
              ),
              Text(
                S.of(context).sellBitboxDepositDescription,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: RealUnitColors.neutral500,
                ),
                textAlign: .center,
              ),
              FilledButton(
                onPressed: () => context.read<SellBitboxCubit>().confirmDeposit(),
                child: Text(S.of(context).confirm),
              ),
            ],
          );
        }
        if (state is SellBitboxDepositing || state is SellBitboxRetryingDeposit) {
          return Column(
            mainAxisAlignment: .center,
            spacing: 24,
            children: [
              const CupertinoActivityIndicator(),
              Text(
                state is SellBitboxRetryingDeposit
                    ? S.of(context).sellBitboxRetryingDeposit
                    : S.of(context).sellBitboxDepositing,
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: .center,
              ),
            ],
          );
        }
        if (state is SellBitboxDepositRetry) {
          // Non-null broadcastTxHash: the deposit IS on-chain, only the confirm is pending.
          final confirmOnly = state.broadcastTxHash != null;
          return Column(
            mainAxisAlignment: .center,
            spacing: 24,
            children: [
              Icon(Icons.error_outline, size: 48, color: RealUnitColors.status.red600),
              Text(
                confirmOnly
                    ? S.of(context).sellBitboxConfirmRetryTitle
                    : S.of(context).sellBitboxDepositRetryTitle,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: .bold),
                textAlign: .center,
              ),
              Text(
                state.errorMessage.isNotEmpty
                    ? state.errorMessage
                    : confirmOnly
                    ? S.of(context).sellBitboxConfirmRetryDescription
                    : S.of(context).sellBitboxDepositRetryDescription,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: RealUnitColors.neutral500),
                textAlign: .center,
              ),
              FilledButton(
                onPressed: () => context.read<SellBitboxCubit>().retryDeposit(),
                child: Text(S.of(context).retry),
              ),
            ],
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _row(BuildContext context, {required String label, required String value}) {
    return Padding(
      padding: const .symmetric(vertical: 12, horizontal: 20),
      child: Row(
        mainAxisAlignment: .spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: RealUnitColors.neutral500,
              height: 18 / 14,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: .w600,
              height: 18 / 14,
            ),
          ),
        ],
      ),
    );
  }

  String _truncateAddress(String address) {
    if (address.length <= 12) return address;
    return '${address.substring(0, 6)}…${address.substring(address.length - 4)}';
  }
}
