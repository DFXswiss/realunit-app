import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/screens/referral/format_frozen_chf.dart';
import 'package:realunit_wallet/screens/settings/bloc/settings_bloc.dart';
import 'package:realunit_wallet/styles/colors.dart';

/// Frozen CHF line for referral prizes. Honors [SettingsState.hideAmounts].
class FrozenChfLabel extends StatelessWidget {
  final String raw;

  const FrozenChfLabel({super.key, required this.raw});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, state) {
        final value = state.hideAmounts ? '***.**' : formatFrozenChfAmount(raw);
        return Text(
          S.of(context).referralPayoutChf(value),
          style: const TextStyle(
            fontSize: 12,
            height: 16 / 12,
            color: RealUnitColors.neutral500,
          ),
        );
      },
    );
  }
}
