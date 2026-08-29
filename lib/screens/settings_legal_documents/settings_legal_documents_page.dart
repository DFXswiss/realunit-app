import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/config/legal_documents_config.dart';
import 'package:realunit_wallet/setup/routing/routes/legal_routes.dart';
import 'package:realunit_wallet/setup/routing/routes/settings_routes.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/outlined_tile.dart';

class SettingsLegalDocumentsPage extends StatelessWidget {
  const SettingsLegalDocumentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(S.of(context).legalDocuments),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const .symmetric(
            horizontal: 20.0,
            vertical: 12.0,
          ),
          child: SafeArea(
            child: Column(
              spacing: 12.0,
              children: [
                OutlinedTile(
                  leading: const Icon(
                    Icons.description_outlined,
                    color: RealUnitColors.realUnitBlue,
                  ),
                  title: S.of(context).termsOfUse,
                  onTap: () => context.pushNamed(LegalRoutes.terms),
                  trailingIcon: Icons.chevron_right_rounded,
                ),
                ...LegalDocumentsConfig.allDocuments.map(
                  (config) => OutlinedTile(
                    leading: Icon(
                      config.icon,
                      color: RealUnitColors.realUnitBlue,
                    ),
                    title: config.title(context),
                    onTap: () => config.onTap(context),
                    trailingIcon: config.isExternal
                        ? Icons.open_in_new_rounded
                        : Icons.chevron_right_rounded,
                  ),
                ),
                OutlinedTile(
                  leading: const Icon(
                    Icons.business_outlined,
                    color: RealUnitColors.realUnitBlue,
                  ),
                  title: S.of(context).aktionariatTitle,
                  onTap: () => context.pushNamed(SettingsRoutes.aktionariatDocuments),
                  trailingIcon: Icons.chevron_right_rounded,
                ),
                OutlinedTile(
                  leading: const Icon(
                    Icons.business_outlined,
                    color: RealUnitColors.realUnitBlue,
                  ),
                  title: S.of(context).dfxTitle,
                  onTap: () => context.pushNamed(SettingsRoutes.dfxDocuments),
                  trailingIcon: Icons.chevron_right_rounded,
                ),
                OutlinedTile(
                  key: const Key('settings-referral-terms'),
                  leading: const Icon(
                    Icons.card_giftcard_outlined,
                    color: RealUnitColors.realUnitBlue,
                  ),
                  title: S.of(context).referralTermsTitle,
                  onTap: () => context.pushNamed(LegalRoutes.referralTerms),
                  trailingIcon: Icons.chevron_right_rounded,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
