import 'package:flutter_test/flutter_test.dart';
import 'package:realunit_wallet/setup/routing/routes/app_routes.dart';

void main() {
  group('kycRouteQuery', () {
    test('carries the context the entry point was handed', () {
      expect(kycRouteQuery('RealunitBuy'), {'context': 'RealunitBuy'});
      expect(kycRouteQuery('RealunitSell'), {'context': 'RealunitSell'});
    });

    // Only the API knows which context a gate belongs to. When it attached
    // none, the route is entered unscoped — exactly as before — rather than
    // with a context the app made up.
    test('omits the parameter when the API attached no context', () {
      expect(kycRouteQuery(null), isEmpty);
    });
  });
}
