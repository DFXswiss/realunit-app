import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/buy/buy_payment_info.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_buy_payment_info_service.dart';
import 'package:realunit_wallet/screens/buy/buy_payment_details_page.dart';
import 'package:realunit_wallet/screens/buy/cubits/buy_confirm/buy_confirm_cubit.dart';
import 'package:realunit_wallet/setup/di.dart';
import 'package:realunit_wallet/setup/routing/routes/app_routes.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';

/// Primary buy CTA shown once the API has returned a valid quote. Tapping it
/// confirms the purchase (binding) via [BuyConfirmCubit]; on success it opens
/// the `Zahlungsdetails` page with the bank-transfer instructions, on failure
/// it surfaces the typed error as a snackbar.
class BuyConfirmButton extends StatelessWidget {
  final BuyPaymentInfo buyPaymentInfo;

  const BuyConfirmButton({
    super.key,
    required this.buyPaymentInfo,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => BuyConfirmCubit(
        getIt<RealUnitBuyPaymentInfoService>(),
      ),
      child: BuyConfirmButtonView(
        buyPaymentInfo: buyPaymentInfo,
      ),
    );
  }
}

class BuyConfirmButtonView extends StatelessWidget {
  final BuyPaymentInfo buyPaymentInfo;

  const BuyConfirmButtonView({
    super.key,
    required this.buyPaymentInfo,
  });

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<BuyConfirmCubit, BuyConfirmState>(
      listener: (context, state) {
        if (state is BuyConfirmSuccess) {
          context.pushNamed(
            AppRoutes.buyPaymentDetails,
            extra: BuyPaymentDetailsParams(
              buyPaymentInfo: buyPaymentInfo,
              // The charged amount comes from the quote itself, never keystrokes.
              amount: '${buyPaymentInfo.amount.round()}',
              // Backward compatible: prefer the API-designated purpose once it
              // ships; until then `reference` (always returned) is the value.
              purposeOfPayment: state.remittanceInfo ?? state.reference,
              paymentRequest: state.paymentRequest,
            ),
          );
        }
        if (state is BuyConfirmFailure) {
          final text = switch (state.error) {
            BuyConfirmError.aktionariat => S.of(context).buyPaymentConfirmFailedAktionariat,
            BuyConfirmError.amountTooLow => S.of(context).buyPaymentConfirmFailedAmountTooLow,
            BuyConfirmError.primaryEmailRequired =>
              S.of(context).buyPaymentConfirmFailedAktionariat,
            BuyConfirmError.unknown => S.of(context).buyPaymentConfirmFailed,
          };
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(text)),
          );
        }
        if (state is BuyDeactivateSuccess) {
          context.pop();
        }
        if (state is BuyDeactivateFailure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(S.of(context).pendingTransactionDeactivateFailed)),
          );
        }
      },
      builder: (context, state) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            children: [
              AppFilledButton(
                onPressed: () => context.read<BuyConfirmCubit>().confirmPayment(
                  buyPaymentInfo.id,
                ),
                state: state is BuyConfirmLoading ? .loading : .idle,
                label: S.of(context).buyPaymentConfirm,
              ),
              AppFilledButton(
                variant: FilledButtonVariant.secondary,
                label: S.of(context).pendingTransactionDeactivate,
                onPressed: state is BuyConfirmLoading ? null : () => _confirmAndDeactivate(context),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmAndDeactivate(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: Text(S.of(dialogContext).pendingTransactionDeactivateConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(S.of(dialogContext).cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(S.of(dialogContext).pendingTransactionDeactivate),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await context.read<BuyConfirmCubit>().deactivateQuote(buyPaymentInfo.id);
  }
}
