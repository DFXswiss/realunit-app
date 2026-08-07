import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/sell_payment_info.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_sell_payment_info_service.dart';
import 'package:realunit_wallet/packages/utils/default_assets.dart';
import 'package:realunit_wallet/screens/sell/cubits/sell_confirm/sell_confirm_cubit.dart';
import 'package:realunit_wallet/setup/di.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';
import 'package:realunit_wallet/widgets/handlebars.dart';
import 'package:realunit_wallet/widgets/iban_text_formatter.dart';
import 'package:realunit_wallet/widgets/scrollable_actions_layout.dart';

class SellConfirmSheet extends StatelessWidget {
  final SellPaymentInfo paymentInfo;

  const SellConfirmSheet({super.key, required this.paymentInfo});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => SellConfirmCubit(
        getIt<RealUnitSellPaymentInfoService>(),
      ),
      child: SellConfirmSheetView(
        paymentInfo: paymentInfo,
      ),
    );
  }
}

class SellConfirmSheetView extends StatelessWidget {
  final SellPaymentInfo paymentInfo;

  const SellConfirmSheetView({super.key, required this.paymentInfo});

  @override
  Widget build(BuildContext context) {
    return BlocListener<SellConfirmCubit, SellConfirmState>(
      listener: (context, state) async {
        if (state is SellConfirmFailure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.error),
              backgroundColor: RealUnitColors.status.red600,
            ),
          );
        }
        if (state is SellConfirmSuccess) {
          context.pop(true);
        }
      },
      child: SafeArea(
        child: SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Handlebars.horizontal(context, margin: const EdgeInsets.only(top: 5), width: 36),
                // Handlebar stays OUTSIDE the scrollable body (sibling above it) —
                // it must never scroll away with the content.
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.9,
                  ),
                  child: ScrollableActionsLayout(
                    shrinkWrap: true,
                    body: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24.0),
                          child: Text(
                            S.of(context).sellReviewAndConfirm,
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: RealUnitColors.neutral200),
                            borderRadius: BorderRadius.circular(16.0),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: _withDividers(
                              children: [
                                _infoRow(
                                  label: realUnitAsset.symbol,
                                  value: '${paymentInfo.amount}',
                                ),
                                _infoRow(
                                  label:
                                      '${S.of(context).amountIn} ${paymentInfo.currency.code}',
                                  value: '${paymentInfo.estimatedAmount}',
                                ),
                                _infoRow(
                                  label: S.of(context).receiver,
                                  value: IbanTextFormatter.formatIban(paymentInfo.beneficiary.iban),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: BlocBuilder<SellConfirmCubit, SellConfirmState>(
                          builder: (context, state) {
                            final isLoading = state is SellConfirmLoading;
                            return AppFilledButton(
                              label: S.of(context).confirm,
                              onPressed: () =>
                                  context.read<SellConfirmCubit>().confirmPayment(paymentInfo),
                              state: isLoading ? .loading : .idle,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Label/value row: both sides are Flexible and WRAP (not ellipsize) so a long
  /// value (e.g. a beneficiary IBAN) always stays fully readable — the sheet
  /// scrolls, so extra height here is absorbed, never data loss via truncation.
  /// Wrapping also prevents horizontal RenderFlex overflow for either side.
  Widget _infoRow({required String label, required String value}) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 12.0,
        horizontal: 20.0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              softWrap: true,
              style: const TextStyle(
                color: RealUnitColors.neutral500,
                height: 18 / 14,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              softWrap: true,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                height: 18 / 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _withDividers({required List<Widget> children}) {
    final result = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      result.add(children[i]);
      if (i < children.length - 1) {
        result.add(
          const Divider(
            color: RealUnitColors.neutral200,
          ),
        );
      }
    }
    return result;
  }
}
