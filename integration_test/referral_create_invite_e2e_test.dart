import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_created_invite_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_summary_dto.dart';
import 'package:realunit_wallet/screens/referral/cubit/referral_cubit.dart';
import 'package:realunit_wallet/screens/referral/referral_create_page.dart';
import 'package:realunit_wallet/styles/themes.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';

class _MockReferralCubit extends MockCubit<ReferralState> implements ReferralCubit {}

const _summary = ReferralSummaryDto(
  eligible: true,
  termsAccepted: true,
  openCount: 0,
  creditedCount: 0,
  realuSum: 0,
  chfSum: 0,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late _MockReferralCubit cubit;

  setUp(() {
    cubit = _MockReferralCubit();
    when(() => cubit.isClosed).thenReturn(false);
  });

  Future<void> pumpCreate(WidgetTester tester) {
    return tester.pumpWidget(
      MaterialApp(
        theme: realUnitTheme,
        locale: const Locale('de'),
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
        home: BlocProvider<ReferralCubit>.value(
          value: cubit,
          child: const ReferralCreateView(),
        ),
      ),
    );
  }

  testWidgets('does not create an invite when the guest name is empty', (tester) async {
    when(() => cubit.state).thenReturn(const ReferralCreateReady(summary: _summary));
    whenListen(
      cubit,
      const Stream<ReferralState>.empty(),
      initialState: const ReferralCreateReady(summary: _summary),
    );

    await pumpCreate(tester);
    await tester.pump();
    await tester.tap(find.byType(AppFilledButton));
    await tester.pump();

    expect(
      find.text('Bitte den Vornamen der eingeladenen Person eingeben.'),
      findsOneWidget,
    );
    verifyNever(() => cubit.createInvite(guestName: any(named: 'guestName')));
  });

  testWidgets('submits the guest name and creates the invite', (tester) async {
    when(() => cubit.state).thenReturn(const ReferralCreateReady(summary: _summary));
    whenListen(
      cubit,
      const Stream<ReferralState>.empty(),
      initialState: const ReferralCreateReady(summary: _summary),
    );
    when(() => cubit.createInvite(guestName: any(named: 'guestName'))).thenAnswer((_) async {});

    await pumpCreate(tester);
    await tester.pump();
    await tester.enterText(find.byType(TextFormField), '  Alice   Bob  ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    verify(() => cubit.createInvite(guestName: 'Alice Bob')).called(1);
  });

  testWidgets('after create, shows the named invite', (tester) async {
    const created = ReferralCreatedInviteDto(
      code: 'AB12CD',
      url: 'https://realunit.app/invite/AB12CD',
      guestName: 'Alice',
    );
    when(() => cubit.state).thenReturn(
      const ReferralInviteCreated(summary: _summary, invite: created),
    );
    whenListen(
      cubit,
      const Stream<ReferralState>.empty(),
      initialState: const ReferralInviteCreated(summary: _summary, invite: created),
    );

    await pumpCreate(tester);
    await tester.pump();

    expect(find.text('Deine Einladung für Alice'), findsOneWidget);
    expect(find.text('Persönlicher Einladungslink'), findsOneWidget);
  });
}
