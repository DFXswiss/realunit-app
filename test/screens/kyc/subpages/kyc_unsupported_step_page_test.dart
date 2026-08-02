import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/dfx/models/kyc/kyc_level.dart';
import 'package:realunit_wallet/screens/kyc/cubits/kyc/kyc_cubit.dart';
import 'package:realunit_wallet/screens/kyc/subpages/kyc_unsupported_step_page.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';
import 'package:realunit_wallet/widgets/buttons/app_text_button.dart';

import '../../../helper/pump_app.dart';

class _MockKycCubit extends MockCubit<KycState> implements KycCubit {}

void main() {
  late _MockKycCubit kycCubit;

  setUp(() {
    kycCubit = _MockKycCubit();
    when(() => kycCubit.state).thenReturn(const KycInitial());
    when(() => kycCubit.checkKyc()).thenAnswer((_) => Future.value());
  });

  Widget subject() => BlocProvider<KycCubit>.value(
    value: kycCubit,
    child: const KycUnsupportedStepPage(),
  );

  group('$KycUnsupportedStepPage', () {
    testWidgets('offers both a retry and a route to support', (tester) async {
      await tester.pumpApp(subject());

      expect(find.byType(AppFilledButton), findsOne);
      expect(find.byType(AppTextButton), findsOne);
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
