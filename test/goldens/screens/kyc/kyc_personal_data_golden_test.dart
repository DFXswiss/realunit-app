import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_country_service.dart';
import 'package:realunit_wallet/packages/service/dfx/models/registration/kyc/kyc_personal_data.dart';
import 'package:realunit_wallet/packages/service/dfx/models/user/dto/real_unit_user_data_dto.dart';
import 'package:realunit_wallet/screens/kyc/cubits/kyc/kyc_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/personal_data/cubit/kyc_personal_data/kyc_personal_data_cubit.dart';
import 'package:realunit_wallet/screens/kyc/steps/personal_data/kyc_personal_data_page.dart';

import '../../../helper/helper.dart';

class _MockKycPersonalDataCubit extends MockCubit<KycPersonalDataState>
    implements KycPersonalDataCubit {}

class _MockKycCubit extends MockCubit<KycState> implements KycCubit {}

RealUnitUserDataDto _userData() => const RealUnitUserDataDto(
  email: 'erika@example.com',
  name: 'Erika Mueller',
  type: 'HUMAN',
  phoneNumber: '+41790000000',
  birthday: '1990-01-01',
  nationality: 'CH',
  addressStreet: 'Bahnhofstrasse 1',
  addressPostalCode: '8001',
  addressCity: 'Winterthur',
  addressCountry: 'CH',
  swissTaxResidence: true,
  lang: 'EN',
  kycData: KycPersonalData(
    accountType: KycAccountType.personal,
    firstName: 'Erika',
    lastName: 'Mueller',
    phone: '+41790000000',
    address: KycAddress(
      street: 'Bahnhofstrasse',
      houseNumber: '1',
      zip: '8001',
      city: 'Winterthur',
      country: 41,
    ),
  ),
);

void main() {
  late _MockKycPersonalDataCubit personalDataCubit;
  late _MockKycCubit kycCubit;

  setUp(() {
    personalDataCubit = _MockKycPersonalDataCubit();
    kycCubit = _MockKycCubit();

    when(() => personalDataCubit.state).thenReturn(const KycPersonalDataInitial());
    when(() => kycCubit.state).thenReturn(const KycInitial());
  });

  setUpAll(() {
    GetIt.instance.registerSingleton<DfxCountryService>(fixtureCountryService());
  });

  tearDownAll(() async => GetIt.instance.reset());

  group('$KycPersonalDataView', () {
    // initialUserData == null → the page short-circuits to its defensive refresh surface. No cubit is
    // created, so drive the page directly with only the parent KycCubit in scope for the handler.
    goldenTest(
      'missing user data — defensive refresh page',
      fileName: 'kyc_personal_data_page_missing_user_data',
      constraints: phoneConstraints,
      builder: () => wrapForGolden(
        BlocProvider<KycCubit>.value(
          value: kycCubit,
          child: const KycPersonalDataPage(url: 'https://example.com'),
        ),
      ),
    );

    goldenTest(
      'seeded from the registration payload',
      fileName: 'kyc_personal_data_page_default',
      constraints: phoneConstraints,
      builder: () => wrapForGolden(
        MultiBlocProvider(
          providers: [
            BlocProvider<KycPersonalDataCubit>.value(value: personalDataCubit),
            BlocProvider<KycCubit>.value(value: kycCubit),
          ],
          child: KycPersonalDataView(
            url: 'https://example.com',
            initialUserData: _userData(),
          ),
        ),
      ),
    );
  });
}
