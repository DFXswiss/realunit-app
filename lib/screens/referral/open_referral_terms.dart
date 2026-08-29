import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:realunit_wallet/setup/routing/routes/legal_routes.dart';

/// Opens the Teilnahmebedingungen after the Empfehler has accepted them
/// (TB Ziff. 2–11 stay readable). GET /terms 1:1, then the bundled 14.08
/// TB. No-op when there is no GoRouter (golden / pumpApp shells).
void openReferralTerms(BuildContext context) {
  final router = GoRouter.maybeOf(context);
  if (router == null) return;
  router.pushNamed(LegalRoutes.referralTerms);
}
