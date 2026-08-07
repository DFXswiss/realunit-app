import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/models/registration/registration_email_status.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_registration_service.dart';
import 'package:realunit_wallet/screens/support/cubits/support_email_capture/support_email_capture_cubit.dart';

class _MockRegistrationService extends Mock implements RealUnitRegistrationService {}

void main() {
  late _MockRegistrationService service;

  setUp(() {
    service = _MockRegistrationService();
  });

  SupportEmailCaptureCubit build() => SupportEmailCaptureCubit(service);

  group('initial state', () {
    test('emits $SupportEmailCaptureInitial', () {
      expect(build().state, isA<SupportEmailCaptureInitial>());
    });
  });

  group('submit', () {
    blocTest<SupportEmailCaptureCubit, SupportEmailCaptureState>(
      'emailRegistered → Loading → Success',
      setUp: () => when(() => service.registerEmail(any())).thenAnswer(
        (_) async => RegistrationEmailStatus.emailRegistered,
      ),
      build: build,
      act: (c) => c.submit('a@b.com'),
      expect: () => const [
        SupportEmailCaptureLoading(),
        SupportEmailCaptureSuccess(),
      ],
      verify: (_) {
        verify(() => service.registerEmail('a@b.com')).called(1);
      },
    );

    blocTest<SupportEmailCaptureCubit, SupportEmailCaptureState>(
      'mergeRequested → Loading → MergeRequested',
      setUp: () => when(() => service.registerEmail(any())).thenAnswer(
        (_) async => RegistrationEmailStatus.mergeRequested,
      ),
      build: build,
      act: (c) => c.submit('a@b.com'),
      expect: () => const [
        SupportEmailCaptureLoading(),
        SupportEmailCaptureMergeRequested(),
      ],
    );

    blocTest<SupportEmailCaptureCubit, SupportEmailCaptureState>(
      'ApiException → Failure carrying the api message',
      setUp: () => when(() => service.registerEmail(any())).thenAnswer(
        (_) async => throw const ApiException(
          code: 'SOMETHING_ELSE',
          message: 'rejected by server',
        ),
      ),
      build: build,
      act: (c) => c.submit('a@b.com'),
      expect: () => [
        const SupportEmailCaptureLoading(),
        isA<SupportEmailCaptureFailure>()
            .having((s) => s.message, 'message', 'rejected by server'),
      ],
    );

    blocTest<SupportEmailCaptureCubit, SupportEmailCaptureState>(
      'non-Api exception → Failure carrying e.toString()',
      setUp: () => when(() => service.registerEmail(any())).thenAnswer(
        (_) async => throw Exception('socket down'),
      ),
      build: build,
      act: (c) => c.submit('a@b.com'),
      expect: () => [
        const SupportEmailCaptureLoading(),
        isA<SupportEmailCaptureFailure>()
            .having((s) => s.message, 'message', contains('socket down')),
      ],
    );
  });
}
