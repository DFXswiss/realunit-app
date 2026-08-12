import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/models/balance.dart';
import 'package:realunit_wallet/packages/repository/balance_repository.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/screens/dashboard/bloc/balance_cubit.dart';
import 'package:realunit_wallet/screens/migrate_bitbox/cubits/migrate_bitbox/migrate_bitbox_cubit.dart';
import 'package:realunit_wallet/setup/di.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';
import 'package:realunit_wallet/widgets/scrollable_actions_layout.dart';

class MigrateIntroView extends StatelessWidget {
  const MigrateIntroView({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => BalanceCubit(
      getIt<BalanceRepository>(),
      asset: getIt<AppStore>().apiConfig.asset,
      walletAddress: getIt<AppStore>().primaryAddress,
    ),
    child: Scaffold(
      appBar: AppBar(title: Text(S.of(context).migrateBitbox)),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: SafeArea(
          child: ScrollableActionsLayout(
            centerBody: true,
            body: Column(
              spacing: 16,
              children: [
                Text(
                  S.of(context).migrateBitboxIntroTitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                Text(
                  S.of(context).migrateBitboxIntroDescription,
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: RealUnitColors.neutral500),
                ),
                BlocBuilder<BalanceCubit, Balance>(
                  builder: (context, state) => Text(
                    '${S.of(context).migrateBitboxIntroBalance}: ${state.balance} REALU',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              ],
            ),
            actions: [
              AppFilledButton(
                label: S.of(context).migrateBitboxStart,
                onPressed: () => context.read<MigrateBitboxCubit>().startPairing(),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
