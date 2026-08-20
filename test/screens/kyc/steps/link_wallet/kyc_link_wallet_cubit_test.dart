import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/bitbox_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/models/registration/kyc/kyc_personal_data.dart';
import 'package:realunit_wallet/packages/service/dfx/models/registration/registration_status.dart';
import 'package:realunit_wallet/packages/service/dfx/models/user/dto/real_unit_user_data_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_registration_service.dart';
import 'package:realunit_wallet/screens/kyc/steps/link_wallet/cubits/kyc_link_wallet_cubit.dart';

class _MockRegistrationService extends Mock implements RealUnitRegistrationService {}

const _kycData = KycPersonalData(
  accountType: KycAccountType.personal,
  firstName: 'A',
  lastName: 'B',
  phone: '+41',
  address: KycAddress(street: 'S', zip: '8000', city: 'Zurich', country: 41),
);

const _userData = RealUnitUserDataDto(
  email: 'a@b.com',
  name: 'A B',
  type: 'HUMAN',
  phoneNumber: '+41',
  birthday: '2000-01-01',
  nationality: 'CH',
  addressStreet: 'S',
  addressPostalCode: '8000',
  addressCity: 'Zurich',
  addressCountry: 'CH',
  swissTaxResidence: true,
  lang: 'de',
  kycData: _kycData,
);

void main() {
  late _MockRegistrationService registrationService;

  setUpAll(() {
    registerFallbackValue(_userData);
  });

  setUp(() {
    registrationService = _MockRegistrationService();
  });

  // Constructor seeds the userData straight into `Ready` — no fetch round-trip
  // is performed by the cubit. The parent `KycCubit` has already produced this
  // value as part of its routing decision.
  KycLinkWalletCubit build() => KycLinkWalletCubit(registrationService, _userData);

  group('initial state', () {
    test('cubit starts in Ready(userData) with whatever the parent handed in', () {
      final cubit = build();
      expect(cubit.state, const KycLinkWalletReady(_userData));
    });
  });

  group('submit', () {
    blocTest<KycLinkWalletCubit, KycLinkWalletState>(
      'registerWallet succeeds → Submitting → Success',
      setUp: () {
        when(
          () => registrationService.registerWallet(any()),
        ).thenAnswer((_) async => RegistrationStatus.completed);
      },
      build: build,
      act: (c) => c.submit(_userData),
      expect: () => [const KycLinkWalletSubmitting(_userData), const KycLinkWalletSuccess()],
      verify: (_) {
        verify(() => registrationService.registerWallet(_userData)).called(1);
      },
    );

    blocTest<KycLinkWalletCubit, KycLinkWalletState>(
      'registerWallet throws BitboxNotConnectedException → BitboxRequired',
      setUp: () {
        when(
          () => registrationService.registerWallet(any()),
        ).thenThrow(const BitboxNotConnectedException());
      },
      build: build,
      act: (c) => c.submit(_userData),
      expect: () => [
        const KycLinkWalletSubmitting(_userData),
        const KycLinkWalletBitboxRequired(_userData),
      ],
    );

    blocTest<KycLinkWalletCubit, KycLinkWalletState>(
      'registerWallet throws generic exception → Failure',
      setUp: () {
        when(
          () => registrationService.registerWallet(any()),
        ).thenAnswer((_) async => throw Exception('network down'));
      },
      build: build,
      act: (c) => c.submit(_userData),
      expect: () => [const KycLinkWalletSubmitting(_userData), isA<KycLinkWalletFailure>()],
    );

    blocTest<KycLinkWalletCubit, KycLinkWalletState>(
      'registerWallet throws ApiException → Failure with API message as-is',
      setUp: () {
        when(
          () => registrationService.registerWallet(any()),
        ).thenThrow(
          const ApiException(statusCode: 400, code: 'X', message: 'Wallet already linked'),
        );
      },
      build: build,
      act: (c) => c.submit(_userData),
      expect: () => [
        const KycLinkWalletSubmitting(_userData),
        isA<KycLinkWalletFailure>().having((s) => s.message, 'message', 'Wallet already linked'),
      ],
    );
  });

  group('retrySubmit', () {
    blocTest<KycLinkWalletCubit, KycLinkWalletState>(
      're-runs registration after the BitBox was connected → Submitting → Success',
      setUp: () {
        when(
          () => registrationService.registerWallet(any()),
        ).thenAnswer((_) async => RegistrationStatus.completed);
      },
      build: build,
      act: (c) => c.retrySubmit(_userData),
      expect: () => [const KycLinkWalletSubmitting(_userData), const KycLinkWalletSuccess()],
      verify: (_) {
        verify(() => registrationService.registerWallet(_userData)).called(1);
      },
    );

    blocTest<KycLinkWalletCubit, KycLinkWalletState>(
      'still emits BitboxRequired on retry when the BitBox is still disconnected',
      setUp: () {
        when(
          () => registrationService.registerWallet(any()),
        ).thenThrow(const BitboxNotConnectedException());
      },
      build: build,
      act: (c) => c.retrySubmit(_userData),
      expect: () => [
        const KycLinkWalletSubmitting(_userData),
        const KycLinkWalletBitboxRequired(_userData),
      ],
    );
  });
}
