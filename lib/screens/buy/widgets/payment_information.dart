import 'package:flutter/cupertino.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/payment_info_error.dart';
import 'package:realunit_wallet/screens/buy/cubits/buy_payment_info/buy_payment_info_cubit.dart';
import 'package:realunit_wallet/screens/buy/widgets/payment_action_required.dart';

class PaymentInformation extends StatelessWidget {
  const PaymentInformation({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BuyPaymentInfoCubit, BuyPaymentInfoState>(
      builder: (context, paymentInfoState) {
        // On success the primary CTA ("Jetzt verbindlich kaufen") is rendered
        // by PaymentActionButton at the bottom of the page — the bank-transfer
        // details have moved to the BuyPaymentDetailsPage shown after confirm.
        if (paymentInfoState is BuyPaymentInfoLoading) {
          return const Center(
            child: CupertinoActivityIndicator(),
          );
        }
        if (paymentInfoState is BuyPaymentInfoFailure) {
          final error = paymentInfoState.error;
          if (error == PaymentInfoError.registrationRequired) {
            return PaymentActionRequired(
              title: S.of(context).registrationRequired,
              description: S.of(context).registrationRequiredDescription,
            );
          } else if (error == PaymentInfoError.kycRequired) {
            return PaymentActionRequired(
              title: S.of(context).identityCheckRequired,
              description: S.of(context).identityCheckDescription,
            );
          } else if (error == PaymentInfoError.bitboxDisconnected) {
            return PaymentActionRequired(
              title: S.of(context).bitboxDisconnectedTitle,
              description: S.of(context).bitboxDisconnectedDescription,
            );
          } else if (error == PaymentInfoError.priceSourceUnavailable ||
              error == PaymentInfoError.unknown) {
            return PaymentActionRequired(
              title: paymentInfoState.message,
              description: '',
            );
          }
        }
        return const SizedBox.shrink();
      },
    );
  }
}
