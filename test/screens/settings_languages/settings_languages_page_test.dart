import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/config/network_mode.dart';
import 'package:realunit_wallet/packages/repository/settings_repository.dart';
import 'package:realunit_wallet/packages/repository/supported_language_repository.dart';
import 'package:realunit_wallet/screens/settings/bloc/settings_bloc.dart';
import 'package:realunit_wallet/screens/settings_languages/settings_languages_page.dart';
import 'package:realunit_wallet/styles/language.dart';

import '../../helper/helper.dart';

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

  testWidgets(
    'renders the languages returned by the repository',
    (tester) async {
      when(() => langRepo.getEnabled())
          .thenAnswer((_) async => const [Language.en, Language.de]);

      await tester.pumpApp(const SettingsLanguagePage());
      await tester.pumpAndSettle();

      expect(find.text(Language.en.name), findsOneWidget);
      expect(find.text(Language.de.name), findsOneWidget);
      expect(find.byKey(const Key('settings-languages-error')), findsNothing);
    },
  );

  testWidgets(
    'on snapshot.hasError shows the error view with a retry button',
    (tester) async {
      when(() => langRepo.getEnabled()).thenAnswer(
        (_) async => Future.error(Exception('API down')),
      );

      await tester.pumpApp(const SettingsLanguagePage());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('settings-languages-error')), findsOneWidget);
      expect(find.byType(OutlinedButton), findsOneWidget);
    },
  );

  testWidgets(
    'tapping retry re-invokes the repository',
    (tester) async {
      var callCount = 0;
      when(() => langRepo.getEnabled()).thenAnswer((_) async {
        callCount++;
        if (callCount == 1) {
          throw Exception('API down');
        }
        return const [Language.en];
      });

      await tester.pumpApp(const SettingsLanguagePage());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings-languages-error')), findsOneWidget);

      await tester.tap(find.byType(OutlinedButton));
      await tester.pumpAndSettle();

      expect(callCount, 2);
      expect(find.byKey(const Key('settings-languages-error')), findsNothing);
      expect(find.text(Language.en.name), findsOneWidget);
    },
  );
}
