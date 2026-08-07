import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/repository/supported_language_repository.dart';
import 'package:realunit_wallet/screens/settings_languages/settings_languages_page.dart';
import 'package:realunit_wallet/styles/language.dart';

import '../../../helper/helper.dart';

class _MockSupportedLanguageRepository extends Mock
    implements SupportedLanguageRepository {}

void main() {
  // `settings_languages_page_default` (languages loaded) lives in
  // `settings_languages_golden_test.dart`. This file covers the two other
  // `FutureBuilder` branches of `SettingsLanguagePage.build`
  // (`settings_languages_page.dart:39-59`): the pending spinner and the
  // `_LanguageErrorView`. Neither branch reaches the `getIt<SettingsBloc>()`
  // lookup, so only the repository the page reads in `initState` is registered.
  late _MockSupportedLanguageRepository langRepo;

  setUp(() {
    langRepo = _MockSupportedLanguageRepository();
    final getIt = GetIt.instance;
    if (getIt.isRegistered<SupportedLanguageRepository>()) {
      getIt.unregister<SupportedLanguageRepository>();
    }
    getIt.registerSingleton<SupportedLanguageRepository>(langRepo);
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  group('$SettingsLanguagePage', () {
    // No data, no error → `CupertinoActivityIndicator` (page:57-59). A future
    // that never completes keeps the FutureBuilder in its pending branch;
    // freeze the spinner with pumpOnce.
    goldenTest(
      'loading',
      fileName: 'settings_languages_page_loading',
      constraints: phoneConstraints,
      pumpBeforeTest: pumpOnce,
      builder: () {
        when(() => langRepo.getEnabled())
            .thenAnswer((_) => Completer<List<Language>>().future);
        return wrapForGolden(const SettingsLanguagePage());
      },
    );

    // `snapshot.hasError` → `_LanguageErrorView` (page:42-56, 91-137): icon,
    // title, description and Retry button.
    goldenTest(
      'error view with retry',
      fileName: 'settings_languages_page_error',
      constraints: phoneConstraints,
      builder: () {
        when(() => langRepo.getEnabled())
            .thenAnswer((_) async => throw Exception('failed to load languages'));
        return wrapForGolden(const SettingsLanguagePage());
      },
    );
  });
}
