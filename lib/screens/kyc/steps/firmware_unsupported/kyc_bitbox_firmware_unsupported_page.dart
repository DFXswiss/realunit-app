import 'package:flutter/material.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/scrollable_actions_layout.dart';

/// Terminal screen for a BitBox whose firmware refuses the registration
/// signature. Deliberately action-less (`actions: const []`) — the app cannot
/// flash firmware (the plugin does not vendor `api/bootloader`), and BitBox
/// ship updates through the BitBoxApp, so the only real action is the one the
/// copy names: check there for an update.
///
/// No retry button on purpose. The gate reads the version the device reports,
/// so it clears itself the moment the user updates — a retry here would only
/// reproduce the same silent NACK.
class KycBitboxFirmwareUnsupportedPage extends StatelessWidget {
  const KycBitboxFirmwareUnsupportedPage({super.key, this.version});

  /// The firmware the device reported, e.g. `"v9.26.4"`. Null when it could not
  /// be read, in which case the version line is omitted rather than showing an
  /// empty or placeholder value.
  final String? version;

  @override
  Widget build(BuildContext context) {
    final version = this.version;
    return Scaffold(
      appBar: AppBar(
        title: Text(S.of(context).kycBitboxFirmwareUnsupportedTitle),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0),
        child: SafeArea(
          child: ScrollableActionsLayout(
            centerBody: true,
            actions: const [],
            body: Column(
              spacing: 16.0,
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 48,
                  color: RealUnitColors.neutral500,
                ),
                Text(
                  S.of(context).kycBitboxFirmwareUnsupportedTitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                Text(
                  S.of(context).kycBitboxFirmwareUnsupportedDescription,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: RealUnitColors.neutral500,
                  ),
                ),
                if (version != null)
                  Text(
                    S.of(context).kycBitboxFirmwareUnsupportedVersion(version),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: RealUnitColors.neutral500,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
