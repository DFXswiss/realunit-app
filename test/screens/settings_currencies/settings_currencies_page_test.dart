import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/repository/settings_repository.dart';
import 'package:realunit_wallet/packages/repository/supported_fiat_repository.dart';
import 'package:realunit_wallet/packages/config/network_mode.dart';
import 'package:realunit_wallet/screens/settings/bloc/settings_bloc.dart';
import 'package:realunit_wallet/screens/settings_currencies/settings_currencies_page.dart';
import 'package:realunit_wallet/styles/currency.dart';

import '../../helper/helper.dart';

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

  testWidgets(
    'renders the currencies returned by the repository',
    (tester) async {
      when(() => fiatRepo.getAll())
          .thenAnswer((_) async => const [Currency.chf, Currency.eur]);

      await tester.pumpApp(const SettingsCurrenciesPage());
      await tester.pumpAndSettle();

      expect(find.text('CHF'), findsOneWidget);
      expect(find.text('EUR'), findsOneWidget);
      expect(find.byKey(const Key('settings-currencies-error')), findsNothing);
    },
  );

  testWidgets(
    'on snapshot.hasError shows the error view with a retry button',
    (tester) async {
      when(() => fiatRepo.getAll()).thenAnswer(
        (_) async => Future.error(Exception('API down')),
      );

      await tester.pumpApp(const SettingsCurrenciesPage());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('settings-currencies-error')), findsOneWidget);
      expect(find.text('CHF'), findsNothing);
      // Retry button (uses `S.current.retry` = "Retry" in English) is present.
      expect(find.byType(OutlinedButton), findsOneWidget);
    },
  );

  testWidgets(
    'tapping retry re-invokes the repository',
    (tester) async {
      var callCount = 0;
      when(() => fiatRepo.getAll()).thenAnswer((_) async {
        callCount++;
        if (callCount == 1) {
          throw Exception('API down');
        }
        return const [Currency.chf];
      });

      await tester.pumpApp(const SettingsCurrenciesPage());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings-currencies-error')), findsOneWidget);

      await tester.tap(find.byType(OutlinedButton));
      await tester.pumpAndSettle();

      expect(callCount, 2);
      expect(find.byKey(const Key('settings-currencies-error')), findsNothing);
      expect(find.text('CHF'), findsOneWidget);
    },
  );
}
