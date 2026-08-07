import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/payment_info_error.dart';
import 'package:realunit_wallet/screens/buy/cubits/buy_converter/buy_converter_cubit.dart';
import 'package:realunit_wallet/screens/buy/cubits/buy_payment_info/buy_payment_info_cubit.dart';
import 'package:realunit_wallet/screens/buy/widgets/buy_confirm_button.dart';
import 'package:realunit_wallet/screens/hardware_connect_bitbox/show_bitbox_reconnect_sheet.dart';
import 'package:realunit_wallet/setup/routing/routes/app_routes.dart';
import 'package:realunit_wallet/setup/routing/routes/support_routes.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';

/// Bottom call-to-action of the buy page. It mirrors the `BuyPaymentInfoCubit`
/// state: on a valid quote it shows the binding-buy CTA, otherwise it offers
/// the action the current gate requires (register, KYC, reconnect, retry) or a
/// disabled button for the min-amount validation error.
class PaymentActionButton extends StatelessWidget {
  final TextEditingController amountController;

  const PaymentActionButton({
    super.key,
    required this.amountController,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BuyPaymentInfoCubit, BuyPaymentInfoState>(
      builder: (context, paymentState) {
        if (paymentState is BuyPaymentInfoSuccess) {
          return BuyConfirmButton(
            buyPaymentInfo: paymentState.buyPaymentInfo,
          );
        }
        if (paymentState is BuyPaymentInfoFailure) {
          if (paymentState.error == PaymentInfoError.minAmountNotMet) {
            final state = paymentState as BuyPaymentInfoMinAmountNotMetFailure;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 20.0),
              child: Column(
                spacing: 8.0,
                children: [
                  Text(
                    S
                        .of(context)
                        .buyMinAmount(
                          '${state.minAmount.ceil()}',
                          context.read<BuyConverterCubit>().state.currency.code,
                        ),
                    style: const TextStyle(
                      color: RealUnitColors.neutral500,
                      fontSize: 14,
                    ),
                  ),
                  AppFilledButton(
                    onPressed: null,
                    label: S.of(context).next,
                  ),
                ],
              ),
            );
          }
          if (paymentState.error == PaymentInfoError.registrationRequired) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: AppFilledButton(
                onPressed: () async {
                  await context.pushNamed(AppRoutes.kyc, extra: paymentState.context);
                  if (context.mounted) {
                    context.read<BuyPaymentInfoCubit>().getPaymentInfo(
                      amount: amountController.text,
                      currency: context.read<BuyConverterCubit>().state.currency,
                    );
                  }
                },
                label: S.of(context).next,
              ),
            );
          }
          if (paymentState.error == PaymentInfoError.kycRequired) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: AppFilledButton(
                onPressed: () async {
                  await context.pushNamed(AppRoutes.kyc, extra: paymentState.context);
                  if (context.mounted) {
                    context.read<BuyPaymentInfoCubit>().getPaymentInfo(
                      amount: amountController.text,
                      currency: context.read<BuyConverterCubit>().state.currency,
                    );
                  }
                },
                label: S.of(context).next,
              ),
            );
          }
          if (paymentState.error == PaymentInfoError.primaryEmailRequired) {
            // Pre-tap gate: the API flagged the quote invalid because the
            // account has no primary email. Route to email capture first,
            // then re-fetch the quote so a now-valid quote surfaces the
            // binding-buy CTA — mirrors the registration / KYC gates above.
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: AppFilledButton(
                onPressed: () async {
                  await context.pushNamed(
                    SupportRoutes.emailCapture,
                    extra: S.of(context).buyPrimaryEmailRequiredCaptureDescription,
                  );
                  if (context.mounted) {
                    context.read<BuyPaymentInfoCubit>().getPaymentInfo(
                      amount: amountController.text,
                      currency: context.read<BuyConverterCubit>().state.currency,
                    );
                  }
                },
                label: S.of(context).next,
              ),
            );
          }
          if (paymentState.error == PaymentInfoError.primaryEmailNotConfirmed) {
            // The buyer has a primary email on record but has not yet confirmed it.
            // The KYC page auto-routes to its confirm-email step in this case, so
            // route there (no `extra`) instead of to email capture, then re-fetch
            // the quote so a now-confirmed email surfaces the binding-buy CTA.
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: AppFilledButton(
                onPressed: () async {
                  await context.pushNamed(AppRoutes.kyc);
                  if (context.mounted) {
                    context.read<BuyPaymentInfoCubit>().getPaymentInfo(
                      amount: amountController.text,
                      currency: context.read<BuyConverterCubit>().state.currency,
                    );
                  }
                },
                label: S.of(context).next,
              ),
            );
          }
          if (paymentState.error == PaymentInfoError.bitboxDisconnected) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: AppFilledButton(
                onPressed: () async {
                  final paymentInfoCubit = context.read<BuyPaymentInfoCubit>();
                  final converterCubit = context.read<BuyConverterCubit>();
                  await showBitboxReconnectSheet(context);
                  paymentInfoCubit.getPaymentInfo(
                    amount: amountController.text,
                    currency: converterCubit.state.currency,
                  );
                },
                label: S.of(context).bitboxReconnect,
              ),
            );
          }
          if (paymentState.error == PaymentInfoError.unknown) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: AppFilledButton(
                onPressed: () => context.read<BuyPaymentInfoCubit>().getPaymentInfo(
                  amount: amountController.text,
                  currency: context.read<BuyConverterCubit>().state.currency,
                ),
                label: S.of(context).retry,
              ),
            );
          }
        }
        return const SizedBox.shrink();
      },
    );
  }
}
