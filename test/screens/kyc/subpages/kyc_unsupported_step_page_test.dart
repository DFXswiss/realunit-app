import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/setup/routing/routes/support_routes.dart';
import 'package:realunit_wallet/packages/service/dfx/models/kyc/kyc_level.dart';
import 'package:realunit_wallet/screens/kyc/cubits/kyc/kyc_cubit.dart';
import 'package:realunit_wallet/screens/kyc/subpages/kyc_unsupported_step_page.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';
import 'package:realunit_wallet/widgets/buttons/app_text_button.dart';

import '../../../helper/pump_app.dart';

class _MockKycCubit extends MockCubit<KycState> implements KycCubit {}

void main() {
  late _MockKycCubit kycCubit;

  // Hosting a router is what makes the support handoff assertable: without one the CTA's
  // `pushNamed` throws, so a test that only checks the button exists proves nothing about where it
  // goes. Mirrors settings_contact_page_test.
  late List<String> pushedRoutes;

  setUp(() {
    kycCubit = _MockKycCubit();
    when(() => kycCubit.state).thenReturn(const KycInitial());
    when(() => kycCubit.checkKyc()).thenAnswer((_) => Future.value());
    pushedRoutes = [];
  });

  Widget subject() => BlocProvider<KycCubit>.value(
    value: kycCubit,
    child: const KycUnsupportedStepPage(),
  );

  GoRouter buildRouter() => GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, _) => subject()),
      GoRoute(
        name: SupportRoutes.support,
        path: '/support',
        builder: (_, _) {
          pushedRoutes.add(SupportRoutes.support);
          return const Scaffold(body: Text('SUPPORT'));
        },
      ),
    ],
  );

  group('$KycUnsupportedStepPage', () {
    testWidgets('offers both a retry and a route to support', (tester) async {
      await tester.pumpApp(subject());

      expect(find.byType(AppFilledButton), findsOne);
      expect(find.byType(AppTextButton), findsOne);
    });

    testWidgets('the support action navigates to the support screen', (tester) async {
      await tester.pumpWidget(
        MaterialApp.router(
          // pumpApp cannot host a router, so the delegates it normally supplies are repeated here
          localizationsDelegates: [S.delegate, GlobalMaterialLocalizations.delegate],
          supportedLocales: S.delegate.supportedLocales,
          routerConfig: buildRouter(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(AppTextButton));
      await tester.pumpAndSettle();

      expect(pushedRoutes, [SupportRoutes.support]);
    });

    // The whole point of the page: the previous screen was a dead end with no actions at all.
    testWidgets('the retry re-reads the KYC state', (tester) async {
      await tester.pumpApp(subject());

      await tester.tap(find.byType(AppFilledButton));
      await tester.pump();

      verify(() => kycCubit.checkKyc()).called(1);
    });

    // The step identifier is an internal enum value; surfacing it told the user nothing and was the
    // defect this page replaces.
    testWidgets('never renders an internal step identifier', (tester) async {
      await tester.pumpApp(subject());

      for (final name in KycStepName.values) {
        expect(
          find.textContaining(name.value),
          findsNothing,
          reason: 'the wire identifier ${name.value} must not reach the UI',
        );
      }
    });
  });
}
