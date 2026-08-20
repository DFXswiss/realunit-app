import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_kyc_service.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/models/country/country.dart';
import 'package:realunit_wallet/packages/service/dfx/models/registration/kyc/kyc_personal_data.dart';
import 'package:realunit_wallet/screens/kyc/steps/personal_data/cubit/kyc_personal_data/kyc_personal_data_cubit.dart';

class _MockKycService extends Mock implements DfxKycService {}

const _switzerland = Country(
  id: 41,
  symbol: 'CH',
  name: 'Switzerland',
  kycAllowed: true,
);

void main() {
  late _MockKycService service;

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    service = _MockKycService();
  });

  KycPersonalDataCubit build() => KycPersonalDataCubit(service);

  Future<void> submit(KycPersonalDataCubit c) => c.submit(
    url: 'https://kyc/data/personal/1',
    accountType: KycAccountType.personal,
    firstName: 'Erika',
    lastName: 'Mueller',
    phone: '+41790000000',
    street: 'Bahnhofstrasse',
    houseNumber: '13',
    zip: '8001',
    city: 'Zurich',
    country: _switzerland,
  );

  group('initial state', () {
    test('emits $KycPersonalDataInitial', () {
      expect(build().state, isA<KycPersonalDataInitial>());
    });
  });

  group('submit', () {
    blocTest<KycPersonalDataCubit, KycPersonalDataState>(
      'success: forwards the KycPersonalData body to setData; Loading → Success',
      setUp: () => when(() => service.setData(any(), any())).thenAnswer((_) async {}),
      build: build,
      act: submit,
      expect: () => const [KycPersonalDataLoading(), KycPersonalDataSuccess()],
      verify: (_) => verify(
        () => service.setData('https://kyc/data/personal/1', {
          'accountType': 'Personal',
          'firstName': 'Erika',
          'lastName': 'Mueller',
          'phone': '+41790000000',
          'address': {
            'street': 'Bahnhofstrasse',
            'houseNumber': '13',
            'zip': '8001',
            'city': 'Zurich',
            'country': {'id': 41},
          },
        }),
      ).called(1),
    );

    blocTest<KycPersonalDataCubit, KycPersonalDataState>(
      'failure: setData throws → Loading → Failure(e.toString())',
      setUp: () => when(
        () => service.setData(any(), any()),
      ).thenAnswer((_) async => throw Exception('boom')),
      build: build,
      act: submit,
      expect: () => [
        const KycPersonalDataLoading(),
        isA<KycPersonalDataFailure>().having((s) => s.message, 'message', contains('boom')),
      ],
    );

    blocTest<KycPersonalDataCubit, KycPersonalDataState>(
      'ApiException → Failure with API message as-is',
      setUp: () => when(() => service.setData(any(), any())).thenAnswer(
        (_) async => throw const ApiException(
          statusCode: 400,
          code: 'X',
          message: 'Invalid address',
        ),
      ),
      build: build,
      act: submit,
      expect: () => [
        const KycPersonalDataLoading(),
        const KycPersonalDataFailure('Invalid address'),
      ],
    );
  });

  group('$KycPersonalDataFailure', () {
    test('Equatable props cover message', () {
      const a = KycPersonalDataFailure('x');
      const b = KycPersonalDataFailure('x');
      const c = KycPersonalDataFailure('y');

      expect(a, b);
      expect(a, isNot(c));
    });
  });
}
