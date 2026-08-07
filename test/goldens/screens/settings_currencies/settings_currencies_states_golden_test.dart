import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/repository/supported_fiat_repository.dart';
import 'package:realunit_wallet/screens/settings_currencies/settings_currencies_page.dart';
import 'package:realunit_wallet/styles/currency.dart';

import '../../../helper/helper.dart';

class _MockSupportedFiatRepository extends Mock implements SupportedFiatRepository {}

void main() {
  // `settings_currencies_page_default` (currencies loaded) lives in
  // `settings_currencies_golden_test.dart`. This file covers the two other
  // `FutureBuilder` branches of `SettingsCurrenciesPage.build`
  // (`settings_currencies_page.dart:43-63`): the pending spinner and the
  // `_ErrorView`. Neither branch reaches the `getIt<SettingsBloc>()` lookup,
  // so only the repository the page reads in `initState` is registered.
  late _MockSupportedFiatRepository fiatRepo;

  setUp(() {
    fiatRepo = _MockSupportedFiatRepository();
    final getIt = GetIt.instance;
    if (getIt.isRegistered<SupportedFiatRepository>()) {
      getIt.unregister<SupportedFiatRepository>();
    }
    getIt.registerSingleton<SupportedFiatRepository>(fiatRepo);
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  group('$SettingsCurrenciesPage', () {
    // No data, no error → `CupertinoActivityIndicator` (page:61-63). A future
    // that never completes keeps the FutureBuilder in its pending branch;
    // freeze the spinner with pumpOnce.
    goldenTest(
      'loading',
      fileName: 'settings_currencies_page_loading',
      constraints: phoneConstraints,
      pumpBeforeTest: pumpOnce,
      builder: () {
        when(() => fiatRepo.getAll())
            .thenAnswer((_) => Completer<List<Currency>>().future);
        return wrapForGolden(const SettingsCurrenciesPage());
      },
    );

    // `snapshot.hasError` → `_ErrorView` (page:46-60, 96-142): icon, title,
    // description and Retry button.
    goldenTest(
      'error view with retry',
      fileName: 'settings_currencies_page_error',
      constraints: phoneConstraints,
      builder: () {
        when(() => fiatRepo.getAll())
            .thenAnswer((_) async => throw Exception('failed to load currencies'));
        return wrapForGolden(const SettingsCurrenciesPage());
      },
    );
  });
}
