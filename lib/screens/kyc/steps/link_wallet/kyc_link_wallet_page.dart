import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/models/user/dto/real_unit_user_data_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_registration_service.dart';
import 'package:realunit_wallet/screens/hardware_connect_bitbox/connect_bitbox_page.dart';
import 'package:realunit_wallet/screens/home/bloc/home_bloc.dart';
import 'package:realunit_wallet/screens/kyc/cubits/kyc/kyc_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/link_wallet/cubits/kyc_link_wallet_cubit.dart';
import 'package:realunit_wallet/setup/di.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';
import 'package:realunit_wallet/widgets/scrollable_actions_layout.dart';

class KycLinkWalletPage extends StatelessWidget {
  /// Server-supplied user data the parent `KycCubit` already fetched as part
  /// of its routing decision. The backend always populates this for
  /// `AddWallet`, so `null` is treated as an unexpected state — the page
  /// surfaces a retry button that re-fires the parent cubit's `checkKyc()`.
  final RealUnitUserDataDto? userData;

  const KycLinkWalletPage({super.key, this.userData});

  @override
  Widget build(BuildContext context) {
    final data = userData;
    if (data == null) {
      return const _LinkWalletMissingUserDataPage();
    }
    return BlocProvider(
      create: (_) => KycLinkWalletCubit(getIt<RealUnitRegistrationService>(), data),
      child: const KycLinkWalletView(),
    );
  }
}

class KycLinkWalletView extends StatelessWidget {
  const KycLinkWalletView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.of(context).kycLinkWalletTitle)),
      body: BlocConsumer<KycLinkWalletCubit, KycLinkWalletState>(
        listenWhen: (_, current) =>
            current is KycLinkWalletSuccess ||
            current is KycLinkWalletFailure ||
            current is KycLinkWalletBitboxRequired,
        listener: (context, state) async {
          if (state is KycLinkWalletSuccess) {
            // Re-fetch routing state from the API. The wallet is now in the
            // Aktionariat share register, so `getRegistrationInfo` will return
            // `AlreadyRegistered` and `_runCheckKyc` will dispatch the next
            // KYC step.
            context.read<KycCubit>().checkKyc();
          }
          if (state is KycLinkWalletFailure) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(S.of(context).registrationFailed(state.message)),
                backgroundColor: RealUnitColors.status.red600,
              ),
            );
          }
          if (state is KycLinkWalletBitboxRequired) {
            // No BitBox connected when registering the wallet — open the
            // shared connect sheet instead of dead-ending on an error, then
            // retry registration once the device is linked. Mirror of
            // `KycRegistrationPage`.
            final userData = state.userData;
            final result = await showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (_) => ConnectBitboxPage(
                onFinish: (wallet) {
                  context.read<HomeBloc>().add(SyncWalletServicesEvent(wallet));
                  context.pop(true);
                },
              ),
            );
            if (context.mounted && result == true) {
              context.read<KycLinkWalletCubit>().retrySubmit(userData);
            }
          }
        },
        builder: (context, state) => switch (state) {
          KycLinkWalletReady(:final userData) => _LinkWalletBody(
            userData: userData,
            isSubmitting: false,
          ),
          KycLinkWalletSubmitting(:final userData) => _LinkWalletBody(
            userData: userData,
            isSubmitting: true,
          ),
          // BitBox required: the listener drives the connect sheet on top of
          // this frame; render the idle confirm body so the user lands back on
          // the submit button if they dismiss the sheet without connecting.
          KycLinkWalletBitboxRequired(:final userData) => _LinkWalletBody(
            userData: userData,
            isSubmitting: false,
          ),
          // Success: the Bloc listener kicks off `checkKyc` which transitions
          // the parent KycCubit, so this branch is a transient frame. Render
          // the spinner to avoid a flash of the form.
          KycLinkWalletSuccess() => const Center(child: CupertinoActivityIndicator()),
          KycLinkWalletState() => const Center(child: CupertinoActivityIndicator()),
        },
      ),
    );
  }
}

class _LinkWalletBody extends StatelessWidget {
  const _LinkWalletBody({required this.userData, required this.isSubmitting});

  final RealUnitUserDataDto userData;
  final bool isSubmitting;

  @override
  Widget build(BuildContext context) {
    final walletAddress = getIt<AppStore>().wallet.primaryAccount.primaryAddress.address.hexEip55;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: SafeArea(
        child: ScrollableActionsLayout(
          centerBody: false,
          body: Column(
            spacing: 16.0,
            children: [
              const SizedBox(height: 16.0),
              Text(
                S.of(context).kycLinkWalletDescription,
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              _LinkWalletInfoRow(label: S.of(context).name, value: userData.name),
              _LinkWalletInfoRow(label: S.of(context).walletAddress, value: walletAddress),
            ],
          ),
          actions: [
            AppFilledButton(
              state: isSubmitting ? FilledButtonState.loading : FilledButtonState.idle,
              onPressed: isSubmitting
                  ? null
                  : () => context.read<KycLinkWalletCubit>().submit(userData),
              label: S.of(context).kycLinkWalletSubmit,
            ),
            const SizedBox(height: 16.0),
          ],
        ),
      ),
    );
  }
}

class _LinkWalletInfoRow extends StatelessWidget {
  const _LinkWalletInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 4.0,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: RealUnitColors.neutral500),
        ),
        Text(value, style: Theme.of(context).textTheme.bodyLarge),
      ],
    );
  }
}

/// Defensive surface when the parent `KycCubit` routed to `linkWallet` but
/// did not supply userData. In practice the backend always pairs `AddWallet`
/// with userData, so this is a hard edge case — the user retries the routing
/// decision rather than re-fetching the wallet status from the page itself.
class _LinkWalletMissingUserDataPage extends StatelessWidget {
  const _LinkWalletMissingUserDataPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(S.of(context).kycLinkWalletTitle)),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0),
        child: SafeArea(
          child: ScrollableActionsLayout(
            centerBody: true,
            body: Text(
              S.of(context).kycFailure,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            actions: [
              AppFilledButton(
                onPressed: () => context.read<KycCubit>().checkKyc(),
                label: S.of(context).refresh,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
