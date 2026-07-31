import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_pay_service.dart';
import 'package:realunit_wallet/packages/utils/default_assets.dart';
import 'package:realunit_wallet/screens/pay/cubits/pay_quote/pay_quote_cubit.dart';
import 'package:realunit_wallet/screens/pay/pay_process_page.dart';
import 'package:realunit_wallet/setup/di.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/scrollable_actions_layout.dart';

class PayQuotePage extends StatelessWidget {
  final String paymentLinkId;

  const PayQuotePage({super.key, required this.paymentLinkId});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => PayQuoteCubit(getIt<RealUnitPayService>(), paymentLinkId)..load(),
      child: const PayQuoteView(),
    );
  }
}

class PayQuoteView extends StatelessWidget {
  const PayQuoteView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.of(context).payQuoteTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: BlocBuilder<PayQuoteCubit, PayQuoteState>(
            builder: (context, state) => switch (state) {
              PayQuoteLoading() => const Center(child: CupertinoActivityIndicator()),
              PayQuoteReady() => _PayQuoteReadyView(state: state),
              PayQuoteExpired() => _PayQuoteMessage(message: S.of(context).payFailureQuoteExpired),
              PayQuoteUnavailable() => _PayQuoteMessage(message: S.of(context).payQuoteUnavailable),
              PayQuoteError() => _PayQuoteMessage(
                message: S.of(context).payFailureGeneric,
                onRetry: () => context.read<PayQuoteCubit>().load(),
              ),
            },
          ),
        ),
      ),
    );
  }
}

class _PayQuoteReadyView extends StatefulWidget {
  final PayQuoteReady state;

  const _PayQuoteReadyView({required this.state});

  @override
  State<_PayQuoteReadyView> createState() => _PayQuoteReadyViewState();
}

class _PayQuoteReadyViewState extends State<_PayQuoteReadyView> {
  bool _navigating = false;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return ScrollableActionsLayout(
      centerBody: true,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 24,
        children: [
          Text(
            S
                .of(context)
                .payQuoteSummary(
                  state.fiatAmount.toStringAsFixed(2),
                  state.fiatAsset,
                ),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          if (state.merchantName != null) ...[
            _AmountRow(
              label: S.of(context).payQuoteMerchant,
              value: state.merchantCity != null
                  ? '${state.merchantName}, ${state.merchantCity}'
                  : state.merchantName!,
            ),
          ],
          _AmountRow(
            label: S.of(context).payQuoteRequested,
            value: '${state.fiatAmount.toStringAsFixed(2)} ${state.fiatAsset}',
          ),
          _AmountRow(
            label: S.of(context).payQuoteZchfNeeded,
            value: '${state.zchfAmount.toStringAsFixed(2)} ZCHF',
          ),
          if (state.realuAmount != null) ...[
            _AmountRow(
              label: S.of(context).payQuoteRealuAmount,
              value: '${state.realuAmount!.toStringAsFixed(0)} ${realUnitAsset.symbol}',
            ),
          ],
          if (state.realuEstimatedZchf != null) ...[
            _AmountRow(
              label: S.of(context).payQuoteRealuEstimated,
              value: '${state.realuEstimatedZchf!.toStringAsFixed(2)} ZCHF',
            ),
          ],
          if (state.realuFeesTotal != null) ...[
            _AmountRow(
              label: S.of(context).payQuoteRealuFees,
              value: '${state.realuFeesTotal!.toStringAsFixed(2)} ${realUnitAsset.symbol}',
            ),
          ],
        ],
      ),
      actions: [
        FilledButton(
          onPressed: _navigating
              ? null
              : () {
                  setState(() => _navigating = true);
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PayProcessPage(
                        paymentLinkId: state.paymentLinkId,
                        zchfNeeded: state.zchfAmount,
                      ),
                    ),
                  );
                },
          child: Text(S.of(context).payConfirmButton),
        ),
      ],
    );
  }
}

class _AmountRow extends StatelessWidget {
  final String label;
  final String value;

  const _AmountRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 16,
      children: [
        Flexible(
          child: Text(
            label,
            softWrap: true,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: RealUnitColors.neutral500,
            ),
          ),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            softWrap: true,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      ],
    );
  }
}

class _PayQuoteMessage extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const _PayQuoteMessage({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: RealUnitColors.neutral500,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            OutlinedButton(
              key: const ValueKey('payQuoteRetryButton'),
              onPressed: onRetry,
              child: Text(S.of(context).retry),
            ),
          ],
        ],
      ),
    );
  }
}
