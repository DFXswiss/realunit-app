import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/screens/settings/bloc/settings_bloc.dart';
import 'package:realunit_wallet/screens/settings/widgets/settings_version_unlock.dart';

import '../../../helper/helper.dart';

void main() {
  late MockSettingsBloc settingsBloc;

  setUpAll(() {
    GetIt.instance.registerSingleton<SettingsBloc>(MockSettingsBloc());
  });

  tearDownAll(() async {
    await GetIt.instance.reset();
  });

  setUp(() {
    settingsBloc = MockSettingsBloc();
    when(() => settingsBloc.state).thenReturn(const SettingsState());
  });

  Widget host() {
    // Re-register the per-test mock into GetIt so getIt<SettingsBloc>() inside the
    // widget picks up the state defined in setUp(). setUpAll() only registers once.
    if (GetIt.instance.isRegistered<SettingsBloc>()) {
      GetIt.instance.unregister<SettingsBloc>();
    }
    GetIt.instance.registerSingleton<SettingsBloc>(settingsBloc);

    return const Scaffold(
      body: SettingsVersionUnlock(releaseTag: '1.2.3'),
    );
  }

  group('$SettingsVersionUnlock', () {
    testWidgets('displays the version text', (tester) async {
      await tester.pumpApp(host());

      expect(find.textContaining('1.2.3'), findsOneWidget);
    });

    testWidgets('6 taps: no event dispatched, no SnackBar shown', (tester) async {
      await tester.pumpApp(host());

      for (var i = 0; i < 6; i++) {
        await tester.tap(find.byType(SettingsVersionUnlock));
        await tester.pump();
      }

      verifyNever(() => settingsBloc.add(const UnlockInsiderFeaturesEvent()));
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets(
      '7th tap dispatches UnlockInsiderFeaturesEvent exactly once and shows the SnackBar',
      (tester) async {
        await tester.pumpApp(host());

        for (var i = 0; i < 7; i++) {
          await tester.tap(find.byType(SettingsVersionUnlock));
          await tester.pump();
        }

        verify(() => settingsBloc.add(const UnlockInsiderFeaturesEvent())).called(1);
        expect(find.byType(SnackBar), findsOneWidget);
        expect(find.text(S.current.settingsInsiderFeaturesUnlocked), findsOneWidget);
      },
    );

    testWidgets('already unlocked: taps trigger neither event nor SnackBar', (tester) async {
      when(() => settingsBloc.state)
          .thenReturn(const SettingsState(insiderFeaturesUnlocked: true));

      await tester.pumpApp(host());

      for (var i = 0; i < 10; i++) {
        await tester.tap(find.byType(SettingsVersionUnlock));
        await tester.pump();
      }

      verifyNever(() => settingsBloc.add(const UnlockInsiderFeaturesEvent()));
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('already unlocked: version text is still displayed', (tester) async {
      when(() => settingsBloc.state)
          .thenReturn(const SettingsState(insiderFeaturesUnlocked: true));

      await tester.pumpApp(host());

      expect(find.textContaining('1.2.3'), findsOneWidget);
    });
  });
}
