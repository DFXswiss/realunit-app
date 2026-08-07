import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/screens/settings_seed/bloc/settings_seed_cubit.dart';
import 'package:realunit_wallet/screens/settings_seed/settings_seed_view.dart';

import '../../../helper/helper.dart';

class _MockSettingsSeedCubit extends MockCubit<SettingsSeedState> implements SettingsSeedCubit {}

void main() {
  // `settings_seed_page_default` (blurred seed card) and
  // `settings_seed_page_revealed` live in `settings_seed_golden_test.dart`.
  // This file covers the pre-unlock branch of `SettingsSeedView`
  // (`settings_seed_view.dart:89-100`): while fewer than 12 mnemonic words are
  // in memory the seed card is replaced by a CupertinoActivityIndicator.
  late _MockSettingsSeedCubit settingsSeedCubit;

  setUp(() {
    settingsSeedCubit = _MockSettingsSeedCubit();
    // Empty seed → wordCount != 12 → spinner branch.
    when(() => settingsSeedCubit.state).thenReturn(const SettingsSeedState(''));
  });

  setUpAll(() {
    // SettingsSeedView.initState calls ScreenshotGuard.acquire(), which hits
    // the no_screenshot method channel.
    stubNoScreenshotChannel();
  });

  group('$SettingsSeedView', () {
    goldenTest(
      'seed still loading — spinner instead of the seed card',
      fileName: 'settings_seed_page_loading',
      constraints: phoneConstraints,
      // The backup illustration SVG is not covered by precacheImages; give it a
      // couple of (microtask-driven, deterministic) frames to decode, then stop
      // before the endless CupertinoActivityIndicator would time out a settle.
      pumpBeforeTest: (tester) async {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
      },
      builder: () => wrapForGolden(
        BlocProvider<SettingsSeedCubit>.value(
          value: settingsSeedCubit,
          child: const SettingsSeedView(),
        ),
      ),
    );
  });
}
