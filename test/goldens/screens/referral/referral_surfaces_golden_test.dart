import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/models/transaction.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_created_invite_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_invite_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_summary_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_referral_service.dart';
import 'package:realunit_wallet/packages/utils/default_assets.dart';
import 'package:realunit_wallet/screens/dashboard/widgets/transaction_row.dart';
import 'package:realunit_wallet/screens/referral/cubit/referral_cubit.dart';
import 'package:realunit_wallet/screens/referral/referral_create_page.dart';
import 'package:realunit_wallet/screens/referral/referral_page.dart';
import 'package:realunit_wallet/screens/referral/referral_terms_page.dart';
import 'package:realunit_wallet/screens/referral/widgets/referral_entry_card.dart';
import 'package:realunit_wallet/screens/settings/bloc/settings_bloc.dart';
import 'package:realunit_wallet/styles/language.dart';

import '../../../helper/helper.dart';

class _MockReferralCubit extends MockCubit<ReferralState>
    implements ReferralCubit {}

class _MockService extends Mock implements RealUnitReferralService {}

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

const _summary = ReferralSummaryDto(
  eligible: true,
  termsAccepted: true,
  openCount: 0,
  creditedCount: 0,
  realuSum: 0,
  chfSum: 0,
);

void main() {
  late _MockReferralCubit cubit;

  setUp(() {
    cubit = _MockReferralCubit();
  });

  group('referral surfaces', () {
    goldenTest(
      'dashboard card when eligible',
      fileName: 'referral_entry_card_eligible',
      constraints: phoneConstraints,
      pumpBeforeTest: (tester) async {
        await tester.pumpAndSettle();
      },
      builder: () {
        final service = _MockService();
        if (GetIt.instance.isRegistered<RealUnitReferralService>()) {
          GetIt.instance.unregister<RealUnitReferralService>();
        }
        GetIt.instance.registerSingleton<RealUnitReferralService>(service);
        when(() => service.getSummary()).thenAnswer((_) async => _summary);
        return wrapForGolden(
          const Scaffold(body: ReferralEntryCard()),
        );
      },
    );

    goldenTest(
      'not-eligible gate',
      fileName: 'referral_gate_not_eligible',
      constraints: phoneConstraints,
      builder: () {
        when(() => cubit.state).thenReturn(const ReferralNotEligible());
        whenListen(
          cubit,
          const Stream<ReferralState>.empty(),
          initialState: const ReferralNotEligible(),
        );
        return wrapForGolden(
          BlocProvider<ReferralCubit>.value(
            value: cubit,
            child: const ReferralGateView(),
          ),
        );
      },
    );

    goldenTest(
      'create page after personal invite',
      fileName: 'referral_create_page_invite_created',
      constraints: phoneConstraints,
      builder: () {
        const created = ReferralCreatedInviteDto(
          code: 'AB12CD',
          url: 'https://realunit.app/invite/AB12CD',
          guestName: 'Alice',
          copyText:
              'Hey Alice, Björn lädt dich ein zu RealUnit: https://realunit.app/invite/AB12CD',
        );
        when(() => cubit.state).thenReturn(
          const ReferralInviteCreated(summary: _summary, invite: created),
        );
        whenListen(
          cubit,
          const Stream<ReferralState>.empty(),
          initialState: const ReferralInviteCreated(
            summary: _summary,
            invite: created,
          ),
        );
        return wrapForGolden(
          BlocProvider<ReferralCubit>.value(
            value: cubit,
            child: const ReferralCreateView(),
          ),
        );
      },
    );

    goldenTest(
      'terms page checkbox gelesen und akzeptiert',
      fileName: 'referral_terms_page_default',
      constraints: phoneConstraints,
      builder: () {
        when(() => cubit.state).thenReturn(
          const ReferralNeedsTerms(summary: _summary),
        );
        whenListen(
          cubit,
          const Stream<ReferralState>.empty(),
          initialState: const ReferralNeedsTerms(summary: _summary),
        );
        return wrapForGolden(
          BlocProvider<ReferralCubit>.value(
            value: cubit,
            child: const ReferralTermsPage(
              initialMarkdownContent: _termsMarkdownStub,
            ),
          ),
        );
      },
    );

    goldenTest(
      'terms page read-only after accept',
      fileName: 'referral_terms_page_readonly',
      constraints: phoneConstraints,
      builder: () {
        when(() => cubit.state).thenReturn(
          const ReferralOverviewLoaded(
            summary: _summary,
            invites: <ReferralInviteDto>[],
          ),
        );
        whenListen(
          cubit,
          const Stream<ReferralState>.empty(),
          initialState: const ReferralOverviewLoaded(
            summary: _summary,
            invites: <ReferralInviteDto>[],
          ),
        );
        return wrapForGolden(
          BlocProvider<ReferralCubit>.value(
            value: cubit,
            child: const ReferralTermsPage(
              initialMarkdownContent: _termsMarkdownStub,
              readOnly: true,
            ),
          ),
        );
      },
    );

    goldenTest(
      'create page name entry',
      fileName: 'referral_create_page_name_entry',
      constraints: phoneConstraints,
      builder: () {
        when(() => cubit.state).thenReturn(
          const ReferralCreateReady(summary: _summary),
        );
        whenListen(
          cubit,
          const Stream<ReferralState>.empty(),
          initialState: const ReferralCreateReady(summary: _summary),
        );
        return wrapForGolden(
          BlocProvider<ReferralCubit>.value(
            value: cubit,
            child: const ReferralCreateView(),
          ),
        );
      },
    );

    goldenTest(
      'history prize row with frozen CHF',
      fileName: 'referral_payout_transaction_row_default',
      constraints: phoneConstraints,
      builder: () {
        final settings = _MockSettingsBloc();
        const settingsState = SettingsState(language: Language.de);
        when(() => settings.state).thenReturn(settingsState);
        whenListen(
          settings,
          const Stream<SettingsState>.empty(),
          initialState: settingsState,
        );
        return wrapForGolden(
          BlocProvider<SettingsBloc>.value(
            value: settings,
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: ReferralPayoutTransactionRow(
                  transaction: Transaction(
                    height: 0,
                    txId: 'referral-payout-7',
                    chainId: realUnitAsset.chainId,
                    senderAddress: kReferralPayoutSenderAddress,
                    receiverAddress: '0xabc',
                    amount: BigInt.from(20),
                    asset: realUnitAsset,
                    type: TransactionTypes.referralPayout,
                    note: '',
                    data: '246.50',
                    timestamp: DateTime.utc(2026, 8, 24, 10),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  });
}

const _termsMarkdownStub = '''# Teilnahmebedingungen Referral-Programm RealUnit App

*Stand: 14.08.2026*

## 1. Veranstalterin

RealUnit Schweiz AG, Schochenmühlestrasse 6, 6340 Baar. Das Referral-Programm wird in der RealUnit App angeboten.

## 2. Teilnahmeberechtigung

Teilnahmeberechtigt sind natürliche Personen, die in der RealUnit App registriert und verifiziert sind und mindestens 70 RealUnit-Aktientoken im eigenen Wallet halten.
''';
