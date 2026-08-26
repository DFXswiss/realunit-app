import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_blockchain_api_service.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_faucet_service.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/sell_payment_info.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_sell_payment_info_service.dart';
import 'package:realunit_wallet/screens/hardware_connect_bitbox/show_bitbox_reconnect_sheet.dart';
import 'package:realunit_wallet/screens/sell_bitbox/cubit/sell_bitbox_cubit.dart';
import 'package:realunit_wallet/screens/sell_bitbox/widgets/sell_bitbox_deposit_step.dart';
import 'package:realunit_wallet/screens/sell_bitbox/widgets/sell_bitbox_eth_step.dart';
import 'package:realunit_wallet/screens/sell_bitbox/widgets/sell_bitbox_swap_step.dart';
import 'package:realunit_wallet/setup/di.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/handlebars.dart';
import 'package:realunit_wallet/widgets/route_animation_gate.dart';

class SellBitboxPage extends StatelessWidget {
  final SellPaymentInfo paymentInfo;

  const SellBitboxPage({super.key, required this.paymentInfo});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => SellBitboxCubit(
        paymentInfo: paymentInfo,
        faucetService: getIt<DfxFaucetService>(),
        blockchainService: getIt<DfxBlockchainApiService>(),
        sellService: getIt<RealUnitSellPaymentInfoService>(),
        appStore: getIt<AppStore>(),
      ),
      child: RouteAnimationGate(
        onSettled: (c) => c.read<SellBitboxCubit>().start(),
        child: SellBitboxView(paymentInfo: paymentInfo),
      ),
    );
  }
}

class SellBitboxView extends StatelessWidget {
  final SellPaymentInfo paymentInfo;

  const SellBitboxView({super.key, required this.paymentInfo});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<SellBitboxCubit, SellBitboxState>(
      listener: (context, state) async {
        if (state is SellBitboxBitboxRequired) {
          await waitForIncomingRouteAnimation(context);
          if (!context.mounted) {
            return;
          }
          final reconnected = await showBitboxReconnectSheet(context);
          if (reconnected && context.mounted) {
            context.read<SellBitboxCubit>().retryAfterConnection();
          }
          return;
        }
        if (state is SellBitboxError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: RealUnitColors.status.red600,
            ),
          );
        }
        if (state is SellBitboxSuccess) {
          await waitForIncomingRouteAnimation(context);
          if (!context.mounted) {
            return;
          }
          final isSuccess = await _showSuccessSheet(context);
          if (isSuccess == true && context.mounted) {
            context.pop();
          }
        }
      },
      builder: (context, state) {
        final currentStep = _stepIndex(state);
        return Scaffold(
          appBar: AppBar(
            title: Text(S.of(context).sellRealu),
          ),
          body: SafeArea(
            child: Padding(
              padding: const .symmetric(horizontal: 20, vertical: 8),
              child: Column(
                spacing: 32,
                children: [
                  Row(
                    children: List.generate(
                      3,
                      (i) {
                        final isActive = i == currentStep;
                        final isDone = i < currentStep;
                        return Expanded(
                          child: Padding(
                            padding: .only(right: i < 2 ? 8 : 0),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              height: 4,
                              decoration: BoxDecoration(
                                color: (isActive || isDone)
                                    ? RealUnitColors.realUnitBlue
                                    : RealUnitColors.neutral200,
                                borderRadius: .circular(2),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Expanded(child: _buildStep(state)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStep(SellBitboxState state) => switch (state) {
    SellBitboxEthState() => const SellBitboxEthStep(),
    SellBitboxSwapState() => SellBitboxSwapStep(paymentInfo: paymentInfo),
    SellBitboxDepositState() => SellBitboxDepositStep(paymentInfo: paymentInfo),
    SellBitboxError() => const SizedBox.shrink(),
  };

  Future<bool?> _showSuccessSheet(BuildContext context) async {
    return await showModalBottomSheet<bool?>(
      context: context,
      isDismissible: false,
      builder: (_) => SafeArea(
        child: SizedBox(
          width: .infinity,
          child: Padding(
            padding: const .symmetric(horizontal: 20),
            child: Column(
              mainAxisSize: .min,
              spacing: 28.0,
              children: [
                Handlebars.horizontal(context, margin: const .only(top: 5), width: 36),
                const Icon(
                  Icons.check_circle_rounded,
                  color: RealUnitColors.realUnitBlue,
                  size: 64,
                ),
                Column(
                  spacing: 8.0,
                  children: [
                    Text(
                      S.of(context).sellSuccess,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    Text(
                      S.of(context).sellSuccessDescription,
                      textAlign: .center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: RealUnitColors.neutral500,
                      ),
                    ),
                  ],
                ),
                FilledButton(
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.all(RealUnitColors.neutral100),
                    foregroundColor: WidgetStateProperty.all(RealUnitColors.realUnitBlack),
                  ),
                  onPressed: () {
                    context.pop(true);
                  },
                  child: Text(
                    S.of(context).close,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: .w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  int _stepIndex(SellBitboxState state) => switch (state) {
    SellBitboxEthState() => 0,
    SellBitboxSwapState() => 1,
    SellBitboxDepositState() => 2,
    _ => 0,
  };
}
