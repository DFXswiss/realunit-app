import 'package:bitbox_flutter/bitbox_flutter.dart' as sdk;
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/hardware_wallet/bitbox.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_country_service.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_kyc_service.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/registration_rejected_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/models/country/country.dart';
import 'package:realunit_wallet/packages/service/dfx/models/registration/kyc/kyc_personal_data.dart';
import 'package:realunit_wallet/packages/service/dfx/models/registration/registration.dart';
import 'package:realunit_wallet/packages/service/dfx/models/registration/registration_status.dart';
import 'package:realunit_wallet/packages/service/dfx/models/registration/registration_user_type.dart';
import 'package:realunit_wallet/packages/service/dfx/models/user/dto/real_unit_user_data_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_registration_service.dart';
import 'package:realunit_wallet/packages/service/wallet_service.dart';
import 'package:realunit_wallet/packages/wallet/exceptions/signing_cancelled_exception.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';
import 'package:realunit_wallet/screens/home/bloc/home_bloc.dart';
import 'package:realunit_wallet/screens/kyc/cubits/kyc/kyc_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/registration/cubits/registration_step/kyc_registration_step_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/registration/cubits/registration_submit/kyc_registration_submit_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/registration/kyc_registration_page.dart';

import '../../../helper/helper.dart';

class _MockRegistrationStepCubit extends MockCubit<KycRegistrationStepState>
    implements KycRegistrationStepCubit {}

class _MockRegistrationSubmitCubit extends MockCubit<KycRegistrationSubmitState>
    implements KycRegistrationSubmitCubit {}

class _MockKycCubit extends MockCubit<KycState> implements KycCubit {}

class _MockHomeBloc extends MockBloc<HomeEvent, HomeState> implements HomeBloc {}

class _MockAppStore extends Mock implements AppStore {}

class _MockRealUnitRegistrationService extends Mock
    implements RealUnitRegistrationService {}

class _MockDfxKycService extends Mock implements DfxKycService {}

class _MockWalletService extends Mock implements WalletService {}

class _MockBitboxService extends Mock implements BitboxService {}

class _MockAWallet extends Mock implements AWallet {}

const _country = Country(id: 41, symbol: 'CH', name: 'Switzerland', kycAllowed: true);

// Mirrors the placeholder fixture from
// test/screens/kyc/steps/kyc_registration_page_test.dart (Ada Lovelace, never
// customer data), but with the birthday year bumped to 1990: unlike that widget
// test, this golden actually renders the birthday dropdowns, whose year list is
// only `now().year … now().year-140` (birthday_field.dart). Ada's historical 1815
// falls outside that window and would render an empty year field; 1990 sits inside
// it for any plausible run date, so the closed dropdown shows the static selected
// value (not the `now()`-derived list) and the render stays byte-stable.
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
  birthday: '1990-12-10',
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
  birthday: '1990-12-10',
  nationality: _country,
  addressStreet: 'S',
  addressStreetNumber: '1',
  addressPostalCode: '8000',
  addressCity: 'Zurich',
  addressCountry: _country,
  swissTaxResidence: true,
);

