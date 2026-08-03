import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/bitbox_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/models/registration/kyc/kyc_personal_data.dart';
import 'package:realunit_wallet/packages/service/dfx/models/registration/registration_status.dart';
import 'package:realunit_wallet/packages/service/dfx/models/user/dto/real_unit_user_data_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_registration_service.dart';
import 'package:realunit_wallet/packages/wallet/exceptions/signing_cancelled_exception.dart';
import 'package:realunit_wallet/packages/wallet/wallet_account.dart';
import 'package:realunit_wallet/screens/migrate_bitbox/cubits/migrate_register/migrate_register_cubit.dart';

class _MockRegistrationService extends Mock implements RealUnitRegistrationService {}

class _MockWalletAccount extends Mock implements AWalletAccount {}

const _userData = RealUnitUserDataDto(
  email: 'ada@example.com',
  name: 'Ada Lovelace',
  type: 'HUMAN',
  phoneNumber: '+41 79 000 00 00',
  birthday: '1815-12-10',
  nationality: 'CH',
  addressStreet: 'Bahnhofstrasse 1',
  addressPostalCode: '8000',
  addressCity: 'Zurich',
  addressCountry: 'CH',
  swissTaxResidence: true,
  lang: 'de',
  kycData: KycPersonalData(
    accountType: KycAccountType.personal,
    firstName: 'Ada',
    lastName: 'Lovelace',
    phone: '+41 79 000 00 00',
    address: KycAddress(
      street: 'Bahnhofstrasse',
      zip: '8000',
      city: 'Zurich',
      country: 41,
    ),
  ),
);

void main() {
  const bearerToken = 'linked-jwt';
  late _MockRegistrationService registrationService;
  late _MockWalletAccount account;

  setUpAll(() {
    registerFallbackValue(_MockWalletAccount());
    registerFallbackValue(_userData);
  });

  setUp(() {
    registrationService = _MockRegistrationService();
    account = _MockWalletAccount();
  });

  MigrateRegisterCubit build() => MigrateRegisterCubit(
    registrationService,
    account: account,
    userData: _userData,
    bearerToken: bearerToken,
  );

  test('starts ready with the supplied registration context', () {
    final cubit = build();
    addTearDown(cubit.close);

    expect(cubit.state, const MigrateRegisterReady());
    expect(cubit.account, same(account));
    expect(cubit.userData, _userData);
    expect(cubit.bearerToken, bearerToken);
  });

  for (final status in [
    RegistrationStatus.completed,
    RegistrationStatus.alreadyRegistered,
  ]) {
    blocTest<MigrateRegisterCubit, MigrateRegisterState>(
      '$status emits Submitting then Success',
      setUp: () {
        when(
          () => registrationService.registerWalletFor(any(), any(), any()),
        ).thenAnswer((_) async => status);
      },
      build: build,
      act: (cubit) => cubit.submit(),
      expect: () => [
        const MigrateRegisterSubmitting(),
        const MigrateRegisterSuccess(),
      ],
      verify: (_) {
        verify(
          () => registrationService.registerWalletFor(
            account,
            _userData,
            bearerToken,
          ),
        ).called(1);
      },
    );
  }

  for (final status in [
    RegistrationStatus.pendingReview,
    RegistrationStatus.forwardingFailed,
  ]) {
    blocTest<MigrateRegisterCubit, MigrateRegisterState>(
      '$status emits Submitting then Pending',
      setUp: () {
        when(
          () => registrationService.registerWalletFor(any(), any(), any()),
        ).thenAnswer((_) async => status);
      },
      build: build,
      act: (cubit) => cubit.submit(),
      expect: () => [
        const MigrateRegisterSubmitting(),
        const MigrateRegisterPending(),
      ],
    );
  }

  final failures = <(Exception, MigrateRegisterFailure)>[
    (
      const SigningCancelledException(),
      const MigrateRegisterFailure(
        MigrateRegisterFailureReason.signatureCancelled,
        canRetry: true,
      ),
    ),
    (
      const BitboxNotConnectedException(),
      const MigrateRegisterFailure(
        MigrateRegisterFailureReason.bitboxNotConnected,
        canRetry: true,
      ),
    ),
    (
      Exception('registration failed'),
      const MigrateRegisterFailure(
        MigrateRegisterFailureReason.generic,
        message: 'Exception: registration failed',
        canRetry: true,
      ),
    ),
  ];

  for (final (error, expectedFailure) in failures) {
    blocTest<MigrateRegisterCubit, MigrateRegisterState>(
      '$error is classified as ${expectedFailure.reason}',
      setUp: () {
        when(
          () => registrationService.registerWalletFor(any(), any(), any()),
        ).thenThrow(error);
      },
      build: build,
      act: (cubit) => cubit.submit(),
      expect: () => [const MigrateRegisterSubmitting(), expectedFailure],
    );
  }

  blocTest<MigrateRegisterCubit, MigrateRegisterState>(
    'retrySubmit re-runs registration',
    setUp: () {
      when(
        () => registrationService.registerWalletFor(any(), any(), any()),
      ).thenAnswer((_) async => RegistrationStatus.completed);
    },
    build: build,
    act: (cubit) => cubit.retrySubmit(),
    expect: () => [
      const MigrateRegisterSubmitting(),
      const MigrateRegisterSuccess(),
    ],
    verify: (_) {
      verify(
        () => registrationService.registerWalletFor(
          account,
          _userData,
          bearerToken,
        ),
      ).called(1);
    },
  );
}
