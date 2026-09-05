import 'package:alchemist/alchemist.dart' as alchemist;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_summary_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_referral_service.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';
import 'package:realunit_wallet/screens/home/bloc/home_bloc.dart';
import 'package:realunit_wallet/screens/settings/bloc/settings_bloc.dart';
import 'package:realunit_wallet/screens/settings/settings_page.dart';

import '../../../helper/helper.dart';

void main() {
  late MockSettingsBloc settingsBloc;
  late MockHomeBloc homeBloc;
  late MockSoftwareWallet wallet;

  setUp(() {
    settingsBloc = MockSettingsBloc();
    homeBloc = MockHomeBloc();
    wallet = MockSoftwareWallet();

    when(() => wallet.walletType).thenReturn(WalletType.software);
    when(() => settingsBloc.state).thenReturn(const SettingsState());
    when(() => homeBloc.state).thenReturn(HomeState(openWallet: wallet));
  });

  setUpAll(() {
    GetIt.instance.registerSingleton<SettingsBloc>(MockSettingsBloc());
    GetIt.instance.registerSingleton<RealUnitReferralService>(
      MockRealUnitReferralService(),
    );
  });

  tearDownAll(() async {
    await GetIt.instance.reset();
  });

  Widget buildSubject() {
    // Re-register the per-test mock into GetIt so the BlocBuilder picks up
    // the state defined in setUp(). setUpAll() only registers once.
    if (GetIt.instance.isRegistered<SettingsBloc>()) {
      GetIt.instance.unregister<SettingsBloc>();
    }
    GetIt.instance.registerSingleton<SettingsBloc>(settingsBloc);

    return wrapForGolden(
      BlocProvider<HomeBloc>.value(
        value: homeBloc,
        child: const SettingsPage(),
      ),
    );
  }

  group('$SettingsPage', () {
    goldenTest(
      'default state, software wallet open',
      fileName: 'settings_page_default',
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      builder: buildSubject,
    );

    goldenTest(
      'bitbox wallet open hides the Wallet-Sicherung tile',
      fileName: 'settings_page_bitbox',
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      builder: () {
        final bitbox = MockBitboxWallet();
        when(() => bitbox.walletType).thenReturn(WalletType.bitbox);
        when(() => homeBloc.state).thenReturn(HomeState(openWallet: bitbox));
        return buildSubject();
      },
    );

    goldenTest(
      'shows Empfehlungen when eligible',
      fileName: 'settings_page_referral_eligible',
      constraints: const BoxConstraints.tightFor(width: 390, height: 844),
      pumpBeforeTest: (tester) async {
        await alchemist.precacheImages(tester);
        await tester.pumpAndSettle();
      },
      builder: () {
        final referral = MockRealUnitReferralService();
        when(() => referral.getSummary()).thenAnswer(
          (_) async => const ReferralSummaryDto(
            eligible: true,
            termsAccepted: true,
            openCount: 0,
            creditedCount: 0,
            realuSum: 0,
            chfSum: 0,
          ),
        );
        if (GetIt.instance.isRegistered<RealUnitReferralService>()) {
          GetIt.instance.unregister<RealUnitReferralService>();
        }
        GetIt.instance.registerSingleton<RealUnitReferralService>(referral);
        return buildSubject();
      },
    );
  });
}
