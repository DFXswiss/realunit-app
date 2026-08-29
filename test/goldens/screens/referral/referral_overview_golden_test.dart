import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_invite_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_summary_dto.dart';
import 'package:realunit_wallet/screens/referral/cubit/referral_cubit.dart';
import 'package:realunit_wallet/screens/referral/referral_overview_page.dart';
import 'package:realunit_wallet/screens/settings/bloc/settings_bloc.dart';
import 'package:realunit_wallet/styles/language.dart';

import '../../../helper/helper.dart';

class _MockReferralCubit extends MockCubit<ReferralState>
    implements ReferralCubit {}

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState>
    implements SettingsBloc {}

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

  Widget buildOverview(ReferralState state) {
    when(() => cubit.state).thenReturn(state);
    whenListen(cubit, const Stream<ReferralState>.empty(), initialState: state);
    return wrapForGolden(
      MultiBlocProvider(
        providers: [
          BlocProvider<ReferralCubit>.value(value: cubit),
          BlocProvider<SettingsBloc>.value(value: settings),
        ],
        child: const ReferralOverviewPage(),
      ),
    );
  }

  group('$ReferralOverviewPage', () {
    goldenTest(
      'overview with open invite, Aktienkurs tile',
      fileName: 'referral_overview_page_default',
      constraints: phoneConstraints,
      builder: () {
        const summary = ReferralSummaryDto(
          eligible: true,
          termsAccepted: true,
          openCount: 1,
          creditedCount: 2,
          realuSum: 40,
          chfSum: 512.4,
          sharePriceLabel: 'Aktienkurs',
          sharePrice: 1.38,
        );
        final invites = [
          ReferralInviteDto(
            id: 1,
            code: 'AB12CD',
            url: 'https://realunit.app/invite/AB12CD',
            guestName: 'Alice',
            status: 'Open',
            created: DateTime.utc(2026, 8, 1),
            copyText:
                'Hey Alice, Björn lädt dich ein zu RealUnit: https://realunit.app/invite/AB12CD',
          ),
        ];
        return buildOverview(
          ReferralOverviewLoaded(summary: summary, invites: invites),
        );
      },
    );
  });
}