void main() {
  late _MockRegistrationStepCubit registrationStepCubit;
  late _MockRegistrationSubmitCubit registrationSubmitCubit;
  late _MockKycCubit kycCubit;
  late _MockHomeBloc homeBloc;

  const personalState = KycRegistrationStepState(
    step: KycRegistrationStep.personal,
    steps: [
      KycRegistrationStep.personal,
      KycRegistrationStep.address,
      KycRegistrationStep.taxResidence,
    ],
  );

  const addressState = KycRegistrationStepState(
    step: KycRegistrationStep.address,
    steps: [
      KycRegistrationStep.personal,
      KycRegistrationStep.address,
      KycRegistrationStep.taxResidence,
    ],
  );

  const taxState = KycRegistrationStepState(
    step: KycRegistrationStep.taxResidence,
    steps: [
      KycRegistrationStep.personal,
      KycRegistrationStep.address,
      KycRegistrationStep.taxResidence,
    ],
  );

  setUp(() {
    registrationStepCubit = _MockRegistrationStepCubit();
    registrationSubmitCubit = _MockRegistrationSubmitCubit();
    kycCubit = _MockKycCubit();
    homeBloc = _MockHomeBloc();

    when(() => registrationStepCubit.state).thenReturn(personalState);
    when(() => registrationSubmitCubit.state)
        .thenReturn(KycRegistrationSubmitInitial());
    when(() => kycCubit.state).thenReturn(const KycInitial());
    when(() => kycCubit.checkKyc()).thenAnswer((_) => Future.value());
  });

  // Full DI so every state renders: the prefill state constructs a real
  // `KycRegistrationPage` (which looks up the registration/country/kyc services
  // via getIt), and the BitBox-required state opens the real `ConnectBitboxPage`
  // (which resolves a Bitbox/Wallet service on build). The country service is the
  // fixture-backed real service so the citizenship/residence dropdowns populate.
  setUpAll(() {
    final getIt = GetIt.instance;
    getIt.registerSingleton<RealUnitRegistrationService>(
      _MockRealUnitRegistrationService(),
    );
    getIt.registerSingleton<DfxCountryService>(fixtureCountryService());
    getIt.registerSingleton<DfxKycService>(_MockDfxKycService());
    final appStore = _MockAppStore();
    when(() => appStore.wallet).thenReturn(_MockAWallet());
    getIt.registerSingleton<AppStore>(appStore);
    final bitboxService = _MockBitboxService();
    when(() => bitboxService.startScan()).thenAnswer((_) async => false);
    when(() => bitboxService.getAllUsbDevices())
        .thenAnswer((_) async => <sdk.BitboxDevice>[]);
    getIt.registerSingleton<BitboxService>(bitboxService);
    getIt.registerSingleton<WalletService>(_MockWalletService());
  });

  tearDownAll(() async => GetIt.instance.reset());

  Widget buildView(Widget child) => wrapForGolden(
        MultiBlocProvider(
          providers: [
            BlocProvider<KycCubit>.value(value: kycCubit),
            BlocProvider<KycRegistrationStepCubit>.value(
              value: registrationStepCubit,
            ),
            BlocProvider<KycRegistrationSubmitCubit>.value(
              value: registrationSubmitCubit,
            ),
            BlocProvider<HomeBloc>.value(value: homeBloc),
          ],
          child: child,
        ),
      );

  // Land the PageView on the step the (mocked) step cubit reports. The mocked
  // cubit emits nothing, so `initState`'s stream subscription never animates the
  // pager — jumping it here is the seam the widget test uses too
  // (kyc_registration_page_test.dart:208).
  Future<void> jumpToActiveStep(WidgetTester tester) async {
    await tester.pumpAndSettle();
    (tester.widget(find.byType(PageView)) as PageView)
        .controller
        ?.jumpToPage(registrationStepCubit.state.index);
    await tester.pumpAndSettle();
  }

  group('$KycRegistrationView', () {
    goldenTest(
      'address step active — AppBar "Residence", pager on page 2',
      fileName: 'kyc_registration_page_address_step',
      constraints: phoneConstraints,
      pumpBeforeTest: jumpToActiveStep,
      builder: () {
        when(() => registrationStepCubit.state).thenReturn(addressState);
        return buildView(const KycRegistrationView());
      },
    );

    goldenTest(
      'tax residence step active — AppBar "Tax residence", pager on page 3',
      fileName: 'kyc_registration_page_tax_step',
      constraints: phoneConstraints,
      pumpBeforeTest: jumpToActiveStep,
      builder: () {
        when(() => registrationStepCubit.state).thenReturn(taxState);
        return buildView(const KycRegistrationView());
      },
    );

    goldenTest(
      'prefilled form — initialUserData seeds the personal step',
      fileName: 'kyc_registration_page_prefilled',
      constraints: phoneConstraints,
      // Real `KycRegistrationPage`: the scalar fields seed synchronously in
      // initState and the two country symbols resolve through the
      // fixture-backed DfxCountryService; the default `precacheImages`
      // pump-and-settle lets both country lookups complete before capture.
      builder: () => wrapForGolden(
        const KycRegistrationPage(initialUserData: _fixtureUserData),
      ),
    );

    goldenTest(
      'submit loading overlay — white full-bleed overlay + spinner over the pager',
      fileName: 'kyc_registration_page_submit_loading',
      constraints: phoneConstraints,
      // CupertinoActivityIndicator animates indefinitely; a single pump captures
      // the overlay at its first frame (pumpAndSettle would time out).
      pumpBeforeTest: pumpOnce,
      builder: () {
        when(() => registrationSubmitCubit.state)
            .thenReturn(KycRegistrationSubmitLoading());
        return buildView(const KycRegistrationView());
      },
    );

    goldenTest(
      'submit failure SnackBar — signingCancelled (red)',
      fileName: 'kyc_registration_page_submit_failure_snackbar',
      constraints: phoneConstraints,
      pumpBeforeTest: (tester) async {
        await tester.pump(); // deliver the whenListen emission to the listener
        await tester.pumpAndSettle(); // run the SnackBar entrance to completion
      },
      builder: () {
        whenListen(
          registrationSubmitCubit,
          Stream.fromIterable([
            const KycRegistrationSubmitFailure(
              'registration rejected',
              cause: SigningCancelledException(),
            ),
          ]),
          initialState: KycRegistrationSubmitInitial(),
        );
        return buildView(const KycRegistrationView());
      },
    );

    goldenTest(
      'submit rejected SnackBar — structured 4xx with server reason',
      fileName: 'kyc_registration_page_submit_rejected_snackbar',
      constraints: phoneConstraints,
      pumpBeforeTest: (tester) async {
        await tester.pump(); // deliver the whenListen emission to the listener
        await tester.pumpAndSettle(); // run the SnackBar entrance to completion
      },
      builder: () {
        whenListen(
          registrationSubmitCubit,
          Stream.fromIterable([
            const KycRegistrationSubmitFailure(
              'registration rejected',
              cause: RegistrationRejectedException(
                statusCode: 400,
                code: 'UNKNOWN',
                message: 'Registration date must be today',
              ),
            ),
          ]),
          initialState: KycRegistrationSubmitInitial(),
        );
        return buildView(const KycRegistrationView());
      },
    );

    goldenTest(
      'forwarding-failed SnackBar — shown after a successful submit',
      fileName: 'kyc_registration_page_forwarding_failed_snackbar',
      constraints: phoneConstraints,
      pumpBeforeTest: (tester) async {
        await tester.pump(); // deliver the Success(forwardingFailed) emission
        await tester.pumpAndSettle(); // run the SnackBar entrance to completion
      },
      builder: () {
        whenListen(
          registrationSubmitCubit,
          Stream.fromIterable([
            const KycRegistrationSubmitSuccess(RegistrationStatus.forwardingFailed),
          ]),
          initialState: KycRegistrationSubmitInitial(),
        );
        return buildView(const KycRegistrationView());
      },
    );

    goldenTest(
      'BitBox-required — the modal ConnectBitbox sheet opened over the pager',
      fileName: 'kyc_registration_page_bitbox_required',
      constraints: phoneConstraints,
      // The BitboxRequired emission drives the listener's showModalBottomSheet;
      // pumpAndSettle opens the sheet and loads its SVG. The real
      // ConnectBitboxCubit stays in BitboxNotConnected because getAllUsbDevices
      // is stubbed empty, so the rendered pixels are stable across regens.
      pumpBeforeTest: (tester) async {
        await tester.pump(); // deliver the BitboxRequired emission
        await tester.pumpAndSettle(); // open + settle the modal sheet
      },
      builder: () {
        whenListen(
          registrationSubmitCubit,
          Stream.fromIterable([
            const KycRegistrationSubmitBitboxRequired(
              registration: _registrationFixture,
            ),
          ]),
          initialState: KycRegistrationSubmitInitial(),
        );
        return buildView(const KycRegistrationView());
      },
    );
  });
}
