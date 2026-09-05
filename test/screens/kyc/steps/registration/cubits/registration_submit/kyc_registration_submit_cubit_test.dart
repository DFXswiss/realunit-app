import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_kyc_service.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/bitbox_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/models/country/country.dart';
import 'package:realunit_wallet/packages/service/dfx/models/kyc/kyc_level.dart';
import 'package:realunit_wallet/packages/service/dfx/models/registration/dto/real_unit_registration_request_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/registration/registration.dart';
import 'package:realunit_wallet/packages/service/dfx/models/registration/registration_status.dart';
import 'package:realunit_wallet/packages/service/dfx/models/registration/registration_user_type.dart';
import 'package:realunit_wallet/packages/service/dfx/models/user/dto/user_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_registration_service.dart';
import 'package:realunit_wallet/screens/kyc/steps/registration/cubits/registration_submit/kyc_registration_submit_cubit.dart';

class _MockDfxKycService extends Mock implements DfxKycService {}

class _MockRealUnitRegistrationService extends Mock implements RealUnitRegistrationService {}

const _country = Country(
  id: 41,
  symbol: 'CH',
  name: 'Switzerland',
  kycAllowed: true,
);

Registration _registration() => const Registration(
  type: RegistrationUserType.human,
  email: 'test@example.com',
  firstName: 'Alice',
  lastName: 'Doe',
  phoneNumber: '+41791234567',
  birthday: '1990-01-15',
  nationality: _country,
  addressStreet: 'Teststrasse',
  addressStreetNumber: '1',
  addressPostalCode: '8000',
  addressCity: 'Zurich',
  addressCountry: _country,
  swissTaxResidence: true,
);

UserDto _user({String? mail = 'test@example.com'}) => UserDto(
  mail: mail,
  kyc: const UserKycDto(hash: 'h', level: KycLevel.level0, dataComplete: false),
);

Future<void> _submitFromRegistration(
  KycRegistrationSubmitCubit cubit,
  Registration r,
) => cubit.submit(
  type: r.type,
  firstName: r.firstName,
  lastName: r.lastName,
  phoneNumber: r.phoneNumber,
  birthday: r.birthday,
  nationality: r.nationality,
  addressStreet: r.addressStreet,
  addressStreetNumber: r.addressStreetNumber,
  addressPostalCode: r.addressPostalCode,
  addressCity: r.addressCity,
  addressCountry: r.addressCountry,
  swissTaxResidence: r.swissTaxResidence,
);

