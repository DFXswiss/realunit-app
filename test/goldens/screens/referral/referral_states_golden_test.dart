import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_summary_dto.dart';
import 'package:realunit_wallet/screens/referral/cubit/referral_cubit.dart';
import 'package:realunit_wallet/screens/referral/referral_create_page.dart';
import 'package:realunit_wallet/screens/referral/referral_error_message.dart';
import 'package:realunit_wallet/screens/referral/referral_overview_page.dart';
import 'package:realunit_wallet/screens/referral/referral_page.dart';
import 'package:realunit_wallet/screens/referral/referral_terms_page.dart';
import 'package:realunit_wallet/screens/settings/bloc/settings_bloc.dart';
import 'package:realunit_wallet/styles/language.dart';

import '../../../helper/helper.dart';

class _MockReferralCubit extends MockCubit<ReferralState> implements ReferralCubit {}

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState> implements SettingsBloc {}

const _summary = ReferralSummaryDto(
  eligible: true,
  termsAccepted: true,
  openCount: 1,
  creditedCount: 2,
  realuSum: 40,
  chfSum: 512.4,
  sharePriceLabel: 'Aktienkurs',
  sharePrice: 1.38,
);

const _termsMarkdownStub = '''# Teilnahmebedingungen Referral-Programm RealUnit App

*Stand: 14.08.2026*

## 1. Veranstalterin

RealUnit Schweiz AG, Schochenmühlestrasse 6, 6340 Baar.
''';

void main() {
  late _MockReferralCubit cubit;
  late _MockSettingsBloc settings;

  setUp(() {
    cubit = _MockReferralCubit();
    settings = _MockSettingsBloc();
    const settingsState = SettingsState(language: Language.de);
    when(() => settings.state).thenReturn(settingsState);
    whenListen(
      settings,
      const Stream<SettingsState>.empty(),
      initialState: settingsState,
    );
  });

  Widget wrapCubit(ReferralState state, Widget child, {bool withSettings = false}) {
    when(() => cubit.state).thenReturn(state);
    whenListen(cubit, const Stream<ReferralState>.empty(), initialState: state);
    final gated = BlocProvider<ReferralCubit>.value(value: cubit, child: child);
    if (!withSettings) return wrapForGolden(gated);
    return wrapForGolden(
      MultiBlocProvider(
        providers: [
          BlocProvider<ReferralCubit>.value(value: cubit),
          BlocProvider<SettingsBloc>.value(value: settings),
        ],
        child: child,
      ),
    );
  }

  group('referral screen states', () {
    goldenTest(
      'gate loading',
      fileName: 'referral_gate_loading',
      constraints: phoneConstraints,
      pumpBeforeTest: pumpOnce,
      builder: () => wrapCubit(
        const ReferralLoading(),
        const ReferralGateView(),
      ),
    );

    goldenTest(
      'gate unavailable error',
      fileName: 'referral_gate_failure',
      constraints: phoneConstraints,
      builder: () => wrapCubit(
        const ReferralFailure(message: referralUnavailableMessage),
        const ReferralGateView(),
      ),
    );

    goldenTest(
      'gate quarter cap',
      fileName: 'referral_gate_quota',
      constraints: phoneConstraints,
      builder: () => wrapCubit(
        const ReferralFailure(message: referralQuotaMessage),
        const ReferralGateView(),
      ),
    );

    goldenTest(
      'overview loading',
      fileName: 'referral_overview_page_loading',
      constraints: phoneConstraints,
      pumpBeforeTest: pumpOnce,
      builder: () => wrapCubit(
        const ReferralLoading(),
        const ReferralOverviewPage(),
        withSettings: true,
      ),
    );

    goldenTest(
      'overview unavailable error',
      fileName: 'referral_overview_page_failure',
      constraints: phoneConstraints,
      builder: () => wrapCubit(
        const ReferralFailure(message: referralUnavailableMessage),
        const ReferralOverviewPage(),
        withSettings: true,
      ),
    );

    goldenTest(
      'overview invite list error',
      fileName: 'referral_overview_page_invites_error',
      constraints: phoneConstraints,
      builder: () => wrapCubit(
        const ReferralOverviewLoaded(
          summary: _summary,
          invites: [],
          invitesError: referralUnavailableMessage,
        ),
        const ReferralOverviewPage(),
        withSettings: true,
      ),
    );

    goldenTest(
      'create page loading',
      fileName: 'referral_create_page_loading',
      constraints: phoneConstraints,
      pumpBeforeTest: pumpOnce,
      builder: () => wrapCubit(
        const ReferralLoading(),
        const ReferralCreateView(),
      ),
    );

    goldenTest(
      'create page not eligible',
      fileName: 'referral_create_page_not_eligible',
      constraints: phoneConstraints,
      builder: () => wrapCubit(
        const ReferralNotEligible(),
        const ReferralCreateView(),
      ),
    );

    goldenTest(
      'create page invalid error',
      fileName: 'referral_create_page_error',
      constraints: phoneConstraints,
      builder: () => wrapCubit(
        const ReferralCreateReady(
          summary: _summary,
          errorMessage: referralInvalidMessage,
        ),
        const ReferralCreateView(),
      ),
    );

    goldenTest(
      'create page quarter cap',
      fileName: 'referral_create_page_quota',
      constraints: phoneConstraints,
      builder: () => wrapCubit(
        const ReferralCreateReady(
          summary: _summary,
          errorMessage: referralQuotaMessage,
        ),
        const ReferralCreateView(),
      ),
    );

    goldenTest(
      'create page creating',
      fileName: 'referral_create_page_creating',
      constraints: phoneConstraints,
      pumpBeforeTest: pumpOnce,
      builder: () => wrapCubit(
        const ReferralCreating(summary: _summary, guestName: 'Alice'),
        const ReferralCreateView(),
      ),
    );

    goldenTest(
      'terms page accept error',
      fileName: 'referral_terms_page_error',
      constraints: phoneConstraints,
      builder: () => wrapCubit(
        const ReferralNeedsTerms(
          summary: _summary,
          errorMessage: referralUnavailableMessage,
        ),
        const ReferralTermsPage(initialMarkdownContent: _termsMarkdownStub),
      ),
    );
  });
}
