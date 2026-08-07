import 'package:bitbox_flutter/bitbox_flutter.dart' as sdk;
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/hardware_wallet/bitbox.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_country_service.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_kyc_service.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/registration_rejected_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/models/country/country.dart';
import 'package:realunit_wallet/packages/service/dfx/models/registration/dto/real_unit_registration_request_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/registration/kyc/kyc_personal_data.dart';
import 'package:realunit_wallet/packages/service/dfx/models/registration/registration.dart';
import 'package:realunit_wallet/packages/service/dfx/models/registration/registration_status.dart';
import 'package:realunit_wallet/packages/service/dfx/models/registration/registration_user_type.dart';
import 'package:realunit_wallet/packages/service/dfx/models/user/dto/real_unit_user_data_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_registration_service.dart';
import 'package:realunit_wallet/packages/service/wallet_service.dart';
import 'package:realunit_wallet/packages/wallet/exceptions/signing_cancelled_exception.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';
import 'package:realunit_wallet/screens/hardware_connect_bitbox/connect_bitbox_page.dart';
import 'package:realunit_wallet/screens/home/bloc/home_bloc.dart';
import 'package:realunit_wallet/screens/kyc/cubits/kyc/kyc_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/registration/cubits/registration_step/kyc_registration_step_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/registration/cubits/registration_submit/kyc_registration_submit_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/registration/kyc_registration_page.dart';
import 'package:realunit_wallet/screens/kyc/steps/registration/steps/kyc_registration_address_step.dart';
import 'package:realunit_wallet/screens/kyc/steps/registration/steps/kyc_registration_personal_step.dart';
import 'package:realunit_wallet/screens/kyc/steps/registration/steps/kyc_registration_tax_step.dart';
import 'package:realunit_wallet/styles/colors.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';
import 'package:realunit_wallet/widgets/form/labeled_text_field.dart';

import '../../../helper/helper.dart';

class MockRegistrationStepCubit extends MockCubit<KycRegistrationStepState>
    implements KycRegistrationStepCubit {}

class MockRegistrationSubmitCubit extends MockCubit<KycRegistrationSubmitState>
    implements KycRegistrationSubmitCubit {}

class MockKycCubit extends MockCubit<KycState> implements KycCubit {}

class MockRealUnitRegistrationService extends Mock implements RealUnitRegistrationService {}

class MockDfxKycService extends Mock implements DfxKycService {}

class MockHomeBloc extends MockBloc<HomeEvent, HomeState> implements HomeBloc {}

class MockAppStore extends Mock implements AppStore {}

class MockAWallet extends Mock implements AWallet {}

class MockWalletService extends Mock implements WalletService {}

class MockBitboxService extends Mock implements BitboxService {}

// Historical placeholder already used as the registration fixture in
// test/screens/kyc/cubits/kyc/kyc_cubit_test.dart — reused here for consistency.
const _country = Country(id: 41, symbol: 'CH', name: 'Switzerland', kycAllowed: true);

const _kycPersonalData = KycPersonalData(
  accountType: KycAccountType.personal,
  firstName: 'Ada',
  lastName: 'Lovelace',
  phone: '+41790000000',
  address: KycAddress(street: 'S', zip: '8000', city: 'Zurich', country: 41),
);

const _fixtureUserData = RealUnitUserDataDto(
  email: 'ada@example.com',
  name: 'Ada Lovelace',
  type: 'HUMAN',
  phoneNumber: '+41790000000',
  birthday: '1815-12-10',
  nationality: 'CH',
  addressStreet: 'S',
  addressPostalCode: '8000',
  addressCity: 'Zurich',
  addressCountry: 'CH',
  swissTaxResidence: true,
  lang: 'de',
  kycData: _kycPersonalData,
);

const _registrationFixture = Registration(
  type: RegistrationUserType.human,
  email: 'ada@example.com',
  firstName: 'Ada',
  lastName: 'Lovelace',
  phoneNumber: '+41790000000',
  birthday: '1815-12-10',
  nationality: _country,
  addressStreet: 'S',
  addressStreetNumber: '1',
  addressPostalCode: '8000',
  addressCity: 'Zurich',
  addressCountry: _country,
  swissTaxResidence: true,
);

const _switzerland = Country(id: 41, symbol: 'CH', name: 'Switzerland', kycAllowed: true);

