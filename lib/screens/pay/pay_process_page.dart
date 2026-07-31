import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_blockchain_api_service.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_faucet_service.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_pay_service.dart';
import 'package:realunit_wallet/packages/service/wallet_service.dart';
import 'package:realunit_wallet/screens/pay/cubits/pay_process/pay_process_cubit.dart';
import 'package:realunit_wallet/setup/di.dart';
import 'package:realunit_wallet/styles/colors.dart';

class PayProcessPage extends StatelessWidget {
  final String paymentLinkId;
  final double zchfNeeded;

  const PayProcessPage({
    super.key,
    required this.paymentLinkId,
    required this.zchfNeeded,
  });

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => PayProcessCubit(
        payService: getIt<RealUnitPayService>(),
        faucetService: getIt<DfxFaucetService>(),
        blockchainService: getIt<DfxBlockchainApiService>(),
        walletService: getIt<WalletService>(),
        appStore: getIt<AppStore>(),
        paymentLinkId: paymentLinkId,
        zchfNeeded: zchfNeeded,
      )..start(),
      child: const PayProcessView(),
    );
  }
}

class PayProcessView extends StatelessWidget {
  const PayProcessView({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PayProcessCubit, PayProcessState>(
      listenWhen: (previous, current) =>
          current is PayProcessSuccess ||
          current is PayProcessFailure ||
          current is PayProcessPayRetry,
      listener: (context, state) async {
        if (state is PayProcessSuccess) {
          await _showResultSheet(
            context,
            icon: Icons.check_circle_rounded,
            title: S.of(context).paySuccess,
            description: S.of(context).paySuccessDescription,
          );
        } else if (state is PayProcessPayRetry) {
          // The swap already succeeded — offer to retry the PAY leg only. The
          // ZCHF stays in the wallet; this never re-swaps.
          await _showRetrySheet(context, state.reason);
        } else if (state is PayProcessFailure) {
          await _showResultSheet(
            context,
            icon: Icons.error_rounded,
            title: S.of(context).payFailureTitle,
            description: _failureMessage(context, state.reason),
          );
        }
      },
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(title: Text(S.of(context).pay)),
          body: SafeArea(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: 24,
                children: [
                  const CupertinoActivityIndicator(radius: 16),
                  Text(
                    _progressLabel(context, state),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _progressLabel(BuildContext context, PayProcessState state) => switch (state) {
    PayProcessInitial() || PayProcessPreparingSwap() => S.of(context).payPreparingSwap,
    PayProcessWaitingForEth() => S.of(context).payWaitingForEth,
    PayProcessSwapping() => S.of(context).paySwapping,
    PayProcessRefreshingQuote() => S.of(context).payRefreshingQuote,
    PayProcessPaying() => S.of(context).payPaying,
    PayProcessAwaitingSettlement() => S.of(context).payAwaitingSettlement,
    PayProcessSuccess() => S.of(context).paySuccess,
    PayProcessPayRetry() => S.of(context).payRetryTitle,
    PayProcessFailure() => S.of(context).payFailureTitle,
  };

  String _failureMessage(BuildContext context, PayProcessFailureReason reason) => switch (reason) {
    PayProcessFailureReason.insufficientZchf => S.of(context).payFailureInsufficientZchf,
    PayProcessFailureReason.insufficientEth => S.of(context).payFailureInsufficientEth,
    PayProcessFailureReason.signatureUnsupported => S.of(context).payFailureSignatureUnsupported,
    PayProcessFailureReason.bitboxRequired => S.of(context).payFailureBitboxRequired,
    PayProcessFailureReason.generic => S.of(context).payFailureGeneric,
  };

  String _retryMessage(BuildContext context, PayRetryReason reason) => switch (reason) {
    PayRetryReason.quoteExpired => S.of(context).payRetryQuoteExpired,
    PayRetryReason.transient => S.of(context).payRetryTransient,
    PayRetryReason.insufficientZchf => S.of(context).payRetryInsufficientZchf,
    PayRetryReason.unsignedTxMismatch => S.of(context).payRetryUnsignedTxMismatch,
  };

  Future<void> _showResultSheet(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 24,
            children: [
              Icon(icon, color: RealUnitColors.realUnitBlue, size: 64),
              Text(title, style: Theme.of(context).textTheme.headlineMedium),
              Text(
                description,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: RealUnitColors.neutral500,
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(S.of(context).close),
              ),
            ],
          ),
        ),
      ),
    );
    if (context.mounted) Navigator.of(context).pop();
  }

  /// Recovery sheet shown after a successful swap when the pay leg failed. The
  /// primary action retries the PAY leg only ([PayProcessCubit.retryPay]) — the
  /// swap is never redone, so the ZCHF already held is reused. Dismissing leaves
  /// that ZCHF safely in the wallet.
  Future<void> _showRetrySheet(BuildContext context, PayRetryReason reason) async {
    final cubit = context.read<PayProcessCubit>();
    // The sheet returns true when the user retries (keep the page) and false
    // when they close (leave the flow); a barrier dismissal yields null.
    final retry = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 24,
            children: [
              const Icon(Icons.replay_rounded, color: RealUnitColors.realUnitBlue, size: 64),
              Text(
                S.of(sheetContext).payRetryTitle,
                style: Theme.of(sheetContext).textTheme.headlineMedium,
              ),
              Text(
                _retryMessage(sheetContext, reason),
                textAlign: TextAlign.center,
                style: Theme.of(sheetContext).textTheme.bodyMedium?.copyWith(
                  color: RealUnitColors.neutral500,
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.of(sheetContext).pop(true),
                child: Text(S.of(sheetContext).payRetryButton),
              ),
              TextButton(
                onPressed: () => Navigator.of(sheetContext).pop(false),
                child: Text(S.of(sheetContext).close),
              ),
            ],
          ),
        ),
      ),
    );

    if (retry == true) {
      // Retry the PAY leg only — never re-swaps. Keep the page so the next
      // attempt surfaces its own result.
      await cubit.retryPay();
    } else if (context.mounted) {
      // Closed: leave the flow. The swapped ZCHF stays safely in the wallet.
      Navigator.of(context).pop();
    }
  }
}
