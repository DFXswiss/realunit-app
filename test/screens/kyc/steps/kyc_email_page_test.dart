import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_widget_service.dart';
import 'package:realunit_wallet/packages/service/dfx/models/registration/registration_email_status.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_registration_service.dart';
import 'package:realunit_wallet/screens/home/bloc/home_bloc.dart';
import 'package:realunit_wallet/screens/kyc/cubits/kyc/kyc_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/email/cubits/email_step/kyc_email_step_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/email/kyc_email_page.dart';
import 'package:realunit_wallet/widgets/form/labeled_text_field.dart';

import '../../../helper/pump_app.dart';

class MockKycEmailStepCubit extends MockCubit<KycEmailStepState> implements KycEmailStepCubit {}

class MockKycCubit extends MockCubit<KycState> implements KycCubit {}

class MockHomeBloc extends MockBloc<HomeEvent, HomeState> implements HomeBloc {}

class MockRealUnitRegistrationService extends Mock implements RealUnitRegistrationService {}

class MockDfxWidgetService extends Mock implements DfxWidgetService {}

/// Pops the first pushed sub-route with the configured [value], so a test can
/// simulate the merge-confirmation page returning success without having to
/// fully mount [KycEmailVerificationPage] and drive its button. The first
/// `didPush` from `pumpWidget` itself (the test's own root route) is skipped.
class _AutoPopObserver extends NavigatorObserver {
  _AutoPopObserver({this.value});

  final Object? value;
  bool _seenRoot = false;
  bool _popped = false;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (!_seenRoot) {
      _seenRoot = true;
      return;
    }
    if (_popped) return;
    _popped = true;
    // Pop on the next microtask so the route gets fully mounted first —
    // matches how a real user would tap "I've confirmed" after the page
    // appears.
    Future.microtask(() => route.navigator?.pop<bool>(value as bool?));
  }
}

void main() {
  late KycEmailStepCubit kycEmailStepCubit;
  late KycCubit kycCubit;
  late HomeBloc homeBloc;

  setUp(() {
    kycEmailStepCubit = MockKycEmailStepCubit();
    kycCubit = MockKycCubit();
    homeBloc = MockHomeBloc();

    when(() => kycEmailStepCubit.state).thenReturn(const KycEmailStepInitial());
    when(() => kycCubit.state).thenReturn(const KycInitial());
    when(() => kycCubit.checkKyc()).thenAnswer((_) => Future.value());
    when(() => homeBloc.state).thenReturn(const HomeState());
  });

  void setupDependencyInjection() {
    final getIt = GetIt.instance;
    getIt.registerSingleton<RealUnitRegistrationService>(MockRealUnitRegistrationService());
    getIt.registerSingleton<DfxWidgetService>(MockDfxWidgetService());
  }

  setUpAll(() {
    setupDependencyInjection();
  });

  tearDownAll(() async => await GetIt.instance.reset());

  Widget buildSubject(Widget child) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: kycCubit),
        BlocProvider.value(value: kycEmailStepCubit),
        BlocProvider.value(value: homeBloc),
      ],
      child: child,
    );
  }

  group('$KycEmailPage', () {
    testWidgets('renders $KycEmailView', (tester) async {
      await tester.pumpApp(const KycEmailPage());

      expect(find.byType(KycEmailView), findsOne);
    });
  });

  group('$KycEmailView', () {
    testWidgets('is rendered initially correctly', (tester) async {
      await tester.pumpApp(buildSubject(const KycEmailView()));

      expect(find.byType(LabeledTextField), findsOne);
      final buttonWidget = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(buttonWidget.onPressed, isNotNull);
    });

    testWidgets('is rendered correctly when loading', (tester) async {
      when(() => kycEmailStepCubit.state).thenReturn(const KycEmailStepLoading());

      await tester.pumpApp(buildSubject(const KycEmailView()));

      expect(find.byType(LabeledTextField), findsOne);
      final buttonWidget = tester.widget<FilledButton>(find.bySubtype<FilledButton>());
      expect(buttonWidget.onPressed, isNull);
    });
  });

  group('$BlocListener', () {
    testWidgets('triggers checkKyc if submitting successes', (tester) async {
      whenListen(
        kycEmailStepCubit,
        Stream.fromIterable([
          const KycEmailStepSuccess(.emailRegistered),
        ]),
        initialState: const KycEmailStepInitial(),
      );

      await tester.pumpApp(buildSubject(const KycEmailView()));
      await tester.pump();

      verify(() => kycCubit.checkKyc()).called(1);
    });

    testWidgets('shows SnackBar if submitting fails', (tester) async {
      whenListen(
        kycEmailStepCubit,
        Stream.fromIterable([const KycEmailStepFailure(.emailDoesNotMatch, 'fail')]),
        initialState: const KycEmailStepInitial(),
      );

      await tester.pumpApp(buildSubject(const KycEmailView()));
      await tester.pump();

      expect(find.byType(SnackBar), findsOne);
    });

    testWidgets(
      're-runs checkKyc after merge confirm pops with true',
      (tester) async {
        whenListen(
          kycEmailStepCubit,
          Stream.fromIterable([
            const KycEmailStepSuccess(RegistrationEmailStatus.mergeRequested),
          ]),
          initialState: const KycEmailStepInitial(),
        );

        // Wrap directly so we can install a NavigatorObserver that auto-pops
        // the verification page with `true` — simulating a successful merge
        // confirmation. `pumpApp` doesn't expose observers.
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: const [
              S.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: S.delegate.supportedLocales,
            navigatorObservers: [_AutoPopObserver(value: true)],
            home: buildSubject(const KycEmailView()),
          ),
        );
        await tester.pumpAndSettle();

        verify(() => kycCubit.checkKyc()).called(1);
      },
    );

    testWidgets(
      'does NOT call checkKyc when merge confirm pops with false / null',
      (tester) async {
        whenListen(
          kycEmailStepCubit,
          Stream.fromIterable([
            const KycEmailStepSuccess(RegistrationEmailStatus.mergeRequested),
          ]),
          initialState: const KycEmailStepInitial(),
        );

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: const [
              S.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: S.delegate.supportedLocales,
            // Pop with `null` (e.g. user backs out of the verification page).
            navigatorObservers: [_AutoPopObserver(value: null)],
            home: buildSubject(const KycEmailView()),
          ),
        );
        await tester.pumpAndSettle();

        verifyNever(() => kycCubit.checkKyc());
      },
    );
  });
}
