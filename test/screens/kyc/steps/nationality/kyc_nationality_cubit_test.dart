import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_kyc_service.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/models/country/country.dart';
import 'package:realunit_wallet/screens/kyc/steps/nationality/cubit/kyc_nationality/kyc_nationality_cubit.dart';

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

  KycNationalityCubit build() => KycNationalityCubit(service);

  group('initial state', () {
    test('emits $KycNationalityInitial', () {
      expect(build().state, isA<KycNationalityInitial>());
    });
  });

  group('registerNationality', () {
    blocTest<KycNationalityCubit, KycNationalityState>(
      'success: forwards {"nationality": {"id": <id>}} to setData; Loading → Success',
      setUp: () => when(
        () => service.setData(any(), any()),
      ).thenAnswer((_) async {}),
      build: build,
      act: (c) => c.registerNationality(
        url: 'https://kyc/nat',
        nationality: _switzerland,
      ),
      expect: () => const [KycNationalityLoading(), KycNationalitySuccess()],
      verify: (_) => verify(
        () => service.setData('https://kyc/nat', {
          'nationality': {'id': 41},
        }),
      ).called(1),
    );

    blocTest<KycNationalityCubit, KycNationalityState>(
      'failure: setData throws → Loading → Failure(e.toString())',
      setUp: () => when(
        () => service.setData(any(), any()),
      ).thenAnswer((_) async => throw Exception('boom')),
      build: build,
      act: (c) => c.registerNationality(
        url: 'https://kyc/nat',
        nationality: _switzerland,
      ),
      expect: () => [
        const KycNationalityLoading(),
        isA<KycNationalityFailure>().having(
          (s) => s.message,
          'message',
          contains('boom'),
        ),
      ],
    );

    blocTest<KycNationalityCubit, KycNationalityState>(
      'ApiException → Failure with API message as-is',
      setUp: () => when(() => service.setData(any(), any())).thenAnswer(
        (_) async => throw const ApiException(
          statusCode: 400,
          code: 'X',
          message: 'Invalid nationality',
        ),
      ),
      build: build,
      act: (c) => c.registerNationality(
        url: 'https://kyc/nat',
        nationality: _switzerland,
      ),
      expect: () => [
        const KycNationalityLoading(),
        const KycNationalityFailure('Invalid nationality'),
      ],
    );
  });

  group('$KycNationalityFailure', () {
    test('Equatable props cover message', () {
      const a = KycNationalityFailure('x');
      const b = KycNationalityFailure('x');
      const c = KycNationalityFailure('y');

      expect(a, b);
      expect(a, isNot(c));
    });
  });
}
