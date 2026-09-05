import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_summary_dto.dart';
import 'package:realunit_wallet/screens/kyc/steps/registration/widgets/referral_code_field.dart';
import 'package:realunit_wallet/screens/referral/cubit/referral_cubit.dart';
import 'package:realunit_wallet/screens/referral/referral_create_page.dart';
import 'package:realunit_wallet/screens/referral/referral_error_message.dart';
import 'package:realunit_wallet/screens/referral/referral_page.dart';
import 'package:realunit_wallet/styles/themes.dart';

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

  Future<void> pumpApp(WidgetTester tester, {required Widget home}) {
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
        home: home,
      ),
    );
  }

  testWidgets('invalid lookup shows ungültig copy on the registration field', (
    tester,
  ) async {
    final ctrl = TextEditingController(text: 'NOPE');
    addTearDown(ctrl.dispose);
    await pumpApp(
      tester,
      home: Scaffold(
        body: ReferralCodeField(
          controller: ctrl,
          lookup: (_) async => throw const ApiException(
            statusCode: 404,
            code: 'NOT_FOUND',
            message: 'missing',
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      find.text('Dieser Code ist ungültig oder abgelaufen.'),
      findsOneWidget,
    );
  });

  testWidgets('not-eligible gate shows the programme closed copy', (
    tester,
  ) async {
    when(() => cubit.state).thenReturn(const ReferralNotEligible());
    whenListen(
      cubit,
      const Stream<ReferralState>.empty(),
      initialState: const ReferralNotEligible(),
    );

    await pumpApp(
      tester,
      home: BlocProvider<ReferralCubit>.value(
        value: cubit,
        child: const ReferralGateView(),
      ),
    );
    await tester.pump();

    expect(
      find.text(
        'Das Empfehlungsprogramm steht verifizierten Aktionären mit dem erforderlichen Bestand zur Verfügung.',
      ),
      findsOneWidget,
    );
    expect(find.text('Schließen'), findsOneWidget);
  });

  testWidgets('create form shows the quarterly prize-limit copy', (
    tester,
  ) async {
    when(() => cubit.state).thenReturn(
      const ReferralCreateReady(
        summary: _summary,
        errorMessage: referralQuotaMessage,
      ),
    );
    whenListen(
      cubit,
      const Stream<ReferralState>.empty(),
      initialState: const ReferralCreateReady(
        summary: _summary,
        errorMessage: referralQuotaMessage,
      ),
    );

    await pumpApp(
      tester,
      home: BlocProvider<ReferralCubit>.value(
        value: cubit,
        child: const ReferralCreateView(),
      ),
    );
    await tester.pump();

    expect(
      find.text('In diesem Quartal sind keine weiteren Prämien möglich.'),
      findsOneWidget,
    );
  });
}
