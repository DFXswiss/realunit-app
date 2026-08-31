import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/wallet/payment_uri.dart';
import 'package:realunit_wallet/screens/receive/widgets/qr_address_widget.dart';
import 'package:realunit_wallet/setup/di.dart';
import 'package:realunit_wallet/setup/routing/routes/app_routes.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';
import 'package:realunit_wallet/widgets/handlebars.dart';
import 'package:realunit_wallet/widgets/scrollable_actions_layout.dart';

class ReceivePage extends StatelessWidget {
  const ReceivePage({super.key, this.isBottomSheet = true});

  final bool isBottomSheet;

  @override
  Widget build(BuildContext context) {
    final address = getIt<AppStore>().primaryAddress;

    return Scaffold(
      appBar: isBottomSheet
          ? null
          : AppBar(
              leading: IconButton(
                onPressed: () => context.pop(),
                icon: const Icon(
                  Icons.arrow_back_rounded,
                ),
              ),
            ),
      body: SafeArea(
        child: ScrollableActionsLayout(
          body: Column(
            children: [
              if (isBottomSheet) Handlebars.horizontal(context),
              SizedBox(
                width: double.infinity,
                height: isBottomSheet ? 20 : 0,
              ),
              QRAddressWidget(
                uri: EthereumURI(address: address, amount: '').toString(),
                subtitle: address,
              ),
            ],
          ),
          actions: [
            Padding(
              padding: const .symmetric(horizontal: 20, vertical: 12),
              child: AppFilledButton(
                label: S.of(context).send,
                onPressed: () => context.pushNamed(AppRoutes.send),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
