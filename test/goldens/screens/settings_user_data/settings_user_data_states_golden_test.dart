import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_country_service.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_kyc_service.dart';
import 'package:realunit_wallet/packages/service/dfx/models/country/country.dart';
import 'package:realunit_wallet/packages/service/dfx/models/kyc/kyc_level.dart';
import 'package:realunit_wallet/packages/service/dfx/models/registration/registration_user_type.dart';
import 'package:realunit_wallet/packages/service/dfx/models/user/dto/user_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/user/user_data.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_registration_service.dart';
import 'package:realunit_wallet/screens/settings_user_data/cubit/settings_user_data_cubit.dart';
import 'package:realunit_wallet/screens/settings_user_data/settings_user_data_page.dart';

import '../../../helper/helper.dart';

class _MockSettingsUserDataCubit extends MockCubit<SettingsUserDataState>
    implements SettingsUserDataCubit {}

class _MockRealUnitRegistrationService extends Mock implements RealUnitRegistrationService {}

class _MockDfxKycService extends Mock implements DfxKycService {}

void main() {
  // The base `settings_user_data_page_default` golden lives in
  // `settings_user_data_golden_test.dart` and renders a fully-populated
  // `SettingsUserDataSuccess` with the conservative default capabilities
  // (all `canEdit*` false → no Edit buttons). This file covers the remaining
  // build branches of `SettingsUserDataView.build` (see
  // `settings_user_data_page.dart:46-153`).
  const country = Country(
    id: 41,
    symbol: 'CH',
    name: 'Switzerland',
    kycAllowed: true,
  );

  UserData buildUserData({DateTime? birthday}) => UserData(
        email: 'test-direct@dfx.swiss',
        name: 'Test Direct',
        type: RegistrationUserType.human,
        phoneNumber: '+41791234567',
        birthday: birthday,
        nationality: country,
        addressStreet: 'Teststrasse 1',
        addressPostalCode: '8000',
        addressCity: 'Zurich',
        addressCountry: country,
        swissTaxResidence: true,
        lang: 'DE',
      );

  late _MockSettingsUserDataCubit cubit;

  setUp(() {
    cubit = _MockSettingsUserDataCubit();
    when(() => cubit.getUserData()).thenAnswer((_) => Future.value());
  });

  setUpAll(() {
    final getIt = GetIt.instance;
    getIt.registerSingleton<RealUnitRegistrationService>(_MockRealUnitRegistrationService());
    getIt.registerSingleton<DfxCountryService>(fixtureCountryService());
    getIt.registerSingleton<DfxKycService>(_MockDfxKycService());
  });

  tearDownAll(() async {
    await GetIt.instance.reset();
  });

  Widget buildSubject(SettingsUserDataState state) {
    when(() => cubit.state).thenReturn(state);
    return wrapForGolden(
      BlocProvider<SettingsUserDataCubit>.value(
        value: cubit,
        child: const SettingsUserDataView(),
      ),
    );
  }

  group('$SettingsUserDataPage', () {
    // `canEdit*` true → all three Edit buttons render (page:72-123).
    goldenTest(
      'success with edit buttons (all capabilities enabled)',
      fileName: 'settings_user_data_page_editable',
      constraints: phoneConstraints,
      builder: () => buildSubject(
        SettingsUserDataSuccess(
          userData: buildUserData(birthday: DateTime.utc(1990, 1, 1)),
          capabilities: const UserCapabilitiesDto(
            canEditName: true,
            canEditPhone: true,
            canEditAddress: true,
          ),
        ),
      ),
    );

    // `pendingSteps` contains name+address change → "Change in review" badge
    // renders next to the Name and Residence rows (page:69-71, 111-113).
    goldenTest(
      'success with pending change badges',
      fileName: 'settings_user_data_page_pending',
      constraints: phoneConstraints,
      builder: () => buildSubject(
        SettingsUserDataSuccess(
          userData: buildUserData(birthday: DateTime.utc(1990, 1, 1)),
          pendingSteps: const {KycStepName.nameChange, KycStepName.addressChange},
          capabilities: const UserCapabilitiesDto(
            canEditName: true,
            canEditPhone: true,
            canEditAddress: true,
          ),
        ),
      ),
    );

    // `userData.birthday == null` → the Birthday row is dropped (page:83).
    goldenTest(
      'success without a birthday row',
      fileName: 'settings_user_data_page_no_birthday',
      constraints: phoneConstraints,
      builder: () => buildSubject(
        SettingsUserDataSuccess(userData: buildUserData()),
      ),
    );

    // `userData == null` but `email != null` → only the E-Mail row (page:130-139).
    goldenTest(
      'success with only an email (no user data)',
      fileName: 'settings_user_data_page_email_only',
      constraints: phoneConstraints,
      builder: () => buildSubject(
        const SettingsUserDataSuccess(email: 'test-direct@dfx.swiss'),
      ),
    );

    // `userData == null` and `email == null` → "No user data" copy (page:140-142).
    goldenTest(
      'success empty (no user data, no email)',
      fileName: 'settings_user_data_page_empty',
      constraints: phoneConstraints,
      builder: () => buildSubject(const SettingsUserDataSuccess()),
    );

    // Loading → CupertinoActivityIndicator (page:143-145); freeze the spinner.
    goldenTest(
      'loading',
      fileName: 'settings_user_data_page_loading',
      constraints: phoneConstraints,
      pumpBeforeTest: pumpOnce,
      builder: () => buildSubject(const SettingsUserDataLoading()),
    );

    // BitboxDisconnected → _BitboxDisconnectedView (page:146-148, 161-199).
    goldenTest(
      'bitbox disconnected',
      fileName: 'settings_user_data_page_bitbox_disconnected',
      constraints: phoneConstraints,
      builder: () => buildSubject(const SettingsUserDataBitboxDisconnected()),
    );

    // Failure → userDataLoadFailed copy (page:149-151).
    goldenTest(
      'failure',
      fileName: 'settings_user_data_page_failure',
      constraints: phoneConstraints,
      builder: () => buildSubject(const SettingsUserDataFailure()),
    );
  });
}