void main() {
  late DfxKycService kycService;
  late RealUnitRegistrationService registrationService;

  setUpAll(() {
    registerFallbackValue(_registration());
  });

  setUp(() {
    kycService = _MockDfxKycService();
    registrationService = _MockRealUnitRegistrationService();
  });

  KycRegistrationSubmitCubit buildCubit() =>
      KycRegistrationSubmitCubit(registrationService, kycService);

  group('$KycRegistrationSubmitCubit submit', () {
    blocTest<KycRegistrationSubmitCubit, KycRegistrationSubmitState>(
      'happy path → Loading, Success(completed)',
      setUp: () {
        when(() => kycService.getUser()).thenAnswer((_) async => _user());
        when(
          () => registrationService.completeRegistration(any()),
        ).thenAnswer((_) async => RegistrationStatus.completed);
      },
      build: buildCubit,
      act: (cubit) => _submitFromRegistration(cubit, _registration()),
      expect: () => [
        KycRegistrationSubmitLoading(),
        const KycRegistrationSubmitSuccess(RegistrationStatus.completed),
      ],
    );

    test(
      'forwards a non-null countryAndTINs into the Registration handed to the service',
      () async {
        when(() => kycService.getUser()).thenAnswer((_) async => _user());
        when(
          () => registrationService.completeRegistration(any()),
        ).thenAnswer((_) async => RegistrationStatus.completed);

        await buildCubit().submit(
          type: RegistrationUserType.human,
          firstName: 'Alice',
          lastName: 'Doe',
          phoneNumber: '+41791234567',
          birthday: '1990-01-15',
          nationality: _country,
          addressStreet: 'Teststrasse',
          addressStreetNumber: '1',
          addressPostalCode: '8000',
          addressCity: 'Zurich',
          addressCountry: _country,
          swissTaxResidence: false,
          countryAndTINs: const [
            CountryAndTin(country: 'DE', tin: '12 345 678 901'),
          ],
        );

        final captured = verify(
          () => registrationService.completeRegistration(captureAny()),
        ).captured.single as Registration;

        // Guard against changing the phone number while assembling the Registration.
        // The mocked Page test and direct Service test would not observe that mutation.
        expect(captured.phoneNumber, '+41791234567');
        expect(captured.swissTaxResidence, isFalse);
        expect(captured.countryAndTINs, hasLength(1));
        expect(captured.countryAndTINs!.single.country, 'DE');
        expect(captured.countryAndTINs!.single.tin, '12 345 678 901');
      },
    );

    blocTest<KycRegistrationSubmitCubit, KycRegistrationSubmitState>(
      'emits BitboxRequired with the registration payload when BitBox not connected',
      setUp: () {
        when(() => kycService.getUser()).thenAnswer((_) async => _user());
        when(
          () => registrationService.completeRegistration(any()),
        ).thenThrow(const BitboxNotConnectedException());
      },
      build: buildCubit,
      act: (cubit) => _submitFromRegistration(cubit, _registration()),
      expect: () => [
        KycRegistrationSubmitLoading(),
        isA<KycRegistrationSubmitBitboxRequired>(),
      ],
    );

    blocTest<KycRegistrationSubmitCubit, KycRegistrationSubmitState>(
      'emits Success(alreadyRegistered) when the API reports already-registered (was: silent ApiException swallow)',
      setUp: () {
        when(() => kycService.getUser()).thenAnswer((_) async => _user());
        when(() => registrationService.completeRegistration(any())).thenAnswer(
          (_) async => RegistrationStatus.alreadyRegistered,
        );
      },
      build: buildCubit,
      act: (cubit) => _submitFromRegistration(cubit, _registration()),
      expect: () => [
        KycRegistrationSubmitLoading(),
        const KycRegistrationSubmitSuccess(RegistrationStatus.alreadyRegistered),
      ],
    );

    blocTest<KycRegistrationSubmitCubit, KycRegistrationSubmitState>(
      'emits Failure on backend ApiException (account-exists no longer silently masked)',
      setUp: () {
        when(() => kycService.getUser()).thenAnswer((_) async => _user());
        when(() => registrationService.completeRegistration(any())).thenThrow(
          const ApiException(
            statusCode: 409,
            code: 'ACCOUNT_EXISTS',
            message: 'wallet linked to other account',
          ),
        );
      },
      build: buildCubit,
      act: (cubit) => _submitFromRegistration(cubit, _registration()),
      expect: () => [
        KycRegistrationSubmitLoading(),
        isA<KycRegistrationSubmitFailure>().having(
          (s) => s.message,
          'message',
          'wallet linked to other account',
        ),
      ],
    );

    blocTest<KycRegistrationSubmitCubit, KycRegistrationSubmitState>(
      'emits Failure on generic post-sign exception (network/parse/empty-sig)',
      setUp: () {
        when(() => kycService.getUser()).thenAnswer((_) async => _user());
        when(() => registrationService.completeRegistration(any())).thenThrow(
          Exception('Signature was empty'),
        );
      },
      build: buildCubit,
      act: (cubit) => _submitFromRegistration(cubit, _registration()),
      expect: () => [
        KycRegistrationSubmitLoading(),
        isA<KycRegistrationSubmitFailure>(),
      ],
    );

    blocTest<KycRegistrationSubmitCubit, KycRegistrationSubmitState>(
      'emits Failure("Mail could not be fetched") when user has no mail',
      setUp: () {
        when(() => kycService.getUser()).thenAnswer((_) async => _user(mail: null));
      },
      build: buildCubit,
      act: (cubit) => _submitFromRegistration(cubit, _registration()),
      expect: () => [
        KycRegistrationSubmitLoading(),
        const KycRegistrationSubmitFailure('Mail could not be fetched'),
      ],
    );

    blocTest<KycRegistrationSubmitCubit, KycRegistrationSubmitState>(
      'emits Failure with API message when getUser throws ApiException',
      setUp: () {
        when(() => kycService.getUser()).thenThrow(
          const ApiException(statusCode: 401, code: 'X', message: 'Unauthorized'),
        );
      },
      build: buildCubit,
      act: (cubit) => _submitFromRegistration(cubit, _registration()),
      expect: () => [
        KycRegistrationSubmitLoading(),
        isA<KycRegistrationSubmitFailure>().having((s) => s.message, 'message', 'Unauthorized'),
      ],
    );

    blocTest<KycRegistrationSubmitCubit, KycRegistrationSubmitState>(
      'emits Failure when getUser itself throws',
      setUp: () {
        when(() => kycService.getUser()).thenThrow(Exception('auth down'));
      },
      build: buildCubit,
      act: (cubit) => _submitFromRegistration(cubit, _registration()),
      expect: () => [
        KycRegistrationSubmitLoading(),
        isA<KycRegistrationSubmitFailure>(),
      ],
    );
  });

  group('$KycRegistrationSubmitCubit retrySubmit', () {
    blocTest<KycRegistrationSubmitCubit, KycRegistrationSubmitState>(
      'retries the sign after reconnect and emits Success',
      setUp: () {
        when(
          () => registrationService.completeRegistration(any()),
        ).thenAnswer((_) async => RegistrationStatus.completed);
      },
      build: buildCubit,
      act: (cubit) => cubit.retrySubmit(_registration()),
      expect: () => [
        KycRegistrationSubmitLoading(),
        const KycRegistrationSubmitSuccess(RegistrationStatus.completed),
      ],
    );

    blocTest<KycRegistrationSubmitCubit, KycRegistrationSubmitState>(
      'still emits BitboxRequired on retry when wallet is still disconnected',
      setUp: () {
        when(
          () => registrationService.completeRegistration(any()),
        ).thenThrow(const BitboxNotConnectedException());
      },
      build: buildCubit,
      act: (cubit) => cubit.retrySubmit(_registration()),
      expect: () => [
        KycRegistrationSubmitLoading(),
        isA<KycRegistrationSubmitBitboxRequired>(),
      ],
    );
  });
}
