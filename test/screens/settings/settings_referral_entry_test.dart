import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_summary_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_referral_service.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';
import 'package:realunit_wallet/screens/home/bloc/home_bloc.dart';
import 'package:realunit_wallet/screens/settings/bloc/settings_bloc.dart';
import 'package:realunit_wallet/screens/settings/settings_page.dart';

import '../../helper/helper.dart';

void main() {
  late MockSettingsBloc settingsBloc;
  late MockHomeBloc homeBloc;
  late MockSoftwareWallet wallet;
  late MockRealUnitReferralService referral;

  setUp(() async {
    await GetIt.instance.reset();
    settingsBloc = MockSettingsBloc();
    homeBloc = MockHomeBloc();
    wallet = MockSoftwareWallet();
    referral = MockRealUnitReferralService();

    when(() => wallet.walletType).thenReturn(WalletType.software);
    when(() => settingsBloc.state).thenReturn(const SettingsState());
    when(() => homeBloc.state).thenReturn(HomeState(openWallet: wallet));
    GetIt.instance.registerSingleton<SettingsBloc>(settingsBloc);
    GetIt.instance.registerSingleton<RealUnitReferralService>(referral);
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  Future<void> pumpSettings(WidgetTester tester) {
    return tester.pumpWidget(
      wrapForGolden(
        BlocProvider<HomeBloc>.value(
          value: homeBloc,
          child: const SettingsPage(unavailablePollInterval: Duration.zero),
        ),
      ),
    );
  }

  testWidgets('shows Empfehlungen when the API gate is open', (tester) async {
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

    await pumpSettings(tester);
    await tester.pumpAndSettle();

    expect(find.text('Empfehlungen'), findsOneWidget);
    expect(find.text('Erhalte 20 REALU pro Weiterempfehlung'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byIcon(Icons.card_giftcard_outlined),
        matching: find.byType(ExcludeSemantics),
      ),
      findsOneWidget,
    );
  });

  testWidgets('hides Empfehlungen when the API gate is closed', (tester) async {
    when(() => referral.getSummary()).thenAnswer(
      (_) async => const ReferralSummaryDto(
        eligible: false,
        termsAccepted: false,
        openCount: 0,
        creditedCount: 0,
        realuSum: 0,
        chfSum: 0,
      ),
    );

    await pumpSettings(tester);
    await tester.pumpAndSettle();

    expect(find.text('Empfehlungen'), findsNothing);
  });

  testWidgets('hides Empfehlungen when summary is unmounted', (tester) async {
    when(() => referral.getSummary()).thenThrow(
      const ApiException(
        statusCode: 404,
        code: 'NOT_FOUND',
        message: 'Cannot GET /v1/realunit/referral/summary',
      ),
    );

    await pumpSettings(tester);
    await tester.pump();
    await tester.pump();

    expect(find.text('Empfehlungen'), findsNothing);
    expect(find.text('Erhalte 20 REALU pro Weiterempfehlung'), findsNothing);
  });
}
