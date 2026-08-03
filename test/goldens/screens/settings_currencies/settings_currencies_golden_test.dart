import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/config/network_mode.dart';
import 'package:realunit_wallet/packages/repository/settings_repository.dart';
import 'package:realunit_wallet/packages/repository/supported_fiat_repository.dart';
import 'package:realunit_wallet/screens/settings/bloc/settings_bloc.dart';
import 'package:realunit_wallet/screens/settings_currencies/settings_currencies_page.dart';
import 'package:realunit_wallet/styles/currency.dart';

import '../../../helper/helper.dart';

class _MockSupportedFiatRepository extends Mock implements SupportedFiatRepository {}

class _MockSettingsRepository extends Mock implements SettingsRepository {}

void main() {

  late _MockSupportedFiatRepository fiatRepo;
  late _MockSettingsRepository settingsRepo;
  late SettingsBloc settingsBloc;

  setUp(() {
    fiatRepo = _MockSupportedFiatRepository();
    settingsRepo = _MockSettingsRepository();
    when(() => settingsRepo.language).thenReturn('en');
    when(() => settingsRepo.currency).thenReturn('CHF');
    when(() => settingsRepo.networkMode).thenReturn(NetworkMode.mainnet);
    when(() => settingsRepo.insiderFeaturesUnlocked).thenReturn(false);
    when(() => fiatRepo.getAll())
        .thenAnswer((_) async => const [Currency.chf, Currency.eur]);
    settingsBloc = SettingsBloc(settingsRepo, () async {});

    final getIt = GetIt.instance;
    if (getIt.isRegistered<SupportedFiatRepository>()) {
      getIt.unregister<SupportedFiatRepository>();
    }
    if (getIt.isRegistered<SettingsBloc>()) {
      getIt.unregister<SettingsBloc>();
    }
    getIt.registerSingleton<SupportedFiatRepository>(fiatRepo);
    getIt.registerSingleton<SettingsBloc>(settingsBloc);
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  group('$SettingsCurrenciesPage', () {
    goldenTest(
      'default state with currencies loaded',
      fileName: 'settings_currencies_page_default',
      constraints: phoneConstraints,
      builder: () => wrapForGolden(const SettingsCurrenciesPage()),
    );
  });
}
