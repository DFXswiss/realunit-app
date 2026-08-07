import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/config/network_mode.dart';
import 'package:realunit_wallet/packages/repository/settings_repository.dart';
import 'package:realunit_wallet/packages/repository/supported_language_repository.dart';
import 'package:realunit_wallet/screens/settings/bloc/settings_bloc.dart';
import 'package:realunit_wallet/screens/settings_languages/settings_languages_page.dart';
import 'package:realunit_wallet/styles/language.dart';

import '../../../helper/helper.dart';

class _MockSupportedLanguageRepository extends Mock
    implements SupportedLanguageRepository {}

class _MockSettingsRepository extends Mock implements SettingsRepository {}

void main() {

  late _MockSupportedLanguageRepository langRepo;
  late _MockSettingsRepository settingsRepo;
  late SettingsBloc settingsBloc;

  setUp(() {
    langRepo = _MockSupportedLanguageRepository();
    settingsRepo = _MockSettingsRepository();
    when(() => settingsRepo.language).thenReturn('en');
    when(() => settingsRepo.currency).thenReturn('CHF');
    when(() => settingsRepo.networkMode).thenReturn(NetworkMode.mainnet);
    when(() => settingsRepo.insiderFeaturesUnlocked).thenReturn(false);
    when(() => langRepo.getEnabled())
        .thenAnswer((_) async => const [Language.en, Language.de]);
    settingsBloc = SettingsBloc(settingsRepo, () async {});

    final getIt = GetIt.instance;
    if (getIt.isRegistered<SupportedLanguageRepository>()) {
      getIt.unregister<SupportedLanguageRepository>();
    }
    if (getIt.isRegistered<SettingsBloc>()) {
      getIt.unregister<SettingsBloc>();
    }
    getIt.registerSingleton<SupportedLanguageRepository>(langRepo);
    getIt.registerSingleton<SettingsBloc>(settingsBloc);
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  group('$SettingsLanguagePage', () {
    goldenTest(
      'default state with languages loaded',
      fileName: 'settings_languages_page_default',
      constraints: phoneConstraints,
      builder: () => wrapForGolden(const SettingsLanguagePage()),
    );
  });
}
