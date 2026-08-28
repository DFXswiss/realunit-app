import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:go_router/go_router.dart';
import 'package:web3dart/web3dart.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/wallet/payment_uri.dart';
import 'package:realunit_wallet/screens/receive/widgets/qr_address_widget.dart';
import 'package:realunit_wallet/screens/settings/bloc/settings_bloc.dart';
import 'package:realunit_wallet/setup/di.dart';
import 'package:realunit_wallet/setup/routing/routes/app_routes.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';
import 'package:realunit_wallet/widgets/scrollable_actions_layout.dart';

class SettingsWalletAddressPage extends StatelessWidget {
  const SettingsWalletAddressPage({super.key});

  @override
  Widget build(BuildContext context) {
    final insiderFeaturesUnlocked =
        context.watch<SettingsBloc>().state.insiderFeaturesUnlocked;
    // Display the receive address in its EIP-55 checksummed form — the
    // canonical representation that lets the user verify it by checksum.
    final walletAddress = EthereumAddress.fromHex(getIt<AppStore>().primaryAddress).hexEip55;

    return Scaffold(
      appBar: AppBar(
        title: Text(S.of(context).walletAddress),
      ),
      body: SafeArea(
        child: Padding(
          padding: const .symmetric(
            horizontal: 20.0,
            vertical: 12.0,
          ),
          child: ScrollableActionsLayout(
            // QR + disclaimer is taller than a small phone at large text
            // scale; do not pin the body to the leftover viewport height
            // (centerBody) or the Column overflows instead of scrolling.
            body: Column(
              spacing: 40.0,
              children: [
                Column(
                  spacing: 16.0,
                  children: [
                    SvgPicture.asset(
                      'assets/images/coins/REALU.svg',
                      width: 70,
                      height: 70,
                    ),
                    Text(
                      '${S.of(context).realunitWallet} ${S.of(context).address}',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ],
                ),
                QRAddressWidget(
                  uri: EthereumURI(address: walletAddress, amount: '').toString(),
                  subtitle: walletAddress,
                ),
                Padding(
                  padding: const .all(20.0),
                  child: Text(
                    S.of(context).walletAddressDisclaimer,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: RealUnitColors.neutral500,
                    ),
                    textAlign: .center,
                  ),
                ),
              ],
            ),
            actions: [
              if (insiderFeaturesUnlocked)
                AppFilledButton(
                  label: S.of(context).send,
                  onPressed: () => context.pushNamed(AppRoutes.send),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
