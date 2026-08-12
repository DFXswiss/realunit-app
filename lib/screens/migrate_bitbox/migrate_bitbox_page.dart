import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/balance_service.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_kyc_service.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_registration_service.dart';
import 'package:realunit_wallet/packages/service/wallet_service.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';
import 'package:realunit_wallet/screens/hardware_connect_bitbox/connect_bitbox_page.dart';
import 'package:realunit_wallet/screens/home/bloc/home_bloc.dart';
import 'package:realunit_wallet/screens/migrate_bitbox/cubits/migrate_bitbox/migrate_bitbox_cubit.dart';
import 'package:realunit_wallet/screens/migrate_bitbox/widgets/migrate_intro_view.dart';
import 'package:realunit_wallet/screens/migrate_bitbox/widgets/migrate_register_view.dart';
import 'package:realunit_wallet/screens/migrate_bitbox/widgets/migrate_result_views.dart';
import 'package:realunit_wallet/screens/migrate_bitbox/widgets/migrate_transfer_view.dart';
import 'package:realunit_wallet/setup/di.dart';

class MigrateBitboxPage extends StatelessWidget {
  const MigrateBitboxPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => MigrateBitboxCubit(
      getIt<WalletService>(),
      // DfxKycService serves purely as the auth transport here
      // (refreshAuthToken / authenticateLinkedAccount); no KYC-specific calls.
      getIt<DfxKycService>(),
      getIt<RealUnitRegistrationService>(),
      getIt<BalanceService>(),
      getIt<AppStore>(),
    ),
    child: const MigrateBitboxViewManager(),
  );
}

class MigrateBitboxViewManager extends StatelessWidget {
  const MigrateBitboxViewManager({super.key});

  @override
  Widget build(BuildContext context) => BlocConsumer<MigrateBitboxCubit, MigrateBitboxState>(
    listenWhen: (_, current) =>
        current is MigrateBitboxAwaitingDevice || current is MigrateBitboxSuccess,
    listener: (context, state) async {
      // Synchronous context use first: the await in the AwaitingDevice branch
      // below would otherwise trip use_build_context_synchronously for every
      // context read that follows it in this async closure.
      if (state is MigrateBitboxSuccess) {
        context.read<HomeBloc>().add(LoadWalletEvent(state.wallet));
        return;
      }
      if (state is MigrateBitboxAwaitingDevice) {
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (sheetContext) => ConnectBitboxPage(
            acquireWallet: () =>
                getIt<WalletService>().acquireUncommittedBitboxWallet('Luke-Skywallet'),
            onFinish: (wallet) {
              Navigator.of(sheetContext).pop();
              context.read<MigrateBitboxCubit>().onDevicePaired(wallet as BitboxWallet);
            },
          ),
        );
        if (context.mounted) {
          context.read<MigrateBitboxCubit>().cancelPairing();
        }
      }
    },
    builder: (context, state) => PopScope(
      canPop: switch (state) {
        MigrateBitboxIntro() ||
        MigrateBitboxRegisterReady() ||
        MigrateBitboxTransferReady() ||
        MigrateBitboxRegistrationPending() ||
        MigrateBitboxSettlingTimeout() ||
        MigrateBitboxFailure() ||
        MigrateBitboxSuccess() => true,
        _ => false,
      },
      child: switch (state) {
        MigrateBitboxIntro() || MigrateBitboxAwaitingDevice() => const MigrateIntroView(),
        MigrateBitboxLinking() => _MigrateBitboxProgressPage(
          label: S.of(context).migrateBitboxLinking,
        ),
        MigrateBitboxRegisterReady(:final userData, :final bitboxAddress) =>
          MigrateRegisterView(
            account: context.read<MigrateBitboxCubit>().draftAccount,
            bearerToken: context.read<MigrateBitboxCubit>().linkedJwt,
            userData: userData,
            bitboxAddress: bitboxAddress,
          ),
        MigrateBitboxRegistrationPending() =>
          const MigrateBitboxRegistrationPendingPage(),
        MigrateBitboxTransferReady(:final fromAddress, :final toAddress, :final amount) =>
          MigrateTransferReadyView(
            fromAddress: fromAddress,
            toAddress: toAddress,
            amount: amount,
          ),
        MigrateBitboxTransferring(:final toAddress, :final amount) => MigrateTransferringView(
          toAddress: toAddress,
          amount: amount,
        ),
        MigrateBitboxSettling() => _MigrateBitboxProgressPage(
          label: S.of(context).migrateBitboxSettling,
        ),
        MigrateBitboxSettlingTimeout() =>
          const MigrateBitboxSettlingTimeoutPage(),
        MigrateBitboxPreparingTransfer() => _MigrateBitboxProgressPage(
          label: S.of(context).migrateBitboxPreparingTransfer,
        ),
        MigrateBitboxCompleting() => _MigrateBitboxProgressPage(
          label: S.of(context).migrateBitboxCompleting,
        ),
        MigrateBitboxSuccess() => const MigrateBitboxSuccessPage(),
        MigrateBitboxFailure(:final reason, :final message, :final canRetry) =>
          MigrateBitboxFailurePage(
          reason: reason,
          message: message,
          canRetry: canRetry,
        ),
      },
    ),
  );
}

class _MigrateBitboxProgressPage extends StatelessWidget {
  const _MigrateBitboxProgressPage({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(S.of(context).migrateBitbox)),
    body: SafeArea(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 16,
          children: [
            const CupertinoActivityIndicator(radius: 16),
            Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    ),
  );
}
