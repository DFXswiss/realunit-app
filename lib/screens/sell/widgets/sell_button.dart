import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/models/bank_account/bank_account.dart';
import 'package:realunit_wallet/screens/hardware_connect_bitbox/show_bitbox_reconnect_sheet.dart';
import 'package:realunit_wallet/screens/sell/cubits/sell_converter/sell_converter_cubit.dart';
import 'package:realunit_wallet/screens/sell/cubits/sell_payment_info/sell_payment_info_cubit.dart';
import 'package:realunit_wallet/screens/sell/widgets/sell_confirm_sheet.dart';
import 'package:realunit_wallet/screens/sell/widgets/sell_executed_sheet.dart';
import 'package:realunit_wallet/setup/routing/routes/app_routes.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';

class SellButton extends StatelessWidget {
  final String amount;
  final BankAccount? bankAccount;

  const SellButton({super.key, required this.amount, required this.bankAccount});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<SellPaymentInfoCubit, SellPaymentInfoState>(
      listener: (context, state) async {
        if (state is SellPaymentInfoFailure) {
          if (state.error == .kycRequired) {
            await context.pushNamed(AppRoutes.kyc, extra: state.context);
            return;
          }
          if (state.error == .registrationRequired) {
            await context.pushNamed(AppRoutes.kyc, extra: state.context);
            return;
          }
          if (state.error == .bitboxDisconnected) {
            final paymentInfoCubit = context.read<SellPaymentInfoCubit>();
            final converterCurrency = context.read<SellConverterCubit>().state.currency;
            await showBitboxReconnectSheet(context);
            if (bankAccount != null && amount.isNotEmpty) {
              paymentInfoCubit.getPaymentInfo(
                amount: amount,
                iban: bankAccount!.iban,
                currency: converterCurrency,
              );
            }
            return;
          }
          if (state.error == .priceSourceUnavailable) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(S.of(context).priceProviderUnavailableTitle),
                  backgroundColor: RealUnitColors.status.red600,
                ),
              );
            }
            return;
          }
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: RealUnitColors.status.red600,
              ),
            );
          }
        }
        if (state is SellPaymentInfoSuccess) {
          if (state.isBitbox && context.mounted) {
            context.pushNamed(AppRoutes.sellBitbox, extra: state.sellPaymentInfo);
            return;
          } else {
            final bool? confirmedSuccess = await showModalBottomSheet(
              isScrollControlled: true,
              context: context,
              builder: (_) => SellConfirmSheet(
                paymentInfo: state.sellPaymentInfo,
              ),
            );
            if (confirmedSuccess ?? false) {
              if (context.mounted) {
                await showModalBottomSheet(
                  isScrollControlled: true,
                  context: context,
                  builder: (_) => const SellExecutedSheet(),
                );
              }
              if (context.mounted) context.pop();
            }
          }
        }
      },
      builder: (context, state) {
        final converterState = context.watch<SellConverterCubit>().state;

        if (state is SellPaymentInfoLoading) {
          return Padding(
            padding: const .symmetric(vertical: 20),
            child: AppFilledButton(
              state: .loading,
              label: '$amount ${S.of(context).sellRealu}',
            ),
          );
        }
        if (state is SellPaymentInfoMinAmountNotMet) {
          return Padding(
            padding: const .symmetric(vertical: 20),
            child: Column(
              spacing: 8.0,
              children: [
                Text(
                  S
                      .of(context)
                      .sellMinAmount(
                        '${state.minAmount.ceil()}',
                        state.currency.code,
                      ),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: RealUnitColors.neutral500,
                  ),
                ),
                AppFilledButton(
                  onPressed: null,
                  label: '$amount ${S.of(context).sellRealu}',
                ),
              ],
            ),
          );
        }
        if (bankAccount != null && amount.isNotEmpty) {
          return Padding(
            padding: const .symmetric(vertical: 20),
            child: AppFilledButton(
              onPressed: () => context.read<SellPaymentInfoCubit>().getPaymentInfo(
                amount: amount,
                iban: bankAccount!.iban,
                currency: converterState.currency,
              ),
              label: '$amount ${S.of(context).sellRealu}',
            ),
          );
        }
        return Padding(
          padding: const .symmetric(vertical: 20),
          child: AppFilledButton(
            onPressed: null,
            label: '$amount ${S.of(context).sellRealu}',
          ),
        );
      },
    );
  }
}
