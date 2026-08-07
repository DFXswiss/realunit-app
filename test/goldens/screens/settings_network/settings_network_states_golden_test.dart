import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/screens/settings/bloc/settings_bloc.dart';
import 'package:realunit_wallet/screens/settings_network/settings_network_page.dart';

import '../../../helper/helper.dart';

void main() {
  // `settings_network_page_default` (mainnet selected, check icon) lives in
  // `settings_network_golden_test.dart`. This file covers the "switch in
  // flight" branch of `SettingsNetworkPage.build`
  // (`settings_network_page.dart:32-44`): tapping a non-selected mode sets the
  // page's `_LoadingNetworkModeModel` so its trailing shows a
  // `CircularProgressIndicator` instead of the check. The mocked `SettingsBloc`
  // never emits, so the `BlocConsumer.listener` that would clear the loading
  // flag (`loadingFinished()`) never fires and the spinner stays put.
  late MockSettingsBloc settingsBloc;

  setUp(() {
    settingsBloc = MockSettingsBloc();
    when(() => settingsBloc.state).thenReturn(const SettingsState());

    final getIt = GetIt.instance;
    if (getIt.isRegistered<SettingsBloc>()) {
      getIt.unregister<SettingsBloc>();
    }
    getIt.registerSingleton<SettingsBloc>(settingsBloc);
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  group('$SettingsNetworkPage', () {
    goldenTest(
      'switching to testnet — spinner instead of check',
      fileName: 'settings_network_page_switching',
      constraints: phoneConstraints,
      // Tap the second (non-selected: Testnet) tile, then a single pump to
      // freeze the CircularProgressIndicator on its first frame — pumpAndSettle
      // would time out on the never-ending spinner.
      pumpBeforeTest: (tester) async {
        await tester.pumpAndSettle();
        await tester.tap(find.byType(InkWell).at(1));
        await tester.pump();
      },
      builder: () => wrapForGolden(
        BlocProvider<SettingsBloc>.value(
          value: settingsBloc,
          child: SettingsNetworkPage(),
        ),
      ),
    );
  });
}
