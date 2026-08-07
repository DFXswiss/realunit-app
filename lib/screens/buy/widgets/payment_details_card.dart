import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/buy/buy_payment_info.dart';
import 'package:realunit_wallet/packages/utils/svg_parser.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/iban_text_formatter.dart';
import 'package:realunit_wallet/widgets/tab_selector.dart';

enum PaymentInfoOptions {
  text,
  qrCode,
}

/// Bank-transfer instructions for a confirmed buy order: IBAN/BIC/receiver and
/// the purpose of payment, plus an optional QR-code tab. Pure presentation —
/// it renders the [BuyPaymentInfo] the API returned for the [amount] the user
/// committed to. Shown on the `Zahlungsdetails` page after the buy is binding.
class PaymentDetailsCard extends StatelessWidget {
  final String amount;
  final BuyPaymentInfo buyPaymentInfo;
  final String purposeOfPayment;
  final String? paymentRequest;

  const PaymentDetailsCard({
    super.key,
    required this.buyPaymentInfo,
    required this.amount,
    required this.purposeOfPayment,
    this.paymentRequest,
  });

  @override
  Widget build(BuildContext context) {
    final selectedTab = ValueNotifier(PaymentInfoOptions.text);
    final hasQrCode = paymentRequest != null;

    return ValueListenableBuilder<PaymentInfoOptions>(
      valueListenable: selectedTab,
      builder: (context, tabIndex, _) {
        return Column(
          spacing: 12,
          children: [
            if (hasQrCode)
              TabSelector<PaymentInfoOptions>(
                tabs: PaymentInfoOptions.values,
                selectedTab: selectedTab.value,
                onTabSelected: (index) => selectedTab.value = index,
                labelBuilder: (context, tab, isSelected) {
                  return Text(
                    switch (tab) {
                      PaymentInfoOptions.text => S.of(context).details,
                      PaymentInfoOptions.qrCode => S.of(context).qrCode,
                    },
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: isSelected ? .w600 : .normal,
                      color: isSelected
                          ? RealUnitColors.realUnitBlue
                          : RealUnitColors.neutral500,
                    ),
                  );
                },
              ),
            Container(
              decoration: BoxDecoration(
                border: Border.all(
                  width: 1,
                  color: RealUnitColors.neutral200,
                ),
                borderRadius: .circular(16.0),
              ),
              child: switch (tabIndex) {
                PaymentInfoOptions.text => Column(
                  mainAxisSize: .min,
                  children: _withDividers(
                    children: [
                      _PaymentDetailsRow(
                        description: '${S.of(context).amountIn} ${buyPaymentInfo.currency.code}',
                        value: amount,
                      ),
                      if (purposeOfPayment.isNotEmpty)
                        _PaymentDetailsRow(
                          description: S.of(context).purposeOfPayment,
                          value: purposeOfPayment,
                        ),
                      _PaymentDetailsRow(
                        description: S.of(context).iban,
                        value: IbanTextFormatter.formatIban(buyPaymentInfo.iban),
                        copyValue: buyPaymentInfo.iban,
                      ),
                      _PaymentDetailsRow(
                        description: S.of(context).bic,
                        value: buyPaymentInfo.bic,
                      ),
                      _PaymentDetailsRow(
                        title: S.of(context).receiver,
                        description: S.of(context).name,
                        value: buyPaymentInfo.name,
                      ),
                      _PaymentDetailsRow(
                        description: S.of(context).address,
                        value: '${buyPaymentInfo.street} ${buyPaymentInfo.number}',
                      ),
                      _PaymentDetailsRow(
                        description: S.of(context).postcodeAbr,
                        value: buyPaymentInfo.zip,
                      ),
                      _PaymentDetailsRow(
                        description: S.of(context).location,
                        value: buyPaymentInfo.city,
                      ),
                      _PaymentDetailsRow(
                        description: S.of(context).country,
                        value: buyPaymentInfo.country,
                      ),
                    ],
                  ),
                ),
                PaymentInfoOptions.qrCode => Container(
                  padding: const .all(16.0),
                  child: Center(
                    child: paymentRequest!.contains('<svg')
                        ? SvgPicture.string(
                            SvgParser.normalize(paymentRequest!),
                            width: MediaQuery.widthOf(context) * 0.6,
                            fit: .contain,
                          )
                        : SizedBox(
                            height: MediaQuery.widthOf(context) * 0.6,
                            width: MediaQuery.widthOf(context) * 0.6,
                            child: QrImageView(
                              data: paymentRequest!,
                            ),
                          ),
                  ),
                ),
              },
            ),
          ],
        );
      },
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

class _PaymentDetailsRow extends StatelessWidget {
  const _PaymentDetailsRow({
    this.title,
    required this.description,
    required this.value,
    this.copyValue,
  });

  final String? title;
  final String description;
  final String value;
  final String? copyValue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 20.0,
        vertical: 12.0,
      ),
      child: Column(
        spacing: 20.0,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Text(
              title!,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                height: 18 / 14,
                letterSpacing: 0.0,
              ),
            ),
          Row(
            spacing: 12.0,
            children: [
              Text(
                description,
                style: const TextStyle(
                  color: RealUnitColors.realUnitBlue,
                  fontSize: 14,
                  height: 18 / 14,
                  letterSpacing: 0.0,
                ),
              ),
              Expanded(
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    height: 18 / 14,
                    letterSpacing: 0.0,
                  ),
                ),
              ),
              InkWell(
                child: const Icon(
                  Icons.copy_outlined,
                  color: RealUnitColors.realUnitBlue,
                  fontWeight: FontWeight.bold,
                  size: 16,
                ),
                onTap: () => Clipboard.setData(
                  ClipboardData(
                    text: copyValue ?? value,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
