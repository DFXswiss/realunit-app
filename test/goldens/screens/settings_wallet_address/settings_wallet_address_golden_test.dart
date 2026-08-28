import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/screens/settings_wallet_address/settings_wallet_address_page.dart';

import '../../../helper/helper.dart';

void main() {
  final MockAppStore appStore = MockAppStore();

  setUp(() {
    when(() => appStore.primaryAddress)
        .thenReturn('0x938115b533a0b746428361760a6972dfd06d984a');
  });

  setUpAll(() {
    final getIt = GetIt.instance;
    getIt.registerSingleton<AppStore>(appStore);
  });

  tearDownAll(() async {
    await GetIt.instance.reset();
  });

  group('$SettingsWalletAddressPage', () {
    goldenTest(
      'default state with primary address',
      fileName: 'settings_wallet_address_page_default',
      constraints: phoneConstraints,
      builder: () => wrapForGolden(const SettingsWalletAddressPage()),
    );
  });
}
