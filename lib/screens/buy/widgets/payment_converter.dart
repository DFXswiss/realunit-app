import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/repository/supported_fiat_repository.dart';
import 'package:realunit_wallet/packages/utils/asset_logo.dart';
import 'package:realunit_wallet/packages/utils/default_assets.dart';
import 'package:realunit_wallet/screens/buy/cubits/buy_converter/buy_converter_cubit.dart';
import 'package:realunit_wallet/setup/di.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/styles/currency.dart';

class PaymentConverter extends StatefulWidget {
  const PaymentConverter({
    super.key,
    required this.amountController,
    required this.resultController,
  });

  final TextEditingController amountController;
  final TextEditingController resultController;

  @override
  State<PaymentConverter> createState() => _PaymentConverterState();
}

class _PaymentConverterState extends State<PaymentConverter> {
  TextEditingController get _amountController => widget.amountController;
  TextEditingController get _resultController => widget.resultController;

  // Backend-authoritative list of buyable currencies for the picker. Loaded
  // once per session via `SupportedFiatRepository` (in-memory cached) so
  // the popup itemBuilder can render synchronously.
  List<Currency> _buyable = const [];
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    getIt<SupportedFiatRepository>().getBuyable().then(
      (currencies) {
        if (mounted) setState(() => _buyable = currencies);
      },
      onError: (Object error, StackTrace stack) {
        developer.log(
          'PaymentConverter: failed to load buyable currencies — picker will '
          'be disabled and the user is notified',
          name: 'realunit_wallet.buy',
          error: error,
          stackTrace: stack,
          level: 1000, // SEVERE
        );
        if (!mounted) return;
        setState(() => _loadFailed = true);
        // Defer to post-frame so we have a Scaffold ancestor in scope.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(S.of(context).settingsCurrencyLoadFailed),
              backgroundColor: RealUnitColors.status.red600,
            ),
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: .start,
      children: [
        Padding(
          padding: const .symmetric(
            horizontal: 12.0,
            vertical: 4.0,
          ),
          child: Text(
            S.of(context).youPay,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: .bold,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            borderRadius: .circular(8.0),
            border: Border.all(color: RealUnitColors.neutral300),
          ),
          child: ClipRRect(
            borderRadius: .circular(8.0),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _amountController,
                    keyboardType: const .numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                    decoration: const InputDecoration(
                      border: .none,
                      contentPadding: .symmetric(
                        horizontal: 10.0,
                        vertical: 14.0,
                      ),
                    ),
                    maxLines: 1,
                    onChanged: (value) => context.read<BuyConverterCubit>().onFiatChanged(value),
                  ),
                ),
                Container(
                  color: RealUnitColors.neutral300,
                  width: 1,
                  height: 52,
                ),
                Expanded(
                  flex: 2,
                  child: Container(
                    color: RealUnitColors.neutral50,
                    child: BlocBuilder<BuyConverterCubit, BuyConverterState>(
                      builder: (context, state) {
                        return PopupMenuButton<Currency>(
                          key: _loadFailed
                              ? const Key('buy-currency-picker-disabled')
                              : const Key('buy-currency-picker'),
                          enabled: !_loadFailed && _buyable.isNotEmpty,
                          initialValue: state.currency,
                          onSelected: (currency) {
                            if (currency == state.currency) return;
                            context.read<BuyConverterCubit>().onCurrencyChanged(currency);
                          },
                          itemBuilder: (context) => _buyable.map((currency) {
                            return PopupMenuItem(
                              value: currency,
                              child: Column(
                                mainAxisSize: .min,
                                crossAxisAlignment: .start,
                                children: [
                                  Text(
                                    currency.code,
                                    overflow: .ellipsis,
                                    style:
                                        Theme.of(
                                          context,
                                        ).textTheme.bodyLarge?.copyWith(
                                          fontWeight: .bold,
                                        ),
                                  ),
                                  Text(
                                    currency.name,
                                    overflow: .ellipsis,
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                          child: Padding(
                            padding: const EdgeInsets.only(
                              top: 8.0,
                              bottom: 8.0,
                              left: 10.0,
                              right: 4.0,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    mainAxisSize: .min,
                                    crossAxisAlignment: .start,
                                    children: [
                                      Text(
                                        state.currency.code,
                                        overflow: .ellipsis,
                                        style:
                                            Theme.of(
                                              context,
                                            ).textTheme.bodyLarge?.copyWith(
                                              fontWeight: .bold,
                                            ),
                                      ),
                                      Text(
                                        state.currency.name,
                                        overflow: .ellipsis,
                                        style: Theme.of(context).textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.arrow_drop_down),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        BlocBuilder<BuyConverterCubit, BuyConverterState>(
          builder: (context, state) {
            if (!_showsExactCharge(state)) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const .symmetric(
                horizontal: 12.0,
                vertical: 4.0,
              ),
              child: Text(
                S.of(context).buyChargedAmount(state.payableText, state.currency.code),
                key: const Key('buy-charged-amount'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: RealUnitColors.neutral600,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 32),
        Padding(
          padding: const .symmetric(
            horizontal: 12.0,
            vertical: 4.0,
          ),
          child: Text(
            S.of(context).youReceive,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: .bold,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            border: .all(color: RealUnitColors.neutral300),
            borderRadius: .circular(8.0),
          ),
          child: ClipRRect(
            borderRadius: .circular(8.0),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _resultController,
                    keyboardType: const .numberWithOptions(
                      decimal: false,
                    ),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      border: .none,
                      contentPadding: .symmetric(
                        horizontal: 10.0,
                        vertical: 14.0,
                      ),
                    ),
                    maxLines: 1,
                    onChanged: (value) => context.read<BuyConverterCubit>().onSharesChanged(value),
                  ),
                ),
                Container(
                  color: RealUnitColors.neutral300,
                  width: 1,
                  height: 52,
                ),
                Expanded(
                  flex: 2,
                  child: Container(
                    color: RealUnitColors.neutral50,
                    padding: const .only(
                      top: 8.0,
                      bottom: 8.0,
                      left: 10.0,
                      right: 4.0,
                    ),
                    child: Row(
                      spacing: 8,
                      children: [
                        Image.asset(
                          getAssetImagePath(realUnitAsset),
                          height: 24,
                          width: 24,
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: .start,
                            children: [
                              Text(
                                realUnitAsset.symbol,
                                overflow: .ellipsis,
                                style:
                                    Theme.of(
                                      context,
                                    ).textTheme.bodyLarge?.copyWith(
                                      fontWeight: .bold,
                                    ),
                              ),
                              Text(
                                realUnitAsset.name,
                                overflow: .ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // payableText is always two fractional digits; fiatText is raw keystrokes
  // ('300' vs '300.00'). Compare numerically so an exact match stays hidden.
  bool _showsExactCharge(BuyConverterState state) {
    if (state.payableText.isEmpty || state.payableText == state.fiatText) {
      return false;
    }
    final fiat = num.tryParse(state.fiatText.replaceAll(',', '.'));
    final payable = num.tryParse(state.payableText.replaceAll(',', '.'));
    if (fiat != null && payable != null) {
      return fiat != payable;
    }
    return true;
  }
}