void main() {
  late KycRegistrationStepCubit registrationStepCubit;
  late KycRegistrationSubmitCubit registrationSubmitCubit;
  late KycCubit kycCubit;
  late HomeBloc homeBloc;

  setUp(() {
    registrationStepCubit = MockRegistrationStepCubit();
    registrationSubmitCubit = MockRegistrationSubmitCubit();
    kycCubit = MockKycCubit();
    homeBloc = MockHomeBloc();

    when(() => registrationStepCubit.state).thenReturn(
      const KycRegistrationStepState(
        step: KycRegistrationStep.personal,
        steps: [
          KycRegistrationStep.personal,
          KycRegistrationStep.address,
        ],
      ),
    );
    when(() => registrationSubmitCubit.state).thenReturn(KycRegistrationSubmitInitial());
    when(() => kycCubit.state).thenReturn(const KycInitial());
    when(() => kycCubit.checkKyc()).thenAnswer((_) => Future.value());
  });

  // The page no longer reads from `RealUnitRegistrationService` directly — the parent
  // `KycCubit` propagates the `RealUnitUserDataDto` via constructor. We still
  // need the country/kyc/registration services for the BlocProvider inside
  // `KycRegistrationPage` (they are looked up via `getIt`).
  void setupDependencyInjection() {
    final getIt = GetIt.instance;
    getIt.registerSingleton<RealUnitRegistrationService>(MockRealUnitRegistrationService());
    getIt.registerSingleton<DfxCountryService>(fixtureCountryService());
    getIt.registerSingleton<DfxKycService>(MockDfxKycService());
    final appStore = MockAppStore();
    when(() => appStore.wallet).thenReturn(MockAWallet());
    getIt.registerSingleton<AppStore>(appStore);
    // The BitBox submit branch opens ConnectBitboxPage, which resolves a
    // BitboxService + WalletService from getIt on build. Stub the scan surface
    // so the page renders without a real device (no pairing is exercised here).
    final bitboxService = MockBitboxService();
    when(() => bitboxService.startScan()).thenAnswer((_) async => false);
    when(() => bitboxService.getAllUsbDevices()).thenAnswer((_) async => <sdk.BitboxDevice>[]);
    getIt.registerSingleton<BitboxService>(bitboxService);
    getIt.registerSingleton<WalletService>(MockWalletService());
  }

  setUpAll(() {
    registerFallbackValue(SyncWalletServicesEvent(MockAWallet()));
    registerFallbackValue(_registrationFixture);
    registerFallbackValue(_switzerland);
    registerFallbackValue(RegistrationUserType.human);
    setupDependencyInjection();
  });

  tearDownAll(() async => await GetIt.instance.reset());

  Widget buildSubject(Widget child) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: kycCubit),
        BlocProvider.value(value: registrationStepCubit),
        BlocProvider.value(value: registrationSubmitCubit),
        BlocProvider.value(value: homeBloc),
      ],
      child: child,
    );
  }

  group('$KycRegistrationPage', () {
    testWidgets('renders $KycRegistrationView with null initialUserData', (tester) async {
      // Non-const construction so the const KycRegistrationPage constructor runs
      // at runtime instead of being folded into a compile-time constant. Null
      // initialUserData keeps it side-effect free (no prefill country lookups).
      // ignore: prefer_const_constructors
      await tester.pumpApp(KycRegistrationPage());

      expect(find.byType(KycRegistrationView), findsOne);
    });
  });

  group('$KycRegistrationView', () {
    testWidgets('renders $KycRegistrationPersonalStep', (tester) async {
      final state = const KycRegistrationStepState(
        step: KycRegistrationStep.personal,
        steps: [
          KycRegistrationStep.personal,
          KycRegistrationStep.address,
        ],
      );
      when(() => registrationStepCubit.state).thenReturn(state);

      await tester.pumpApp(buildSubject(const KycRegistrationView()));
      // No prefill round-trip: the form is rendered synchronously. A single
      // pump is enough to settle initial frames.
      await tester.pump();

      (tester.widget(find.byType(PageView)) as PageView).controller?.jumpToPage(state.index);
      await tester.pump();

      expect(find.byType(KycRegistrationPersonalStep).hitTestable(), findsOne);
    });

    testWidgets('renders $KycRegistrationAddressStep', (tester) async {
      final state = const KycRegistrationStepState(
        step: KycRegistrationStep.address,
        steps: [
          KycRegistrationStep.personal,
          KycRegistrationStep.address,
        ],
      );
      when(() => registrationStepCubit.state).thenReturn(state);

      await tester.pumpApp(buildSubject(const KycRegistrationView()));
      await tester.pump();

      (tester.widget(find.byType(PageView)) as PageView).controller?.jumpToPage(state.index);
      await tester.pump();

      expect(find.byType(KycRegistrationAddressStep), findsOne);
    });

    testWidgets('postal code field uses a text keyboard for alphanumeric codes',
        (tester) async {
      // Regression guard: foreign postal codes are alphanumeric (NL "1011 AB",
      // UK "EC1A 1BB"). A number-only keyboard blocked customers from entering
      // them even though the validator + backend accept letters and spaces.
      final state = const KycRegistrationStepState(
        step: KycRegistrationStep.address,
        steps: [
          KycRegistrationStep.personal,
          KycRegistrationStep.address,
        ],
      );
      when(() => registrationStepCubit.state).thenReturn(state);

      await tester.pumpApp(buildSubject(const KycRegistrationView()));
      await tester.pump();

      (tester.widget(find.byType(PageView)) as PageView).controller?.jumpToPage(state.index);
      await tester.pump();

      final postalField = tester.widget<LabeledTextField>(
        find.byWidgetPredicate((w) => w is LabeledTextField && w.hintText == '8000'),
      );
      expect(postalField.keyboardType, TextInputType.text);
    });

    testWidgets('dismisses the keyboard when tapping outside the address fields',
        (tester) async {
      final state = const KycRegistrationStepState(
        step: KycRegistrationStep.address,
        steps: [
          KycRegistrationStep.personal,
          KycRegistrationStep.address,
        ],
      );
      when(() => registrationStepCubit.state).thenReturn(state);

      await tester.pumpApp(buildSubject(const KycRegistrationView()));
      await tester.pump();

      (tester.widget(find.byType(PageView)) as PageView).controller?.jumpToPage(state.index);
      await tester.pump();

      // Focus the street field so there is a primary focus to clear.
      final streetField = find
          .descendant(
            of: find.byType(KycRegistrationAddressStep),
            matching: find.byType(EditableText),
          )
          .first;
      final streetFocus = tester.widget<EditableText>(streetField).focusNode;
      await tester.tap(streetField);
      await tester.pump();
      expect(streetFocus.hasFocus, isTrue);

      // The opaque GestureDetector wrapping the form clears focus on tap — it is
      // the only opaque GestureDetector that is an ancestor of the address Form
      // (field/button gesture handlers are descendants of the Form).
      final dismissArea = find.ancestor(
        of: find.descendant(
          of: find.byType(KycRegistrationAddressStep),
          matching: find.byType(Form),
        ),
        matching: find.byWidgetPredicate(
          (w) => w is GestureDetector && w.behavior == HitTestBehavior.opaque && w.onTap != null,
        ),
      );
      expect(dismissArea, findsOneWidget);
      tester.widget<GestureDetector>(dismissArea).onTap!();
      await tester.pump();

      expect(streetFocus.hasFocus, isFalse);
    });
  });

  group('$BlocListener', () {
    testWidgets('triggers checkKyc if submitting successes', (tester) async {
      whenListen(
        registrationSubmitCubit,
        Stream.fromIterable([
          const KycRegistrationSubmitSuccess(RegistrationStatus.completed),
        ]),
        initialState: KycRegistrationSubmitInitial(),
      );

      await tester.pumpApp(buildSubject(const KycRegistrationView()));
      await tester.pump();

      verify(() => kycCubit.checkKyc()).called(1);
    });

    testWidgets('re-arms wallet services on registration success', (tester) async {
      // The RealUnit account now exists, so the balance poll (which stops
      // itself after 404ing while the account was missing) must be restarted.
      whenListen(
        registrationSubmitCubit,
        Stream.fromIterable([
          const KycRegistrationSubmitSuccess(RegistrationStatus.completed),
        ]),
        initialState: KycRegistrationSubmitInitial(),
      );

      await tester.pumpApp(buildSubject(const KycRegistrationView()));
      await tester.pump();

      verify(() => homeBloc.add(any(that: isA<SyncWalletServicesEvent>()))).called(1);
    });

    testWidgets(
      'triggers checkKyc on Success(alreadyRegistered)',
      (tester) async {
        // Wave 3.2 regression guard: the API now emits a structured
        // `Success(alreadyRegistered)` instead of a swallowed
        // ApiException, and the listener must treat it identically to
        // `completed` — call `checkKyc` so the cubit re-fetches the
        // server-side registration state and dispatches the next step.
        whenListen(
          registrationSubmitCubit,
          Stream.fromIterable([
            const KycRegistrationSubmitSuccess(RegistrationStatus.alreadyRegistered),
          ]),
          initialState: KycRegistrationSubmitInitial(),
        );

        await tester.pumpApp(buildSubject(const KycRegistrationView()));
        await tester.pump();

        verify(() => kycCubit.checkKyc()).called(1);
      },
    );

    testWidgets(
      'triggers checkKyc on Success(pendingReview)',
      (tester) async {
        whenListen(
          registrationSubmitCubit,
          Stream.fromIterable([
            const KycRegistrationSubmitSuccess(RegistrationStatus.pendingReview),
          ]),
          initialState: KycRegistrationSubmitInitial(),
        );

        await tester.pumpApp(buildSubject(const KycRegistrationView()));
        await tester.pump();

        verify(() => kycCubit.checkKyc()).called(1);
      },
    );

    testWidgets(
      'shows SnackBar AND triggers checkKyc on Success(forwardingFailed)',
      (tester) async {
        whenListen(
          registrationSubmitCubit,
          Stream.fromIterable([
            const KycRegistrationSubmitSuccess(RegistrationStatus.forwardingFailed),
          ]),
          initialState: KycRegistrationSubmitInitial(),
        );

        await tester.pumpApp(buildSubject(const KycRegistrationView()));
        await tester.pump();

        verify(() => kycCubit.checkKyc()).called(1);
        expect(find.byType(SnackBar), findsOne);
        // The re-arm fires for every success status, not just `completed` —
        // `forwardingFailed` still means the account was accepted.
        verify(() => homeBloc.add(any(that: isA<SyncWalletServicesEvent>()))).called(1);
      },
    );

    testWidgets('shows SnackBar if submitting fails', (tester) async {
      whenListen(
        registrationSubmitCubit,
        Stream.fromIterable([const KycRegistrationSubmitFailure('fail')]),
        initialState: KycRegistrationSubmitInitial(),
      );

      await tester.pumpApp(buildSubject(const KycRegistrationView()));
      await tester.pump();

      expect(find.byType(SnackBar), findsOne);
      expect(find.textContaining('Registration failed'), findsOne);
      // A failed submit must not re-arm the wallet services — the re-arm is
      // gated behind KycRegistrationSubmitSuccess.
      verifyNever(() => homeBloc.add(any(that: isA<SyncWalletServicesEvent>())));
    });

    testWidgets(
      'surfaces the server reason and the nothing-was-saved hint when the '
      'API rejects the submit',
      (tester) async {
        // A structured rejection (e.g. a 400 from register/complete) must not
        // be shown as a raw exception toString: the user needs the server
        // reason plus the context that nothing was persisted — otherwise a
        // rejected submit is indistinguishable from a hang and the re-shown
        // wizard looks like a routing bug.
        whenListen(
          registrationSubmitCubit,
          Stream.fromIterable([
            const KycRegistrationSubmitFailure(
              'RegistrationRejectedException: Registration date must be today '
              '(code: UNKNOWN, statusCode: 400)',
              cause: RegistrationRejectedException(
                statusCode: 400,
                code: 'UNKNOWN',
                message: 'Registration date must be today',
              ),
            ),
          ]),
          initialState: KycRegistrationSubmitInitial(),
        );

        await tester.pumpApp(buildSubject(const KycRegistrationView()));
        await tester.pump();

        expect(find.byType(SnackBar), findsOne);
        expect(find.textContaining('Registration date must be today'), findsOne);
        expect(find.textContaining('Your data has not been saved'), findsOne);
        expect(find.textContaining('RegistrationRejectedException'), findsNothing);
        verifyNever(() => homeBloc.add(any(that: isA<SyncWalletServicesEvent>())));
      },
    );

    testWidgets(
      'keeps the generic failure message for an auth error — a 401 is not a '
      'rejection of the entries',
      (tester) async {
        // The service only types non-auth 4xx of register/complete as
        // RegistrationRejectedException; a persistent 401 (e.g. after the
        // one-shot token-refresh retry) stays a plain ApiException and must
        // not tell the user to check their entries.
        whenListen(
          registrationSubmitCubit,
          Stream.fromIterable([
            const KycRegistrationSubmitFailure(
              'RealUnitApiException: Unauthorized '
              '(code: UNKNOWN, statusCode: 401)',
              cause: ApiException(
                statusCode: 401,
                code: 'UNKNOWN',
                message: 'Unauthorized',
              ),
            ),
          ]),
          initialState: KycRegistrationSubmitInitial(),
        );

        await tester.pumpApp(buildSubject(const KycRegistrationView()));
        await tester.pump();

        expect(find.byType(SnackBar), findsOne);
        expect(find.textContaining('Registration failed'), findsOne);
        expect(find.textContaining('Your data has not been saved'), findsNothing);
        verifyNever(() => homeBloc.add(any(that: isA<SyncWalletServicesEvent>())));
      },
    );

    testWidgets(
      'keeps the generic failure message for a 5xx — no "check your entries" '
      'instruction for a server-side fault',
      (tester) async {
        whenListen(
          registrationSubmitCubit,
          Stream.fromIterable([
            const KycRegistrationSubmitFailure(
              'RealUnitApiException: Internal server error '
              '(code: UNKNOWN, statusCode: 500)',
              cause: ApiException(
                statusCode: 500,
                code: 'UNKNOWN',
                message: 'Internal server error',
              ),
            ),
          ]),
          initialState: KycRegistrationSubmitInitial(),
        );

        await tester.pumpApp(buildSubject(const KycRegistrationView()));
        await tester.pump();

        expect(find.byType(SnackBar), findsOne);
        expect(find.textContaining('Registration failed'), findsOne);
        expect(find.textContaining('Your data has not been saved'), findsNothing);
        verifyNever(() => homeBloc.add(any(that: isA<SyncWalletServicesEvent>())));
      },
    );
  });

  group('$KycRegistrationPage prefill', () {
    testWidgets(
      'seeds the form fields from initialUserData, resolving both countries '
      'through the country service',
      (tester) async {
        await tester.pumpApp(const KycRegistrationPage(initialUserData: _fixtureUserData));
        // Scalars seed synchronously in initState; the two country lookups
        // resolve through the fixture-backed DfxCountryService and setState on
        // completion.
        await tester.pumpAndSettle();

        expect(find.text('Ada'), findsOneWidget);
        expect(find.text('Lovelace'), findsOneWidget);

        // The DTO carries two country symbols ('CH' nationality, 'CH' address).
        // Assert on each dropdown's *selected value*, not a 'Switzerland' text
        // match: a closed DropdownButtonFormField renders every item (Switzerland
        // among them) into an offstage IndexedStack, so find.text('Switzerland')
        // would pass on the mere presence of the item — even if
        // _resolveInitialCountries never resolved anything. The dropdown's
        // initialValue is the resolved Country handed down through the field, so
        // asserting it proves the symbol lookup resolved AND propagated into the
        // form. Scope each query to its step: the PageView keeps the personal
        // step alive while the address step is built, so an unscoped query would
        // match both country dropdowns.
        final natField = tester.widget<DropdownButtonFormField<Country>>(
          find.descendant(
            of: find.byType(KycRegistrationPersonalStep),
            matching: find.byType(DropdownButtonFormField<Country>),
          ),
        );
        expect(natField.initialValue?.id, 41);
        expect(natField.initialValue?.symbol, 'CH');
        expect(natField.initialValue?.name, 'Switzerland');

        // Reveal the address step and confirm its residence field resolved the
        // address country too.
        (tester.widget(find.byType(PageView)) as PageView).controller?.jumpToPage(1);
        await tester.pumpAndSettle();
        final resField = tester.widget<DropdownButtonFormField<Country>>(
          find.descendant(
            of: find.byType(KycRegistrationAddressStep),
            matching: find.byType(DropdownButtonFormField<Country>),
          ),
        );
        expect(resField.initialValue?.id, 41);
        expect(resField.initialValue?.symbol, 'CH');
        expect(resField.initialValue?.name, 'Switzerland');
      },
    );

    testWidgets('degrades gracefully when the country lookup fails', (tester) async {
      // Swap the shared fixture service for one whose HTTP layer always fails,
      // so every country call (the two symbol lookups and each field's own
      // getAllCountries) throws. Restore the fixture for the tests that follow.
      final getIt = GetIt.instance;
      await getIt.unregister<DfxCountryService>();
      getIt.registerSingleton<DfxCountryService>(failingCountryService());
      addTearDown(() async {
        await getIt.unregister<DfxCountryService>();
        getIt.registerSingleton<DfxCountryService>(fixtureCountryService());
      });

      await tester.pumpApp(const KycRegistrationPage(initialUserData: _fixtureUserData));
      await tester.pumpAndSettle();

      // The scalar prefill still applies. The lookup failure is swallowed by
      // _resolveInitialCountries' catch, so it never escapes as an unhandled
      // async error — takeException() stays null. The country field degrades to
      // its load-failed branch instead of crashing.
      expect(find.text('Ada'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(find.text(S.current.countriesLoadFailed), findsWidgets);
    });
  });

  group('$KycRegistrationView page transitions', () {
    testWidgets('animates to the step emitted by the step cubit', (tester) async {
      const personal = KycRegistrationStepState(
        step: KycRegistrationStep.personal,
        steps: [KycRegistrationStep.personal, KycRegistrationStep.address],
      );
      const address = KycRegistrationStepState(
        step: KycRegistrationStep.address,
        steps: [KycRegistrationStep.personal, KycRegistrationStep.address],
      );
      whenListen(
        registrationStepCubit,
        Stream.fromIterable([address]),
        initialState: personal,
      );

      await tester.pumpApp(buildSubject(const KycRegistrationView()));
      // The initState subscription drives _pageController.animateToPage on the
      // emitted step, landing the address page.
      await tester.pumpAndSettle();

      expect(find.byType(KycRegistrationAddressStep).hitTestable(), findsOneWidget);
    });
  });

  group('$KycRegistrationView submit feedback', () {
    testWidgets(
      'shows the signing-cancelled message when the failure cause is a '
      'SigningCancelledException',
      (tester) async {
        whenListen(
          registrationSubmitCubit,
          Stream.fromIterable([
            const KycRegistrationSubmitFailure('cancelled', cause: SigningCancelledException()),
          ]),
          initialState: KycRegistrationSubmitInitial(),
        );

        await tester.pumpApp(buildSubject(const KycRegistrationView()));
        await tester.pump();

        expect(find.byType(SnackBar), findsOne);
        expect(find.textContaining('Signature cancelled'), findsOneWidget);
      },
    );

    testWidgets('shows the loading overlay while a submit is in flight', (tester) async {
      whenListen(
        registrationSubmitCubit,
        Stream.fromIterable([KycRegistrationSubmitLoading()]),
        initialState: KycRegistrationSubmitInitial(),
      );

      await tester.pumpApp(buildSubject(const KycRegistrationView()));
      await tester.pump();

      // Target the overlay specifically: the personal step's CountryField also
      // renders a CupertinoActivityIndicator while its country list loads, so
      // byType alone is not unique. The overlay is the white Container layered
      // over the PageView (kyc_registration_page.dart:229-234).
      final overlay = find.byWidgetPredicate(
        (w) => w is Container && w.color == RealUnitColors.basic.white,
      );
      expect(
        find.descendant(of: overlay, matching: find.byType(CupertinoActivityIndicator)),
        findsOneWidget,
      );
    });
  });

  group('$KycRegistrationView BitBox submit', () {
    testWidgets(
      'opens the ConnectBitbox sheet and retries submit once pairing finishes',
      (tester) async {
        when(() => registrationSubmitCubit.retrySubmit(any())).thenAnswer((_) async {});
        whenListen(
          registrationSubmitCubit,
          Stream.fromIterable([
            const KycRegistrationSubmitBitboxRequired(registration: _registrationFixture),
          ]),
          initialState: KycRegistrationSubmitInitial(),
        );

        // The sheet callback calls context.pop(true); that needs a GoRouter in
        // scope, which pumpApp's MaterialApp.home does not provide.
        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => buildSubject(const KycRegistrationView()),
            ),
          ],
        );
        addTearDown(router.dispose);

        await tester.pumpWidget(
          MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: const [
              S.delegate,
              GlobalMaterialLocalizations.delegate,
            ],
            supportedLocales: S.delegate.supportedLocales,
          ),
        );
        // Let the BlocListener open the modal bottom sheet and settle it in.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Drive the sheet's onFinish exactly as ConnectBitboxView would on a
        // successful pairing, without exercising the pairing ceremony itself.
        final page = tester.widget<ConnectBitboxPage>(find.byType(ConnectBitboxPage));
        page.onFinish(MockAWallet());
        await tester.pump();
        // Let the popped sheet's future resolve and the route tear down (which
        // closes the real ConnectBitboxCubit and cancels its scan timer).
        await tester.pump(const Duration(milliseconds: 500));

        verify(() => homeBloc.add(any(that: isA<SyncWalletServicesEvent>()))).called(1);
        verify(() => registrationSubmitCubit.retrySubmit(_registrationFixture)).called(1);
      },
    );
  });

  // End-to-end wiring of the tax-residence branch: navigating to the final tax
  // step, picking a tax-residence country and submitting must forward the
  // derived `swissTaxResidence` + `countryAndTINs` into the submit cubit.
  // Covers both arms of `_onSubmit` on the page.
  group('$KycRegistrationView tax residence submit wiring', () {
    const initialUserData = RealUnitUserDataDto(
      email: 'a@b.com',
      name: 'Ada Lovelace',
      type: 'HUMAN',
      phoneNumber: '+41 79 000 00 00',
      birthday: '1815-12-10',
      nationality: 'CH',
      addressStreet: 'Bahnhofstrasse 1',
      addressPostalCode: '8000',
      addressCity: 'Zurich',
      addressCountry: 'CH',
      swissTaxResidence: true,
      lang: 'de',
      kycData: KycPersonalData(
        accountType: KycAccountType.personal,
        firstName: 'Ada',
        lastName: 'Lovelace',
        phone: '+41 79 000 00 00',
        address: KycAddress(
          street: 'Bahnhofstrasse',
          houseNumber: '1',
          zip: '8000',
          city: 'Zurich',
          country: 41,
        ),
      ),
    );

    // Same person but tax-resident abroad: nationality CH, residence DE. Proves
    // the tax residence defaults from the ADDRESS country (not the nationality)
    // and exercises the non-Swiss prefill end-to-end.
    const initialUserDataDe = RealUnitUserDataDto(
      email: 'a@b.com',
      name: 'Ada Lovelace',
      type: 'HUMAN',
      phoneNumber: '+41 79 000 00 00',
      birthday: '1815-12-10',
      nationality: 'CH',
      addressStreet: 'Bahnhofstrasse 1',
      addressPostalCode: '8000',
      addressCity: 'Berlin',
      addressCountry: 'DE',
      swissTaxResidence: false,
      lang: 'de',
      kycData: KycPersonalData(
        accountType: KycAccountType.personal,
        firstName: 'Ada',
        lastName: 'Lovelace',
        phone: '+41 79 000 00 00',
        address: KycAddress(
          street: 'Bahnhofstrasse',
          houseNumber: '1',
          zip: '8000',
          city: 'Berlin',
          country: 55,
        ),
      ),
    );

    setUp(() {
      // Land the pager on the final tax-residence step so its country picker is
      // in view once we jump the PageView to it.
      when(() => registrationStepCubit.state).thenReturn(
        const KycRegistrationStepState(
          step: KycRegistrationStep.taxResidence,
          steps: [
            KycRegistrationStep.personal,
            KycRegistrationStep.address,
            KycRegistrationStep.taxResidence,
          ],
        ),
      );

      when(
        () => registrationSubmitCubit.submit(
          type: any(named: 'type'),
          firstName: any(named: 'firstName'),
          lastName: any(named: 'lastName'),
          phoneNumber: any(named: 'phoneNumber'),
          birthday: any(named: 'birthday'),
          nationality: any(named: 'nationality'),
          addressStreet: any(named: 'addressStreet'),
          addressStreetNumber: any(named: 'addressStreetNumber'),
          addressPostalCode: any(named: 'addressPostalCode'),
          addressCity: any(named: 'addressCity'),
          addressCountry: any(named: 'addressCountry'),
          swissTaxResidence: any(named: 'swissTaxResidence'),
          countryAndTINs: any(named: 'countryAndTINs'),
        ),
      ).thenAnswer((_) async {});
    });

    Finder taxScrollable() => find
        .descendant(
          of: find.byType(KycRegistrationTaxStep),
          matching: find.byType(Scrollable),
        )
        .first;

    Future<void> showTaxStep(
      WidgetTester tester, {
      RealUnitUserDataDto dto = initialUserData,
    }) async {
      await tester.pumpApp(
        buildSubject(KycRegistrationView(initialUserData: dto)),
      );
      // Let the seeded country lookups resolve before we jump to the tax page.
      await tester.pumpAndSettle();

      final index = registrationStepCubit.state.index;
      (tester.widget(find.byType(PageView)) as PageView).controller?.jumpToPage(index);
      await tester.pumpAndSettle();
    }

    Future<void> tapComplete(WidgetTester tester) async {
      final completeButton = find.descendant(
        of: find.byType(KycRegistrationTaxStep),
        matching: find.byType(AppFilledButton),
      );
      await tester.scrollUntilVisible(
        completeButton,
        100,
        scrollable: taxScrollable(),
      );
      await tester.tap(completeButton);
      await tester.pumpAndSettle();
    }

    List<dynamic> captureSubmit() => verify(
      () => registrationSubmitCubit.submit(
        type: any(named: 'type'),
        firstName: any(named: 'firstName'),
        lastName: any(named: 'lastName'),
        phoneNumber: any(named: 'phoneNumber'),
        birthday: any(named: 'birthday'),
        nationality: any(named: 'nationality'),
        addressStreet: any(named: 'addressStreet'),
        addressStreetNumber: any(named: 'addressStreetNumber'),
        addressPostalCode: any(named: 'addressPostalCode'),
        addressCity: any(named: 'addressCity'),
        addressCountry: captureAny(named: 'addressCountry'),
        swissTaxResidence: captureAny(named: 'swissTaxResidence'),
        countryAndTINs: captureAny(named: 'countryAndTINs'),
      ),
    ).captured;

    Future<void> enterTinAt(WidgetTester tester, int index, String value) async {
      final context = tester.element(find.byType(KycRegistrationTaxStep));
      final tinFields = find.widgetWithText(TextFormField, S.of(context).tinHint);
      final field = tinFields.at(index);
      await tester.scrollUntilVisible(field, 100, scrollable: taxScrollable());
      await tester.enterText(field, value);
      await tester.pump();
    }

    Future<void> addTaxResidence(WidgetTester tester) async {
      final context = tester.element(find.byType(KycRegistrationTaxStep));
      final addButton = find.text(S.of(context).addTaxResidence);
      await tester.scrollUntilVisible(addButton, 100, scrollable: taxScrollable());
      await tester.tap(addButton);
      await tester.pumpAndSettle();
    }

    Future<void> selectFreeCountry(WidgetTester tester, String name) async {
      final taxDropdown = find
          .descendant(
            of: find.byType(KycRegistrationTaxStep),
            matching: find.byType(DropdownButtonFormField<Country>),
          )
          .last;
      await tester.scrollUntilVisible(taxDropdown, 100, scrollable: taxScrollable());
      await tester.tap(taxDropdown);
      await tester.pumpAndSettle();

      final nameFinder = find.text(name);
      if (nameFinder.evaluate().isEmpty || find.text(name).hitTestable().evaluate().isEmpty) {
        await tester.dragUntilVisible(
          nameFinder,
          find.byType(Scrollable).last,
          const Offset(0, -300),
          maxIteration: 120,
        );
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text(name).last);
      await tester.pumpAndSettle();
    }

    // S1 — Address CH, tax: CH only → swiss=true, countryAndTINs=null
    testWidgets(
      'S1 CH only: locked Swiss address → swissTaxResidence true, null countryAndTINs',
      (tester) async {
        await showTaxStep(tester);

        await tapComplete(tester);

        final captured = captureSubmit();
        expect(captured[0], isA<Country>().having((c) => c.symbol, 'symbol', 'CH'));
        expect(captured[1], isTrue);
        expect(captured[2], isNull);
      },
    );

    // S2 — Address DE, tax: DE only → swiss=false, countryAndTINs=[{DE,tin}]
    testWidgets(
      'S2 DE only: locked German address requires TIN and forwards countryAndTINs:DE',
      (tester) async {
        await showTaxStep(tester, dto: initialUserDataDe);

        // Enter with surrounding whitespace: the tax step trims before
        // forwarding, so the captured TIN is the trimmed value.
        await enterTinAt(tester, 0, '  12 345 678 901  ');
        await tapComplete(tester);

        final captured = captureSubmit();
        expect(captured[0], isA<Country>().having((c) => c.symbol, 'symbol', 'DE'));
        expect(captured[1], isFalse);
        final tins = captured[2] as List<CountryAndTin>;
        expect(tins, hasLength(1));
        expect(tins.single.country, 'DE');
        expect(tins.single.tin, '12 345 678 901');
      },
    );

    // S3 — Address CH, tax: CH + FR → swiss=true, countryAndTINs=[{FR,tin}]
    testWidgets(
      'S3 CH + FR: locked Swiss + free France → swiss true, countryAndTINs FR only',
      (tester) async {
        await showTaxStep(tester);

        await addTaxResidence(tester);
        await selectFreeCountry(tester, 'France');
        await enterTinAt(tester, 0, 'FR999');
        await tapComplete(tester);

        final captured = captureSubmit();
        expect(captured[0], isA<Country>().having((c) => c.symbol, 'symbol', 'CH'));
        expect(captured[1], isTrue);
        final tins = captured[2] as List<CountryAndTin>;
        expect(tins, hasLength(1));
        expect(tins.single.country, 'FR');
        expect(tins.single.tin, 'FR999');
      },
    );

    // S4 — Address DE, tax: DE + CH → swiss=true, countryAndTINs=[{DE,tin}]
    testWidgets(
      'S4 DE + CH: locked DE + free CH → swiss true, countryAndTINs DE only',
      (tester) async {
        await showTaxStep(tester, dto: initialUserDataDe);

        await enterTinAt(tester, 0, 'DE111');
        await addTaxResidence(tester);
        await selectFreeCountry(tester, 'Switzerland');
        await tapComplete(tester);

        final captured = captureSubmit();
        // DE (address, with TIN) + CH (additional) → swissTaxResidence true,
        // countryAndTINs only carries the non-CH entry.
        expect(captured[0], isA<Country>().having((c) => c.symbol, 'symbol', 'DE'));
        expect(captured[1], isTrue);
        final tins = captured[2] as List<CountryAndTin>;
        expect(tins, hasLength(1));
        expect(tins.single.country, 'DE');
        expect(tins.single.tin, 'DE111');
      },
    );

    // S5 — Address DE, tax: DE + FR + US → swiss=false, three TINs
    testWidgets(
      'S5 DE + FR + US: multi non-CH residences forward all countryAndTINs',
      (tester) async {
        await showTaxStep(tester, dto: initialUserDataDe);

        await enterTinAt(tester, 0, 'DE111');
        await addTaxResidence(tester);
        await selectFreeCountry(tester, 'France');
        await enterTinAt(tester, 1, 'FR999');
        await addTaxResidence(tester);
        await selectFreeCountry(tester, 'United States');
        await enterTinAt(tester, 2, 'US123');
        await tapComplete(tester);

        final captured = captureSubmit();
        expect(captured[0], isA<Country>().having((c) => c.symbol, 'symbol', 'DE'));
        expect(captured[1], isFalse);
        final tins = captured[2] as List<CountryAndTin>;
        expect(tins, hasLength(3));
        expect(tins[0].country, 'DE');
        expect(tins[0].tin, 'DE111');
        expect(tins[1].country, 'FR');
        expect(tins[1].tin, 'FR999');
        expect(tins[2].country, 'US');
        expect(tins[2].tin, 'US123');
      },
    );

    // Prefill wiring: swissTaxResidence + countryAndTINs from initialUserData
    // must seed the tax step and round-trip on submit (no silent drop).
    testWidgets(
      'prefills CH + DE tax residences from initialUserData and submits both',
      (tester) async {
        const prefillWithForeignTin = RealUnitUserDataDto(
          email: 'a@b.com',
          name: 'Ada Lovelace',
          type: 'HUMAN',
          phoneNumber: '+41 79 000 00 00',
          birthday: '1815-12-10',
          nationality: 'CH',
          addressStreet: 'Bahnhofstrasse 1',
          addressPostalCode: '8000',
          addressCity: 'Zurich',
          addressCountry: 'CH',
          swissTaxResidence: true,
          countryAndTINs: [CountryAndTin(country: 'DE', tin: 'DE123')],
          lang: 'de',
          kycData: KycPersonalData(
            accountType: KycAccountType.personal,
            firstName: 'Ada',
            lastName: 'Lovelace',
            phone: '+41 79 000 00 00',
            address: KycAddress(
              street: 'Bahnhofstrasse',
              houseNumber: '1',
              zip: '8000',
              city: 'Zurich',
              country: 41,
            ),
          ),
        );

        await showTaxStep(tester, dto: prefillWithForeignTin);

        // Seeds resolved: CH (from swissTaxResidence) + DE (from countryAndTINs).
        expect(find.text('Switzerland'), findsWidgets);
        expect(find.text('Germany'), findsWidgets);
        final context = tester.element(find.byType(KycRegistrationTaxStep));
        final tinField = find.widgetWithText(TextFormField, S.of(context).tinHint);
        expect(tinField, findsOneWidget);
        expect(tester.widget<TextFormField>(tinField).controller!.text, 'DE123');

        await tapComplete(tester);

        final captured = captureSubmit();
        expect(captured[0], isA<Country>().having((c) => c.symbol, 'symbol', 'CH'));
        expect(captured[1], isTrue);
        final tins = captured[2] as List<CountryAndTin>;
        expect(tins, hasLength(1));
        expect(tins.single.country, 'DE');
        expect(tins.single.tin, 'DE123');
      },
    );
  });
}
