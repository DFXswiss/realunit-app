import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_country_service.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_kyc_service.dart';
import 'package:realunit_wallet/packages/service/dfx/models/country/country.dart';
import 'package:realunit_wallet/packages/service/dfx/models/registration/kyc/kyc_personal_data.dart';
import 'package:realunit_wallet/packages/service/dfx/models/user/dto/real_unit_user_data_dto.dart';
import 'package:realunit_wallet/screens/kyc/subpages/kyc_unsupported_step_page.dart';
import 'package:realunit_wallet/screens/kyc/cubits/kyc/kyc_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/personal_data/cubit/kyc_personal_data/kyc_personal_data_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/personal_data/kyc_personal_data_page.dart';
import 'package:realunit_wallet/widgets/form/country_field.dart';
import 'package:realunit_wallet/widgets/form/labeled_text_field.dart';
import 'package:realunit_wallet/widgets/form/phone_number_field.dart';

import '../../../helper/country_fixture.dart';
import '../../../helper/pump_app.dart';

class MockKycPersonalDataCubit extends MockCubit<KycPersonalDataState>
    implements KycPersonalDataCubit {}

class MockKycCubit extends MockCubit<KycState> implements KycCubit {}

class MockDfxKycService extends Mock implements DfxKycService {}

void main() {
  late KycPersonalDataCubit personalDataCubit;
  late KycCubit kycCubit;
  const url = 'https://example.com/kyc/data/personal/1';

  RealUnitUserDataDto userDataDto({
    KycAccountType accountType = KycAccountType.personal,
    String phone = '+41790000000',
  }) => RealUnitUserDataDto(
        email: 'erika@example.com',
        name: 'Erika Mueller',
        type: 'HUMAN',
        phoneNumber: phone,
        birthday: '1990-01-01',
        nationality: 'CH',
        addressStreet: 'Bahnhofstrasse 1',
        addressPostalCode: '8001',
        addressCity: 'Winterthur',
        addressCountry: 'CH',
        swissTaxResidence: true,
        lang: 'EN',
        kycData: KycPersonalData(
          accountType: accountType,
          firstName: 'Erika',
          lastName: 'Mueller',
          phone: phone,
          address: const KycAddress(
            street: 'Bahnhofstrasse',
            houseNumber: '1',
            zip: '8001',
            city: 'Winterthur',
            country: 41,
          ),
        ),
      );

  setUp(() {
    personalDataCubit = MockKycPersonalDataCubit();
    kycCubit = MockKycCubit();

    when(() => personalDataCubit.state).thenReturn(const KycPersonalDataInitial());
    when(() => personalDataCubit.stream).thenAnswer((_) => const Stream.empty());
    when(() => kycCubit.state).thenReturn(const KycInitial());
    when(() => kycCubit.checkKyc()).thenAnswer((_) => Future.value());
  });

  void setupDependencyInjection() {
    final getIt = GetIt.instance;
    getIt.registerSingleton<DfxKycService>(MockDfxKycService());
    getIt.registerSingleton<DfxCountryService>(fixtureCountryService());
  }

  setUpAll(() {
    setupDependencyInjection();
    registerFallbackValue(
      const Country(id: 41, symbol: 'CH', name: 'Switzerland', kycAllowed: true),
    );
    registerFallbackValue(KycAccountType.personal);
  });

  tearDownAll(() async => await GetIt.instance.reset());

  Widget buildSubject(Widget child) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: personalDataCubit),
        BlocProvider.value(value: kycCubit),
      ],
      child: child,
    );
  }

  group('$KycPersonalDataPage', () {
    testWidgets('renders $KycPersonalDataView', (tester) async {
      await tester.pumpApp(KycPersonalDataPage(url: url, initialUserData: userDataDto()));

      expect(find.byType(KycPersonalDataView), findsOne);
    });
  });

  group('$KycPersonalDataPage account-type guard', () {
    // Submitting this form sets `accountType` on the account, and the API nulls every organization
    // field whenever that value is Personal — so offering the form to a non-personal account would
    // destroy its organization data and drop the org-only steps from its required set.
    for (final type in [KycAccountType.organization, KycAccountType.soleProprietorship]) {
      testWidgets('refuses the form for a $type account', (tester) async {
        await tester.pumpApp(
          KycPersonalDataPage(url: url, initialUserData: userDataDto(accountType: type)),
        );

        expect(find.byType(KycPersonalDataView), findsNothing);
        expect(find.byType(KycUnsupportedStepPage), findsOne);
      });
    }

    // A missing payload is transient (the registration row has no signed payload yet), so it gets
    // its own refresh surface rather than the shared handoff an unsupported account type gets.
    testWidgets('offers a retry, not a dead end, when the payload is missing', (tester) async {
      await tester.pumpApp(
        BlocProvider<KycCubit>.value(
          value: kycCubit,
          child: const KycPersonalDataPage(url: url),
        ),
      );

      expect(find.byType(KycPersonalDataView), findsNothing);
      expect(find.byType(KycUnsupportedStepPage), findsNothing);

      await tester.tap(find.byType(FilledButton));
      await tester.pump();

      verify(() => kycCubit.checkKyc()).called(1);
    });
  });

  group('$KycPersonalDataView', () {
    testWidgets('renders every field the personal-data step submits', (tester) async {
      await tester.pumpApp(buildSubject(KycPersonalDataView(url: url, initialUserData: userDataDto())));

      // six placed directly (first/last name, street, house number, postcode, city) plus the one
      // PhoneNumberField nests for the number input
      expect(find.byType(LabeledTextField), findsNWidgets(7));
      expect(find.byType(PhoneNumberField), findsOne);
      expect(find.byType(CountryField), findsOne);
      expect(find.byType(FilledButton), findsOne);
    });

    // The copy asks the user to check their details and every submit rewrites all of them, so an
    // empty form would force a from-memory re-entry and let a typo overwrite correct data.
    testWidgets('seeds the form from the registration payload', (tester) async {
      await tester.pumpApp(
        buildSubject(KycPersonalDataView(url: url, initialUserData: userDataDto())),
      );
      await tester.pumpAndSettle();

      expect(find.text('Erika'), findsOne);
      expect(find.text('Mueller'), findsOne);
      expect(find.text('Bahnhofstrasse'), findsOne);
      expect(find.text('8001'), findsOne);
      expect(find.text('Winterthur'), findsOne);
    });

    // A stored number with a dial code the field does not offer must still leave an editable field:
    // PhoneNumberField falls back to its first prefix rather than leaving `prefix` null, which would
    // render a blank dropdown and make it silently drop every edit the user makes.
    testWidgets('stays editable when the stored phone has an unsupported prefix', (tester) async {
      final dto = userDataDto(phone: '+33612345678');
      await tester.pumpApp(buildSubject(KycPersonalDataView(url: url, initialUserData: dto)));
      await tester.pumpAndSettle();

      expect(find.text('+41'), findsOne);
    });

    // The country lookup is fire-and-forget; without a catch a failing GET escapes as an uncaught
    // async error instead of degrading to an empty picker.
    testWidgets('survives a failing country lookup', (tester) async {
      final getIt = GetIt.instance;
      await getIt.reset();
      getIt.registerSingleton<DfxKycService>(MockDfxKycService());
      getIt.registerSingleton<DfxCountryService>(failingCountryService());
      addTearDown(() async {
        await getIt.reset();
        setupDependencyInjection();
      });

      await tester.pumpApp(
        buildSubject(KycPersonalDataView(url: url, initialUserData: userDataDto())),
      );
      await tester.pumpAndSettle();

      // the rest of the form still rendered
      expect(find.text('Erika'), findsOne);
    });

    // Two independent country lookups race — this page's and CountryField's own. If this one is the
    // slower, it must not overwrite a country the user has already chosen in the meantime.
    testWidgets('does not overwrite a country the user already picked', (tester) async {
      final gate = Completer<void>();
      var served = 0;
      final getIt = GetIt.instance;
      await getIt.reset();
      getIt.registerSingleton<DfxKycService>(MockDfxKycService());
      getIt.registerSingleton<DfxCountryService>(
        countryServiceWithClient(
          MockClient((_) async {
            // hold only the first caller (this page); let CountryField's own load through
            if (served++ == 0) await gate.future;
            return countriesFixtureResponse();
          }),
        ),
      );
      addTearDown(() async {
        await getIt.reset();
        setupDependencyInjection();
      });

      await tester.pumpApp(
        buildSubject(KycPersonalDataView(url: url, initialUserData: userDataDto())),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(CountryField));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Germany').last);
      await tester.pumpAndSettle();

      gate.complete();
      await tester.pumpAndSettle();

      expect(find.text('Germany'), findsOne);
      expect(find.text('Switzerland'), findsNothing);
    });

    // Pins the url plumbing: the step's session url is what the submit PUTs to.
    testWidgets('submits the seeded values to the step url', (tester) async {
      when(() => personalDataCubit.submit(
        url: any(named: 'url'),
        accountType: any(named: 'accountType'),
        firstName: any(named: 'firstName'),
        lastName: any(named: 'lastName'),
        phone: any(named: 'phone'),
        street: any(named: 'street'),
        houseNumber: any(named: 'houseNumber'),
        zip: any(named: 'zip'),
        city: any(named: 'city'),
        country: any(named: 'country'),
      )).thenAnswer((_) async {});

      await tester.pumpApp(
        buildSubject(KycPersonalDataView(url: url, initialUserData: userDataDto())),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byType(FilledButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton));
      await tester.pump();

      verify(() => personalDataCubit.submit(
        url: url,
        accountType: KycAccountType.personal,
        firstName: 'Erika',
        lastName: 'Mueller',
        phone: '+41790000000',
        street: 'Bahnhofstrasse',
        houseNumber: '1',
        zip: '8001',
        city: 'Winterthur',
        country: any(named: 'country'),
      )).called(1);
    });

    // The step exists so a rejected account can correct its data; submitting an empty form must
    // surface the validation errors rather than PUT an incomplete body.
    testWidgets('does not submit while a required field is empty', (tester) async {
      await tester.pumpApp(
        buildSubject(KycPersonalDataView(url: url, initialUserData: userDataDto())),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(LabeledTextField, 'Erika'), '');
      await tester.ensureVisible(find.byType(FilledButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton));
      await tester.pump();

      verifyNever(() => personalDataCubit.submit(
        url: any(named: 'url'),
        accountType: any(named: 'accountType'),
        firstName: any(named: 'firstName'),
        lastName: any(named: 'lastName'),
        phone: any(named: 'phone'),
        street: any(named: 'street'),
        houseNumber: any(named: 'houseNumber'),
        zip: any(named: 'zip'),
        city: any(named: 'city'),
        country: any(named: 'country'),
      ));
    });
  });

  group('$BlocListener', () {
    testWidgets('triggers checkKyc when the submit succeeds', (tester) async {
      whenListen(
        personalDataCubit,
        Stream.fromIterable([const KycPersonalDataSuccess()]),
        initialState: const KycPersonalDataInitial(),
      );

      await tester.pumpApp(buildSubject(KycPersonalDataView(url: url, initialUserData: userDataDto())));
      await tester.pump();

      verify(() => kycCubit.checkKyc()).called(1);
    });

    testWidgets('shows a SnackBar when the submit fails', (tester) async {
      whenListen(
        personalDataCubit,
        Stream.fromIterable([const KycPersonalDataFailure('fail')]),
        initialState: const KycPersonalDataInitial(),
      );

      await tester.pumpApp(buildSubject(KycPersonalDataView(url: url, initialUserData: userDataDto())));
      await tester.pump();

      expect(find.byType(SnackBar), findsOne);
    });
  });
}
