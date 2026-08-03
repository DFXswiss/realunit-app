import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/models/user/dto/real_unit_user_data_dto.dart';
import 'package:realunit_wallet/screens/migrate_bitbox/cubits/migrate_bitbox/migrate_bitbox_cubit.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';
import 'package:realunit_wallet/widgets/scrollable_actions_layout.dart';

class MigrateRegisterView extends StatelessWidget {
  const MigrateRegisterView({
    super.key,
    required this.userData,
    required this.bitboxAddress,
  });

  final RealUnitUserDataDto userData;
  final String bitboxAddress;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(S.of(context).migrateBitbox)),
    body: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SafeArea(
        child: ScrollableActionsLayout(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 16,
            children: [
              Text(
                S.of(context).migrateBitboxRegisterTitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              Text(
                S.of(context).migrateBitboxRegisterDescription,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: RealUnitColors.neutral500),
              ),
              _MigrateRegisterInfoRow(
                label: S.of(context).name,
                value: userData.name,
              ),
              _MigrateRegisterInfoRow(
                label: S.of(context).walletAddress,
                value: _truncateAddress(bitboxAddress),
              ),
              Text(
                S.of(context).migrateBitboxRegisterConfirmHint,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: RealUnitColors.neutral500),
              ),
            ],
          ),
          actions: [
            AppFilledButton(
              label: S.of(context).migrateBitboxRegisterCta,
              onPressed: () => context.read<MigrateBitboxCubit>().register(),
            ),
          ],
        ),
      ),
    ),
  );
}

class _MigrateRegisterInfoRow extends StatelessWidget {
  const _MigrateRegisterInfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 4,
    children: [
      Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: RealUnitColors.neutral500),
      ),
      Text(value, style: Theme.of(context).textTheme.bodyLarge),
    ],
  );
}

String _truncateAddress(String address) {
  if (address.length <= 12) return address;
  return '${address.substring(0, 6)}…${address.substring(address.length - 4)}';
}
