import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_kyc_service.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/screens/kyc/steps/2fa/cubits/kyc_2fa/kyc_2fa_cubit.dart';

class _MockKycService extends Mock implements DfxKycService {}

void main() {
  late _MockKycService service;

  setUp(() {
    service = _MockKycService();
  });

  Kyc2FaCubit build() => Kyc2FaCubit(service);

  group('initial state', () {
    test('emits $Kyc2FaInitial', () {
      expect(build().state, isA<Kyc2FaInitial>());
    });
  });

  group('requestCode', () {
    blocTest<Kyc2FaCubit, Kyc2FaState>(
      'success: Loading → Success',
      setUp: () => when(() => service.request2FaCode()).thenAnswer((_) async {}),
      build: build,
      act: (c) => c.requestCode(),
      expect: () => const [Kyc2FaLoading(), Kyc2FaSuccess()],
      verify: (_) => verify(() => service.request2FaCode()).called(1),
    );

    blocTest<Kyc2FaCubit, Kyc2FaState>(
      'failure: request2FaCode throws → Loading → Failure(errorMessage)',
      setUp: () => when(
        () => service.request2FaCode(),
      ).thenAnswer((_) async => throw Exception('rate limited')),
      build: build,
      act: (c) => c.requestCode(),
      expect: () => [
        const Kyc2FaLoading(),
        isA<Kyc2FaFailure>().having(
          (s) => s.errorMessage,
          'errorMessage',
          contains('rate limited'),
        ),
      ],
    );

    blocTest<Kyc2FaCubit, Kyc2FaState>(
      'ApiException → Failure with API message as-is',
      setUp: () => when(() => service.request2FaCode()).thenAnswer(
        (_) async => throw const ApiException(
          statusCode: 400,
          code: 'X',
          message: 'Too many requests',
        ),
      ),
      build: build,
      act: (c) => c.requestCode(),
      expect: () => [
        const Kyc2FaLoading(),
        const Kyc2FaFailure(errorMessage: 'Too many requests'),
      ],
    );
  });

  group('$Kyc2FaFailure', () {
    test('Equatable props cover errorMessage', () {
      const a = Kyc2FaFailure(errorMessage: 'x');
      const b = Kyc2FaFailure(errorMessage: 'x');
      const c = Kyc2FaFailure(errorMessage: 'y');

      expect(a, b);
      expect(a, isNot(c));
    });
  });
}
