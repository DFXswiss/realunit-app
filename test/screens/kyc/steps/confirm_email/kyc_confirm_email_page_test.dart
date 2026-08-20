import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_registration_service.dart';
import 'package:realunit_wallet/screens/kyc/cubits/kyc/kyc_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/confirm_email/cubits/kyc_confirm_email_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/confirm_email/kyc_confirm_email_page.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';

import '../../../../helper/pump_app.dart';

class MockKycConfirmEmailCubit extends MockCubit<KycConfirmEmailState>
    implements KycConfirmEmailCubit {}

class MockKycCubit extends MockCubit<KycState> implements KycCubit {}

class MockRealUnitRegistrationService extends Mock
    implements RealUnitRegistrationService {}

void main() {
  late KycConfirmEmailCubit confirmCubit;
  late KycCubit kycCubit;

  setUp(() {
    confirmCubit = MockKycConfirmEmailCubit();
    kycCubit = MockKycCubit();

    when(() => confirmCubit.state).thenReturn(const KycConfirmEmailInitial());
    when(() => confirmCubit.recheck()).thenAnswer((_) => Future.value());
    when(() => kycCubit.state).thenReturn(const KycInitial());
    when(() => kycCubit.checkKyc()).thenAnswer((_) => Future.value());
  });

  setUpAll(() {
    GetIt.instance.registerSingleton<RealUnitRegistrationService>(
      MockRealUnitRegistrationService(),
    );
  });

  tearDownAll(() async => await GetIt.instance.reset());

  Widget buildSubject(Widget child) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<KycCubit>.value(value: kycCubit),
        BlocProvider<KycConfirmEmailCubit>.value(value: confirmCubit),
      ],
      child: child,
    );
  }

  group('$KycConfirmEmailPage', () {
    testWidgets('renders $KycConfirmEmailView', (tester) async {
      await tester.pumpApp(
        BlocProvider<KycCubit>.value(
          value: kycCubit,
          child: const KycConfirmEmailPage(),
        ),
      );

      expect(find.byType(KycConfirmEmailView), findsOne);
    });
  });

  group('$KycConfirmEmailView', () {
    testWidgets('renders an enabled button initially and taps trigger recheck', (
      tester,
    ) async {
      await tester.pumpApp(buildSubject(const KycConfirmEmailView()));

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNotNull);

      await tester.tap(find.byType(FilledButton));
      await tester.pump();

      verify(() => confirmCubit.recheck()).called(1);
    });

    testWidgets('disables the button while loading', (tester) async {
      when(() => confirmCubit.state).thenReturn(const KycConfirmEmailLoading());

      await tester.pumpApp(buildSubject(const KycConfirmEmailView()));

      final button = tester.widget<AppFilledButton>(find.byType(AppFilledButton));
      expect(button.state, FilledButtonState.loading);
    });
  });

  group('$BlocListener', () {
    testWidgets('shows a SnackBar when the address is not confirmed yet', (
      tester,
    ) async {
      whenListen(
        confirmCubit,
        Stream.fromIterable([const KycConfirmEmailNotConfirmed()]),
        initialState: const KycConfirmEmailInitial(),
      );

      await tester.pumpApp(buildSubject(const KycConfirmEmailView()));
      await tester.pump();

      expect(find.byType(SnackBar), findsOne);
      verifyNever(() => kycCubit.checkKyc());
    });

    testWidgets('shows the API message 1:1 when the re-check fails', (
      tester,
    ) async {
      whenListen(
        confirmCubit,
        Stream.fromIterable([const KycConfirmEmailFailure('Price source is temporarily unavailable')]),
        initialState: const KycConfirmEmailInitial(),
      );

      await tester.pumpApp(buildSubject(const KycConfirmEmailView()));
      await tester.pump();

      expect(find.text('Price source is temporarily unavailable'), findsOne);
      verifyNever(() => kycCubit.checkKyc());
    });

    testWidgets('re-runs checkKyc when the address is confirmed', (tester) async {
      whenListen(
        confirmCubit,
        Stream.fromIterable([const KycConfirmEmailConfirmed()]),
        initialState: const KycConfirmEmailInitial(),
      );

      await tester.pumpApp(buildSubject(const KycConfirmEmailView()));
      await tester.pump();

      verify(() => kycCubit.checkKyc()).called(1);
    });
  });
}
