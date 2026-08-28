import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/screens/settings/bloc/settings_bloc.dart';
import 'package:realunit_wallet/screens/settings_wallet_address/settings_wallet_address_page.dart';

import '../../../helper/helper.dart';

void main() {
  final MockAppStore appStore = MockAppStore();
  late MockSettingsBloc settingsBloc;

  setUp(() {
    settingsBloc = MockSettingsBloc();
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
      builder: () {
        when(() => settingsBloc.state).thenReturn(const SettingsState());
        return wrapForGolden(
          BlocProvider<SettingsBloc>.value(
            value: settingsBloc,
            child: const SettingsWalletAddressPage(),
          ),
        );
      },
    );

    goldenTest(
      'insider-unlocked state with Send action',
      fileName: 'settings_wallet_address_page_with_send',
      constraints: phoneConstraints,
      builder: () {
        when(() => settingsBloc.state)
            .thenReturn(const SettingsState(insiderFeaturesUnlocked: true));
        return wrapForGolden(
          BlocProvider<SettingsBloc>.value(
            value: settingsBloc,
            child: const SettingsWalletAddressPage(),
          ),
        );
      },
    );
  });
}
