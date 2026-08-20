import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_kyc_service.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/screens/kyc/steps/2fa/cubits/kyc_2fa_verify/kyc_2fa_verify_cubit.dart';

class _MockKycService extends Mock implements DfxKycService {}

void main() {
  late _MockKycService service;

  setUp(() {
    service = _MockKycService();
  });

  Kyc2FaVerifyCubit build() => Kyc2FaVerifyCubit(service);

  group('initial state', () {
    test('emits $Kyc2FaVerifyInitial', () {
      expect(build().state, isA<Kyc2FaVerifyInitial>());
    });
  });

  group('verifyCode', () {
    blocTest<Kyc2FaVerifyCubit, Kyc2FaVerifyState>(
      'success: forwards the code to the service; Loading → Success',
      setUp: () => when(
        () => service.verify2FaCode(any()),
      ).thenAnswer((_) async {}),
      build: build,
      act: (c) => c.verifyCode('123456'),
      expect: () => const [Kyc2FaVerifyLoading(), Kyc2FaVerifySuccess()],
      verify: (_) => verify(() => service.verify2FaCode('123456')).called(1),
    );

    blocTest<Kyc2FaVerifyCubit, Kyc2FaVerifyState>(
      'failure: verify2FaCode throws → Loading → Failure(errorMessage)',
      setUp: () => when(
        () => service.verify2FaCode(any()),
      ).thenAnswer((_) async => throw Exception('wrong code')),
      build: build,
      act: (c) => c.verifyCode('000000'),
      expect: () => [
        const Kyc2FaVerifyLoading(),
        isA<Kyc2FaVerifyFailure>().having(
          (s) => s.errorMessage,
          'errorMessage',
          contains('wrong code'),
        ),
      ],
    );

    blocTest<Kyc2FaVerifyCubit, Kyc2FaVerifyState>(
      'ApiException → Failure with API message as-is',
      setUp: () => when(() => service.verify2FaCode(any())).thenAnswer(
        (_) async => throw const ApiException(
          statusCode: 400,
          code: 'X',
          message: 'Invalid code',
        ),
      ),
      build: build,
      act: (c) => c.verifyCode('000000'),
      expect: () => [
        const Kyc2FaVerifyLoading(),
        const Kyc2FaVerifyFailure(errorMessage: 'Invalid code'),
      ],
    );
  });

  group('$Kyc2FaVerifyFailure', () {
    test('Equatable props cover errorMessage', () {
      const a = Kyc2FaVerifyFailure(errorMessage: 'x');
      const b = Kyc2FaVerifyFailure(errorMessage: 'x');
      const c = Kyc2FaVerifyFailure(errorMessage: 'y');

      expect(a, b);
      expect(a, isNot(c));
    });
  });
}
