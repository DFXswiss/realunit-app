abstract final class AppRoutes {
  static const home = 'home';
  static const dashboard = 'dashboard';
  static const transactionHistory = 'transactionHistory';
  static const buy = 'buy';
  static const buyPaymentDetails = 'buyPaymentDetails';
  static const sell = 'sell';
  static const sellBitbox = 'sellBitbox';
  static const pay = 'pay';
  static const send = 'send';
  static const kyc = 'kyc';
  static const receive = 'receive';
  static const bitboxAddressRecovery = 'bitboxAddressRecovery';

  static const webView = 'webView';
}

/// Query parameters that scope the [AppRoutes.kyc] flow to the context the user
/// entered it from (`RealunitBuy`, `RealunitSell`, …), as the API reported it.
///
/// The context travels in the URL rather than in `extra` because the flow has a
/// second entry: after a background lock the boot ladder re-pushes the captured
/// location by bare path (`BootNavRestore` in `boot_navigation.dart`), which
/// carries no `extra`. Without the query the restored flow rebuilds unscoped,
/// and the API then computes `processStatus` over every globally required step
/// instead of only those the entered flow needs — reporting a user who has
/// finished `Ident` as still in progress for steps that do not gate buying.
///
/// A null or empty [kycContext] means the API attached none; the route is
/// then entered unscoped exactly as before, never with an invented context.
Map<String, String> kycRouteQuery(String? kycContext) => {
  if (kycContext != null && kycContext.isNotEmpty) 'context': kycContext,
};
