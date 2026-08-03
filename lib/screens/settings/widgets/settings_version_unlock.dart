import 'package:flutter/material.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/screens/settings/bloc/settings_bloc.dart';
import 'package:realunit_wallet/setup/di.dart';
import 'package:realunit_wallet/styles/colors.dart';

class SettingsVersionUnlock extends StatefulWidget {
  const SettingsVersionUnlock({required this.releaseTag, super.key});

  final String releaseTag;

  @override
  State<SettingsVersionUnlock> createState() =>
      _SettingsVersionUnlockState();
}

class _SettingsVersionUnlockState extends State<SettingsVersionUnlock> {
  int _tapCount = 0;

  void _onTap() {
    final settingsBloc = getIt<SettingsBloc>();
    if (settingsBloc.state.insiderFeaturesUnlocked) {
      return;
    }

    _tapCount++;
    if (_tapCount == 7) {
      settingsBloc.add(const UnlockInsiderFeaturesEvent());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.of(context).settingsInsiderFeaturesUnlocked),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
        child: Text(
          S.of(context).settingsAppVersion(widget.releaseTag),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: RealUnitColors.neutral500,
              ),
        ),
      ),
    );
  }
}
