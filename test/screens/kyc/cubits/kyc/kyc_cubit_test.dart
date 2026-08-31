import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_kyc_service.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/models/kyc/dto/kyc_level_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/kyc/dto/kyc_session_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/kyc/dto/kyc_step_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/kyc/kyc_level.dart';
import 'package:realunit_wallet/packages/service/dfx/models/legal/dto/real_unit_legal_agreement_status_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/legal/dto/real_unit_legal_info_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/legal/real_unit_legal_agreement.dart';
import 'package:realunit_wallet/packages/service/dfx/models/registration/registration_email_status.dart';
import 'package:realunit_wallet/packages/service/dfx/models/registration/kyc/kyc_personal_data.dart';
import 'package:realunit_wallet/packages/service/dfx/models/user/dto/real_unit_user_data_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/user/dto/user_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/wallet/real_unit_registration_info_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/wallet/real_unit_registration_state.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_legal_service.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_registration_service.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';
import 'package:realunit_wallet/screens/kyc/cubits/kyc/kyc_cubit.dart';
import 'package:realunit_wallet/screens/settings/bloc/settings_bloc.dart';
import 'package:realunit_wallet/setup/account_currency_sync.dart';
import 'package:realunit_wallet/styles/currency.dart';

class _MockDfxKycService extends Mock implements DfxKycService {}

class _MockRealUnitRegistrationService extends Mock implements RealUnitRegistrationService {}

class _MockRealUnitLegalService extends Mock implements RealUnitLegalService {}

class _MockAppStore extends Mock implements AppStore {}

class _MockAWallet extends Mock implements AWallet {}

class _MockSettingsBloc extends MockBloc<SettingsEvent, SettingsState> implements SettingsBloc {}

UserKycDto _kycHeader({KycLevel level = KycLevel.level0}) =>
    UserKycDto(hash: 'h', level: level, dataComplete: false);

UserDto _user({
  String? mail = 'test@example.com',
  KycLevel headerLevel = KycLevel.level0,
  Currency? currency,
}) => UserDto(
  mail: mail,
  kyc: _kycHeader(level: headerLevel),
  currency: currency,
);

KycStepDto _step(
  KycStepName name, {
  KycStepStatus status = KycStepStatus.notStarted,
  KycStepReason? reason,
  bool isCurrent = false,
  bool isRequired = false,
  int sequenceNumber = 0,
}) => KycStepDto(
  name: name,
  status: status,
  reason: reason,
  sequenceNumber: sequenceNumber,
  isCurrent: isCurrent,
  isRequired: isRequired,
);

KycLevelDto _kycStatus({
  required KycLevel level,
  List<KycStepDto> steps = const [],
  KycProcessStatus processStatus = KycProcessStatus.inProgress,
}) => KycLevelDto(kycLevel: level, kycSteps: steps, processStatus: processStatus);

KycSessionDto _session({
  required KycLevel level,
  required List<KycStepDto> steps,
  KycStepSessionDto? currentStep,
  KycProcessStatus processStatus = KycProcessStatus.inProgress,
}) => KycSessionDto(
  kycLevel: level,
  kycSteps: steps,
  currentStep: currentStep,
  processStatus: processStatus,
);

KycStepSessionDto _currentStep(
  KycStepName name, {
  String url = 'https://example.com/session',
  UrlType urlType = UrlType.browser,
  KycStepStatus status = KycStepStatus.inProgress,
  int sequenceNumber = 0,
}) => KycStepSessionDto(
  session: KycSessionInfoDto(url: url, type: urlType),
  name: name,
  status: status,
  sequenceNumber: sequenceNumber,
  isCurrent: true,
);

RealUnitRegistrationInfoDto _walletStatus(
  RealUnitRegistrationState state, {
  RealUnitUserDataDto? userData,
  bool? emailConfirmed,
  bool? manualReview,
}) => RealUnitRegistrationInfoDto(
  state: state,
  realUnitUserDataDto: userData,
  emailConfirmed: emailConfirmed,
  manualReview: manualReview,
);

// Single-agreement legal info. `allAccepted:false` leaves the one agreement
// outstanding (so `outstandingAgreements` == [residenceConfirmation]).
RealUnitLegalInfoDto _legalInfo({bool allAccepted = true}) => RealUnitLegalInfoDto(
  agreements: [
    RealUnitLegalAgreementStatusDto(
      agreement: RealUnitLegalAgreement.residenceConfirmation,
      currentVersion: '20260712',
      acceptedVersion: allAccepted ? '20260712' : null,
      accepted: allAccepted,
    ),
  ],
  allAccepted: allAccepted,
);

const _kycPersonalData = KycPersonalData(
  accountType: KycAccountType.personal,
  firstName: 'Ada',
  lastName: 'Lovelace',
  phone: '+41790000000',
  address: KycAddress(street: 'S', zip: '8000', city: 'Zurich', country: 41),
);

const _fixtureUserData = RealUnitUserDataDto(
  email: 'ada@example.com',
  name: 'Ada Lovelace',
  type: 'HUMAN',
  phoneNumber: '+41790000000',
  birthday: '1815-12-10',
  nationality: 'CH',
  addressStreet: 'S',
  addressPostalCode: '8000',
  addressCity: 'Zurich',
  addressCountry: 'CH',
  swissTaxResidence: true,
  lang: 'de',
  kycData: _kycPersonalData,
);

void main() {
  late DfxKycService kycService;
  late RealUnitRegistrationService registrationService;
  late RealUnitLegalService legalService;
  late AppStore appStore;
  late AWallet wallet;

  setUpAll(() {
    registerFallbackValue(<RealUnitLegalAgreement>[]);
    registerFallbackValue(const ApplyAccountCurrencyEvent(Currency.chf));
  });

  setUp(() {
    kycService = _MockDfxKycService();
    registrationService = _MockRealUnitRegistrationService();
    legalService = _MockRealUnitLegalService();
    appStore = _MockAppStore();
    wallet = _MockAWallet();
    when(() => appStore.wallet).thenReturn(wallet);
    // Default: software wallet — most tests don't care about the signing
    // capability gate.
    when(() => wallet.walletType).thenReturn(WalletType.software);
    // Default: AlreadyRegistered — most tests don't care about the wallet
    // status branch and want to fall through to the processStatus dispatch.
    when(() => registrationService.getRegistrationInfo()).thenAnswer(
      (_) async => _walletStatus(RealUnitRegistrationState.alreadyRegistered),
    );
    // Default: the server reports all legal agreements accepted, so the
    // disclaimer gate passes and tests exercise downstream routing. Tests that
    // exercise the gate itself override this per-test.
    when(() => legalService.getLegalInfo()).thenAnswer((_) async => _legalInfo());
  });

  KycCubit buildCubit() => KycCubit(kycService, registrationService, legalService, appStore);

  group('$KycCubit checkKyc', () {
    blocTest<KycCubit, KycState>(
      'emits KycSuccess(email) when user has no email',
      setUp: () {
        when(() => kycService.getKycStatus()).thenAnswer(
          (_) async => _kycStatus(level: KycLevel.level0),
        );
        when(() => kycService.getUser()).thenAnswer((_) async => _user(mail: null));
      },
      build: buildCubit,
      act: (cubit) => cubit.checkKyc(),
      expect: () => [
        const KycLoading(),
        const KycSuccess(currentStep: KycStep.email),
      ],
    );

    blocTest<KycCubit, KycState>(
      'applies account currency from GET /v2/user when a wallet is open',
      setUp: () {
        final settings = _MockSettingsBloc();
        GetIt.instance.registerSingleton<SettingsBloc>(settings);
        GetIt.instance.registerSingleton(
          AccountCurrencySync(
            settings: settings,
            kyc: kycService,
            currentWallet: () => wallet,
          ),
        );
        when(() => kycService.getKycStatus()).thenAnswer(
          (_) async => _kycStatus(level: KycLevel.level0),
        );
        when(() => kycService.getUser()).thenAnswer(
          (_) async => _user(mail: null, currency: Currency.chf),
        );
      },
      build: buildCubit,
      act: (cubit) => cubit.checkKyc(),
      expect: () => [
        const KycLoading(),
        const KycSuccess(currentStep: KycStep.email),
      ],
      verify: (_) {
        verify(
          () => GetIt.instance<SettingsBloc>().add(const ApplyAccountCurrencyEvent(Currency.chf)),
        ).called(1);
      },
      tearDown: () async => GetIt.instance.reset(),
    );

    blocTest<KycCubit, KycState>(
      'does not dispatch ApplyAccountCurrencyEvent when GET /v2/user has no currency',
      setUp: () {
        GetIt.instance.registerSingleton<SettingsBloc>(_MockSettingsBloc());
        when(() => kycService.getKycStatus()).thenAnswer(
          (_) async => _kycStatus(level: KycLevel.level0),
        );
        when(() => kycService.getUser()).thenAnswer((_) async => _user(mail: null));
      },
      build: buildCubit,
      act: (cubit) => cubit.checkKyc(),
      expect: () => [
        const KycLoading(),
        const KycSuccess(currentStep: KycStep.email),
      ],
      verify: (_) {
        verifyNever(() => GetIt.instance<SettingsBloc>().add(any()));
      },
      tearDown: () async => GetIt.instance.reset(),
    );

    blocTest<KycCubit, KycState>(
      'does not dispatch ApplyAccountCurrencyEvent when the wallet is closed',
      setUp: () {
        final settings = _MockSettingsBloc();
        GetIt.instance.registerSingleton<SettingsBloc>(settings);
        GetIt.instance.registerSingleton(
          AccountCurrencySync(
            settings: settings,
            kyc: kycService,
            currentWallet: () => null,
          ),
        );
        when(() => kycService.getKycStatus()).thenAnswer(
          (_) async => _kycStatus(level: KycLevel.level0),
        );
        when(() => kycService.getUser()).thenAnswer(
          (_) async => _user(mail: null, currency: Currency.chf),
        );
      },
      build: buildCubit,
      act: (cubit) => cubit.checkKyc(),
      expect: () => [
        const KycLoading(),
        const KycSuccess(currentStep: KycStep.email),
      ],
      verify: (_) {
        verifyNever(() => GetIt.instance<SettingsBloc>().add(any()));
      },
      tearDown: () async => GetIt.instance.reset(),
    );

    test('does not dispatch ApplyAccountCurrencyEvent after a different wallet opens', () async {
      final settings = _MockSettingsBloc();
      GetIt.instance.registerSingleton<SettingsBloc>(settings);
      AWallet? current = wallet;
      GetIt.instance.registerSingleton(
        AccountCurrencySync(
          settings: settings,
          kyc: kycService,
          currentWallet: () => current,
        ),
      );
      when(() => kycService.getKycStatus()).thenAnswer(
        (_) async => _kycStatus(level: KycLevel.level0),
      );
      final held = Completer<UserDto>();
      when(() => kycService.getUser()).thenAnswer((_) => held.future);

      final cubit = buildCubit();
      final pending = cubit.checkKyc();

      current = _MockAWallet();
      held.complete(_user(mail: null, currency: Currency.chf));
      await pending;

      verifyNever(() => settings.add(any()));
      await cubit.close();
      await GetIt.instance.reset();
    });

    blocTest<KycCubit, KycState>(
      'does not dispatch ApplyAccountCurrencyEvent when AccountCurrencySync is unregistered',
      setUp: () {
        GetIt.instance.registerSingleton<SettingsBloc>(_MockSettingsBloc());
        when(() => kycService.getKycStatus()).thenAnswer(
          (_) async => _kycStatus(level: KycLevel.level0),
        );
        when(() => kycService.getUser()).thenAnswer(
          (_) async => _user(mail: null, currency: Currency.chf),
        );
      },
      build: buildCubit,
      act: (cubit) => cubit.checkKyc(),
      expect: () => [
        const KycLoading(),
        const KycSuccess(currentStep: KycStep.email),
      ],
      verify: (_) {
        verifyNever(() => GetIt.instance<SettingsBloc>().add(any()));
      },
      tearDown: () async => GetIt.instance.reset(),
    );

    blocTest<KycCubit, KycState>(
      'auto-registers email when mail exists but level < 10, then recurses',
      setUp: () {
        when(() => kycService.getKycStatus()).thenAnswer(
          (_) async => _kycStatus(level: KycLevel.level0),
        );
        when(() => kycService.getUser()).thenAnswer((_) async => _user());
        when(() => registrationService.registerEmail(any())).thenAnswer(
          (_) async => RegistrationEmailStatus.emailRegistered,
        );
      },
      build: buildCubit,
      act: (cubit) => cubit.checkKyc(),
      expect: () => [
        const KycLoading(),
        const KycSuccess(currentStep: KycStep.email),
      ],
      verify: (_) {
        verify(() => registrationService.registerEmail('test@example.com')).called(1);
      },
    );

    // Legal disclaimer gate is server-driven: the API is the single source of
    // truth for whether outstanding agreements remain. `allAccepted:false`
    // routes to the disclaimer step.
    blocTest<KycCubit, KycState>(
      'emits KycSuccess(legalDisclaimer) when the server reports outstanding agreements',
      setUp: () {
        when(() => kycService.getKycStatus()).thenAnswer(
          (_) async => _kycStatus(level: KycLevel.level20),
        );
        when(() => kycService.getUser()).thenAnswer((_) async => _user());
        when(() => legalService.getLegalInfo()).thenAnswer(
          (_) async => _legalInfo(allAccepted: false),
        );
      },
      build: buildCubit,
      act: (cubit) => cubit.checkKyc(),
      expect: () => [
        const KycLoading(),
        const KycSuccess(currentStep: KycStep.legalDisclaimer),
      ],
    );

    // `allAccepted:true` (default stub) passes the gate without ever showing
    // the disclaimer — the once-per-session ceremony is gone; the server
    // decides.
    blocTest<KycCubit, KycState>(
      'proceeds past the disclaimer gate when the server reports allAccepted',
      setUp: () {
        when(() => kycService.getKycStatus()).thenAnswer(
          (_) async => _kycStatus(
            level: KycLevel.level50,
            processStatus: KycProcessStatus.completed,
          ),
        );
        when(() => kycService.getUser()).thenAnswer((_) async => _user());
      },
      build: buildCubit,
      act: (cubit) => cubit.checkKyc(),
      expect: () => [
        const KycLoading(),
        const KycCompleted(),
      ],
    );

    // Legacy tolerance (mirrors the `emailConfirmed` gate): a 404 means the
    // legal endpoint is not deployed yet (pre-rollout backend), so the gate
    // falls back to the local per-session flag. With nothing accepted yet the
    // flag is `false`, so the disclaimer is shown — identical to the previous
    // behaviour.
    blocTest<KycCubit, KycState>(
      'falls back to the local session gate (shows disclaimer) when getLegalInfo returns 404',
      setUp: () {
        when(() => kycService.getKycStatus()).thenAnswer(
          (_) async => _kycStatus(level: KycLevel.level20),
        );
        when(() => kycService.getUser()).thenAnswer((_) async => _user());
        when(() => legalService.getLegalInfo()).thenThrow(
          const ApiException(statusCode: 404, code: 'NOT_FOUND', message: ''),
        );
      },
      build: buildCubit,
      act: (cubit) => cubit.checkKyc(),
      expect: () => [
        const KycLoading(),
        const KycSuccess(currentStep: KycStep.legalDisclaimer),
      ],
    );

    // Fail closed: any non-404 error on the compliance gate must surface as a
    // KycFailure — never silently degrade to the local flag (no silent fallback
    // on a legal gate).
    blocTest<KycCubit, KycState>(
      'emits KycFailure when getLegalInfo fails with a non-404 error',
      setUp: () {
        when(() => kycService.getKycStatus()).thenAnswer(
          (_) async => _kycStatus(level: KycLevel.level20),
        );
        when(() => kycService.getUser()).thenAnswer((_) async => _user());
        when(() => legalService.getLegalInfo()).thenThrow(
          const ApiException(statusCode: 500, code: 'SERVER_ERROR', message: 'boom'),
        );
      },
      build: buildCubit,
      act: (cubit) => cubit.checkKyc(),
      expect: () => [
        const KycLoading(),
        isA<KycFailure>(),
      ],
    );

    // Wave 3 — server-side registration state drives routing. The cubit
    // re-fetches `getRegistrationInfo()` after the disclaimer gate and dispatches
    // on its `state` field, with no local sign-produced flag. The DTO that
    // came back from `getRegistrationInfo` is forwarded on the emitted state so
    // downstream pages do not have to re-fetch.
    blocTest<KycCubit, KycState>(
      'emits KycSuccess(registration) with propagated userData when wallet status reports NewRegistration',
      setUp: () {
        when(() => kycService.getKycStatus()).thenAnswer(
          (_) async => _kycStatus(level: KycLevel.level20),
        );
        when(() => kycService.getUser()).thenAnswer((_) async => _user());
        when(() => registrationService.getRegistrationInfo()).thenAnswer(
          (_) async => _walletStatus(
            RealUnitRegistrationState.newRegistration,
            userData: _fixtureUserData,
          ),
        );
      },
      build: buildCubit,
      act: (cubit) => cubit.checkKyc(),
      expect: () => [
        const KycLoading(),
        const KycSuccess(
          currentStep: KycStep.registration,
          realUnitUserData: _fixtureUserData,
        ),
      ],
    );

    blocTest<KycCubit, KycState>(
      'emits KycSuccess(registration) with null userData when the server omits it',
      setUp: () {
        when(() => kycService.getKycStatus()).thenAnswer(
          (_) async => _kycStatus(level: KycLevel.level20),
        );
        when(() => kycService.getUser()).thenAnswer((_) async => _user());
        when(() => registrationService.getRegistrationInfo()).thenAnswer(
          (_) async => _walletStatus(RealUnitRegistrationState.newRegistration),
        );
      },
      build: buildCubit,
      act: (cubit) => cubit.checkKyc(),
      expect: () => [
        const KycLoading(),
        const KycSuccess(currentStep: KycStep.registration),
      ],
    );

    blocTest<KycCubit, KycState>(
      'emits KycSuccess(linkWallet) with propagated userData when wallet status reports AddWallet',
      setUp: () {
        when(() => kycService.getKycStatus()).thenAnswer(
          (_) async => _kycStatus(level: KycLevel.level20),
        );
        when(() => kycService.getUser()).thenAnswer((_) async => _user());
        when(() => registrationService.getRegistrationInfo()).thenAnswer(
          (_) async => _walletStatus(
            RealUnitRegistrationState.addWallet,
            userData: _fixtureUserData,
          ),
        );
      },
      build: buildCubit,
      act: (cubit) => cubit.checkKyc(),
      expect: () => [
        const KycLoading(),
        const KycSuccess(
          currentStep: KycStep.linkWallet,
          realUnitUserData: _fixtureUserData,
        ),
      ],
    );

    // Wallet-mode signing-capability gate: the address+signature debug
    // wallet cannot produce an EIP-712 signature. The cubit must surface
    // `KycSignatureUnsupportedFailure` BEFORE emitting `KycSuccess` for any
    // state that would require signing (`NewRegistration` / `AddWallet`).
    // States that don't require signing (`AlreadyRegistered`) still flow
    // through normally.
    blocTest<KycCubit, KycState>(
      'emits KycSignatureUnsupportedFailure when debug wallet + NewRegistration',
      setUp: () {
        when(() => wallet.walletType).thenReturn(WalletType.debug);
        when(() => kycService.getKycStatus()).thenAnswer(
          (_) async => _kycStatus(level: KycLevel.level20),
        );
        when(() => kycService.getUser()).thenAnswer((_) async => _user());
        when(() => registrationService.getRegistrationInfo()).thenAnswer(
          (_) async => _walletStatus(
            RealUnitRegistrationState.newRegistration,
            userData: _fixtureUserData,
          ),
        );
      },
      build: buildCubit,
      act: (cubit) => cubit.checkKyc(),
      expect: () => [
        const KycLoading(),
        const KycSignatureUnsupportedFailure(),
      ],
    );

    blocTest<KycCubit, KycState>(
      'emits KycSignatureUnsupportedFailure when debug wallet + AddWallet',
      setUp: () {
        when(() => wallet.walletType).thenReturn(WalletType.debug);
        when(() => kycService.getKycStatus()).thenAnswer(
          (_) async => _kycStatus(level: KycLevel.level20),
        );
        when(() => kycService.getUser()).thenAnswer((_) async => _user());
        when(() => registrationService.getRegistrationInfo()).thenAnswer(
          (_) async => _walletStatus(
            RealUnitRegistrationState.addWallet,
            userData: _fixtureUserData,
          ),
        );
      },
      build: buildCubit,
      act: (cubit) => cubit.checkKyc(),
      expect: () => [
        const KycLoading(),
        const KycSignatureUnsupportedFailure(),
      ],
    );

    blocTest<KycCubit, KycState>(
      'debug wallet + AlreadyRegistered passes through (no signing needed)',
      setUp: () {
        when(() => wallet.walletType).thenReturn(WalletType.debug);
        when(() => kycService.getKycStatus()).thenAnswer(
          (_) async => _kycStatus(
            level: KycLevel.level50,
            processStatus: KycProcessStatus.completed,
          ),
        );
        when(() => kycService.getUser()).thenAnswer((_) async => _user());
        // Default already maps to AlreadyRegistered — make it explicit here.
        when(() => registrationService.getRegistrationInfo()).thenAnswer(
          (_) async => _walletStatus(RealUnitRegistrationState.alreadyRegistered),
        );
      },
      build: buildCubit,
      act: (cubit) => cubit.checkKyc(),
      expect: () => [
        const KycLoading(),
        const KycCompleted(),
      ],
    );

    // Email-confirmation gate (API-driven). Only an explicit
    // `emailConfirmed == false` on an already-registered wallet routes to the
    // confirm step; `true` (confirmed, or grandfathered) and `null` (pre-rollout
    // backend) proceed as before.
    blocTest<KycCubit, KycState>(
      'emits KycSuccess(confirmEmail) when AlreadyRegistered and emailConfirmed=false',
      setUp: () {
        when(() => kycService.getKycStatus()).thenAnswer(
          (_) async => _kycStatus(
            level: KycLevel.level50,
            processStatus: KycProcessStatus.completed,
          ),
        );
        when(() => kycService.getUser()).thenAnswer((_) async => _user());
        when(() => registrationService.getRegistrationInfo()).thenAnswer(
          (_) async => _walletStatus(
            RealUnitRegistrationState.alreadyRegistered,
            emailConfirmed: false,
          ),
        );
      },
      build: buildCubit,
      act: (cubit) => cubit.checkKyc(),
      expect: () => [
        const KycLoading(),
        const KycSuccess(currentStep: KycStep.confirmEmail),
      ],
    );

    blocTest<KycCubit, KycState>(
      'proceeds (no confirm gate) when AlreadyRegistered and emailConfirmed=true',
      setUp: () {
        when(() => kycService.getKycStatus()).thenAnswer(
          (_) async => _kycStatus(
            level: KycLevel.level50,
            processStatus: KycProcessStatus.completed,
          ),
        );
        when(() => kycService.getUser()).thenAnswer((_) async => _user());
        when(() => registrationService.getRegistrationInfo()).thenAnswer(
          (_) async => _walletStatus(
            RealUnitRegistrationState.alreadyRegistered,
            emailConfirmed: true,
          ),
        );
      },
      build: buildCubit,
      act: (cubit) => cubit.checkKyc(),
      expect: () => [
        const KycLoading(),
        const KycCompleted(),
      ],
    );

    blocTest<KycCubit, KycState>(
      'legacy fallback: proceeds when AlreadyRegistered and emailConfirmed=null',
      setUp: () {
        when(() => kycService.getKycStatus()).thenAnswer(
          (_) async => _kycStatus(
            level: KycLevel.level50,
            processStatus: KycProcessStatus.completed,
          ),
        );
        when(() => kycService.getUser()).thenAnswer((_) async => _user());
        // Explicit null — the pre-rollout backend case (grandfathered accounts
        // report an explicit `true`, never `null`).
        when(() => registrationService.getRegistrationInfo()).thenAnswer(
          (_) async => _walletStatus(
            RealUnitRegistrationState.alreadyRegistered,
          ),
        );
      },
      build: buildCubit,
      act: (cubit) => cubit.checkKyc(),
      expect: () => [
        const KycLoading(),
        const KycCompleted(),
      ],
    );

    // Manual-review gate (API-driven). When the Aktionariat forward failed and
    // staff must re-forward the registration, the API reports
    // `manualReview == true` on the already-registered wallet and the cubit
    // parks the user on a dedicated waiting state. `false` and `null`
    // (pre-rollout backend) proceed as before.
    blocTest<KycCubit, KycState>(
      'emits KycManualReview when AlreadyRegistered and manualReview=true',
      setUp: () {
        when(() => kycService.getKycStatus()).thenAnswer(
          (_) async => _kycStatus(
            level: KycLevel.level50,
            processStatus: KycProcessStatus.completed,
          ),
        );
        when(() => kycService.getUser()).thenAnswer((_) async => _user());
        when(() => registrationService.getRegistrationInfo()).thenAnswer(
          (_) async => _walletStatus(
            RealUnitRegistrationState.alreadyRegistered,
            manualReview: true,
          ),
        );
      },
      build: buildCubit,
      act: (cubit) => cubit.checkKyc(),
      expect: () => [
        const KycLoading(),
        const KycManualReview(),
      ],
    );

    // Manual review takes precedence over the e-mail gate: even with
    // `emailConfirmed == false`, an explicit `manualReview == true` parks the
    // user on the review screen rather than routing to the confirm step.
    blocTest<KycCubit, KycState>(
      'manualReview=true takes precedence over emailConfirmed=false',
      setUp: () {
        when(() => kycService.getKycStatus()).thenAnswer(
          (_) async => _kycStatus(
            level: KycLevel.level50,
            processStatus: KycProcessStatus.completed,
          ),
        );
        when(() => kycService.getUser()).thenAnswer((_) async => _user());
        when(() => registrationService.getRegistrationInfo()).thenAnswer(
          (_) async => _walletStatus(
            RealUnitRegistrationState.alreadyRegistered,
            manualReview: true,
            emailConfirmed: false,
          ),
        );
      },
      build: buildCubit,
      act: (cubit) => cubit.checkKyc(),
      expect: () => [
        const KycLoading(),
        const KycManualReview(),
      ],
    );

    // `manualReview == false` is no gate: the cubit proceeds exactly as before
    // and still applies the e-mail gate below it (here → confirmEmail).
    blocTest<KycCubit, KycState>(
      'does NOT emit KycManualReview when manualReview=false (still hits the confirmEmail gate)',
      setUp: () {
        when(() => kycService.getKycStatus()).thenAnswer(
          (_) async => _kycStatus(
            level: KycLevel.level50,
            processStatus: KycProcessStatus.completed,
          ),
        );
        when(() => kycService.getUser()).thenAnswer((_) async => _user());
        when(() => registrationService.getRegistrationInfo()).thenAnswer(
          (_) async => _walletStatus(
            RealUnitRegistrationState.alreadyRegistered,
            manualReview: false,
            emailConfirmed: false,
          ),
        );
      },
      build: buildCubit,
      act: (cubit) => cubit.checkKyc(),
      expect: () => [
        const KycLoading(),
        const KycSuccess(currentStep: KycStep.confirmEmail),
      ],
    );

    // Legacy fallback: `manualReview == null` (pre-rollout backend) is no gate —
    // the cubit proceeds exactly as before (here → Completed).
    blocTest<KycCubit, KycState>(
      'legacy fallback: proceeds when AlreadyRegistered and manualReview=null',
      setUp: () {
        when(() => kycService.getKycStatus()).thenAnswer(
          (_) async => _kycStatus(
            level: KycLevel.level50,
            processStatus: KycProcessStatus.completed,
          ),
        );
        when(() => kycService.getUser()).thenAnswer((_) async => _user());
        // Explicit null manualReview + confirmed e-mail — no gate at all.
        when(() => registrationService.getRegistrationInfo()).thenAnswer(
          (_) async => _walletStatus(
            RealUnitRegistrationState.alreadyRegistered,
            emailConfirmed: true,
          ),
        );
      },
      build: buildCubit,
      act: (cubit) => cubit.checkKyc(),
      expect: () => [
        const KycLoading(),
        const KycCompleted(),
      ],
    );

    // The confirm gate is scoped to `alreadyRegistered`. In `addWallet`,
    // `emailConfirmed` describes the other wallet's registration, so an explicit
    // `false` must NOT route to the confirm step — the user proceeds to link the
    // wallet and the gate is re-evaluated on the fresh registration afterwards.
    blocTest<KycCubit, KycState>(
      'does NOT gate on emailConfirmed=false when AddWallet (routes to linkWallet)',
      setUp: () {
        when(() => kycService.getKycStatus()).thenAnswer(
          (_) async => _kycStatus(level: KycLevel.level20),
        );
        when(() => kycService.getUser()).thenAnswer((_) async => _user());
        when(() => registrationService.getRegistrationInfo()).thenAnswer(
          (_) async => _walletStatus(
            RealUnitRegistrationState.addWallet,
            userData: _fixtureUserData,
            emailConfirmed: false,
          ),
        );
      },
      build: buildCubit,
      act: (cubit) => cubit.checkKyc(),
      expect: () => [
        const KycLoading(),
        const KycSuccess(
          currentStep: KycStep.linkWallet,
          realUnitUserData: _fixtureUserData,
        ),
      ],
    );

    // Failure-path coverage for the wallet-status round-trip: if
    // `getRegistrationInfo()` itself throws, the outer `catch` in `_runCheckKyc`
    // must surface a `KycFailure` rather than leaking the exception through
    // the disclaimer-passed gate or wedging the state machine.
    blocTest<KycCubit, KycState>(
      'emits KycFailure when getRegistrationInfo throws',
      setUp: () {
        when(() => kycService.getKycStatus()).thenAnswer(
          (_) async => _kycStatus(level: KycLevel.level20),
        );
        when(() => kycService.getUser()).thenAnswer((_) async => _user());
        when(() => registrationService.getRegistrationInfo()).thenThrow(
          Exception('network error'),
        );
      },
      build: buildCubit,
      act: (cubit) => cubit.checkKyc(),
      expect: () => [
        const KycLoading(),
        isA<KycFailure>(),
      ],
    );

    blocTest<KycCubit, KycState>(
      'emits KycAccountMergeRequested when any step carries the accountMergeRequested reason',
      setUp: () {
        when(() => kycService.getKycStatus()).thenAnswer(
          (_) async => _kycStatus(
            level: KycLevel.level20,
            steps: [
              _step(
                KycStepName.contactData,
                reason: KycStepReason.accountMergeRequested,
              ),
            ],
          ),
        );
        when(() => kycService.getUser()).thenAnswer((_) async => _user());
      },
      build: buildCubit,
      act: (cubit) => cubit.checkKyc(),
      expect: () => [
        const KycLoading(),
        const KycAccountMergeRequested(),
      ],
    );

    // From here on the routing is API-driven via `processStatus` —
    // the cubit no longer iterates `kycSteps` to derive completion or
    // pendingness.
    blocTest<KycCubit, KycState>(
      'emits KycCompleted when API reports processStatus=Completed',
      setUp: () {
        when(() => kycService.getKycStatus()).thenAnswer(
          (_) async => _kycStatus(
            level: KycLevel.level50,
            processStatus: KycProcessStatus.completed,
          ),
        );
        when(() => kycService.getUser()).thenAnswer((_) async => _user());
      },
      build: buildCubit,
      act: (cubit) => cubit.checkKyc(),
      expect: () => [const KycLoading(), const KycCompleted()],
    );

    blocTest<KycCubit, KycState>(
      'emits KycMergeProcessing when API reports processStatus=MergeProcessing',
      setUp: () {
        when(() => kycService.getKycStatus()).thenAnswer(
          (_) async => _kycStatus(
            level: KycLevel.level20,
            processStatus: KycProcessStatus.mergeProcessing,
          ),
        );
        when(() => kycService.getUser()).thenAnswer((_) async => _user());
      },
      build: buildCubit,
      act: (cubit) => cubit.checkKyc(),
      expect: () => [const KycLoading(), const KycMergeProcessing()],
    );

    blocTest<KycCubit, KycState>(
      'emits KycPending(ident) when API reports processStatus=PendingReview and ident is the required pending step',
      setUp: () {
        when(() => kycService.getKycStatus()).thenAnswer(
          (_) async => _kycStatus(
            level: KycLevel.level50,
            processStatus: KycProcessStatus.pendingReview,
            steps: [
              _step(KycStepName.ident, status: KycStepStatus.inReview, isRequired: true),
            ],
          ),
        );
        when(() => kycService.getUser()).thenAnswer((_) async => _user());
      },
      build: buildCubit,
      act: (cubit) => cubit.checkKyc(),
      expect: () => [const KycLoading(), const KycPending(KycStep.ident)],
    );

    // PendingReview is authoritative. The cubit must NEVER collapse this
    // branch to `KycCompleted` — regression: an API review-pending status
    // must not route the user to the dashboard.
    blocTest<KycCubit, KycState>(
      'emits KycUnsupportedStepFailure (not Completed) when PendingReview has no required step at all',
      setUp: () {
        when(() => kycService.getKycStatus()).thenAnswer(
          (_) async => _kycStatus(
            level: KycLevel.level50,
            processStatus: KycProcessStatus.pendingReview,
            steps: [
              _step(KycStepName.ident, status: KycStepStatus.completed),
            ],
          ),
        );
        when(() => kycService.getUser()).thenAnswer((_) async => _user());
      },
      build: buildCubit,
      act: (cubit) => cubit.checkKyc(),
      expect: () => [
        const KycLoading(),
        const KycUnsupportedStepFailure(null),
      ],
    );

    // PendingReview + a required step the app cannot render (e.g.
    // additionalDocuments, residencePermit, statutes — all absent from
    // `_mapStepName`). Must surface an explicit failure with the step name,
    // never `KycCompleted`.
    blocTest<KycCubit, KycState>(
      'emits KycUnsupportedStepFailure(step) when PendingReview required step is unmapped',
      setUp: () {
        when(() => kycService.getKycStatus()).thenAnswer(
          (_) async => _kycStatus(
            level: KycLevel.level50,
            processStatus: KycProcessStatus.pendingReview,
            steps: [
              _step(
                KycStepName.additionalDocuments,
                status: KycStepStatus.inReview,
                isRequired: true,
              ),
            ],
          ),
        );
        when(() => kycService.getUser()).thenAnswer((_) async => _user());
      },
      build: buildCubit,
      act: (cubit) => cubit.checkKyc(),
      expect: () => [
        const KycLoading(),
        const KycUnsupportedStepFailure(KycStepName.additionalDocuments),
      ],
    );

    // Registration normally satisfies PersonalData without the user seeing it. It re-opens when
    // identification rejects the submitted data, and until the page existed that landed the user on
    // the unsupported-step failure screen with no way to correct anything.
    blocTest<KycCubit, KycState>(
      'routes PersonalData to its own step instead of the unsupported-step failure',
      setUp: () {
        when(() => kycService.getKycStatus()).thenAnswer(
          (_) async => _kycStatus(
            level: KycLevel.level20,
            processStatus: KycProcessStatus.pendingReview,
            steps: [
              _step(
                KycStepName.personalData,
                status: KycStepStatus.inProgress,
                isRequired: true,
              ),
            ],
          ),
        );
        when(() => kycService.getUser()).thenAnswer((_) async => _user());
      },
      build: buildCubit,
      act: (cubit) => cubit.checkKyc(),
      expect: () => [
        const KycLoading(),
        const KycPending(KycStep.personalData),
      ],
    );

    blocTest<KycCubit, KycState>(
      'emits KycPending(dfxApproval) when dfxApproval is the only required step in PendingReview',
      setUp: () {
        when(() => kycService.getKycStatus()).thenAnswer(
          (_) async => _kycStatus(
            level: KycLevel.level50,
            processStatus: KycProcessStatus.pendingReview,
            steps: [
              _step(KycStepName.dfxApproval, status: KycStepStatus.inReview, isRequired: true),
            ],
          ),
        );
        when(() => kycService.getUser()).thenAnswer((_) async => _user());
      },
      build: buildCubit,
      act: (cubit) => cubit.checkKyc(),
      expect: () => [const KycLoading(), const KycPending(KycStep.dfxApproval)],
    );

    blocTest<KycCubit, KycState>(
      'calls _continueKyc and emits KycSuccess(currentStep) when processStatus=InProgress',
      setUp: () {
        when(() => kycService.getKycStatus()).thenAnswer(
          (_) async => _kycStatus(
            level: KycLevel.level20,
            processStatus: KycProcessStatus.inProgress,
          ),
        );
        when(() => kycService.getUser()).thenAnswer((_) async => _user());
        when(() => kycService.continueKyc()).thenAnswer(
          (_) async => _session(
            level: KycLevel.level20,
            steps: const [],
            currentStep: _currentStep(
              KycStepName.ident,
              url: 'https://example.com/ident',
            ),
          ),
        );
      },
      build: buildCubit,
      act: (cubit) => cubit.checkKyc(),
      expect: () => [
        const KycLoading(),
        const KycSuccess(
          currentStep: KycStep.ident,
          urlOrToken: 'https://example.com/ident',
        ),
      ],
    );

    blocTest<KycCubit, KycState>(
      'emits KycUnsupportedStepFailure when _continueKyc currentStep has no UI mapping',
      setUp: () {
        when(() => kycService.getKycStatus()).thenAnswer(
          (_) async => _kycStatus(
            level: KycLevel.level20,
            processStatus: KycProcessStatus.inProgress,
          ),
        );
        when(() => kycService.getUser()).thenAnswer((_) async => _user());
        when(() => kycService.continueKyc()).thenAnswer(
          (_) async => _session(
            level: KycLevel.level20,
            steps: const [],
            // personalData used to stand in for "unmapped" here; it has its own page now, so this
            // needs a name that is still absent from `_mapStepName`.
            currentStep: _currentStep(KycStepName.statutes),
          ),
        );
      },
      build: buildCubit,
      act: (cubit) => cubit.checkKyc(),
      expect: () => [
        const KycLoading(),
        const KycUnsupportedStepFailure(KycStepName.statutes),
      ],
    );

    // V45 follow-up: when the API answers `inProgress` but does not name a
    // `currentStep` we surface an explicit failure instead of throwing a
    // `StateError` from a `firstWhere`-on-empty (which used to leak as raw
    // stack-trace text into the user-facing i18n message).
    blocTest<KycCubit, KycState>(
      'emits KycUnsupportedStepFailure(null) when _continueKyc returns no currentStep',
      setUp: () {
        when(() => kycService.getKycStatus()).thenAnswer(
          (_) async => _kycStatus(
            level: KycLevel.level20,
            processStatus: KycProcessStatus.inProgress,
          ),
        );
        when(() => kycService.getUser()).thenAnswer((_) async => _user());
        when(() => kycService.continueKyc()).thenAnswer(
          (_) async => _session(
            level: KycLevel.level20,
            steps: const [],
          ),
        );
      },
      build: buildCubit,
      act: (cubit) => cubit.checkKyc(),
      expect: () => [
        const KycLoading(),
        const KycUnsupportedStepFailure(null),
      ],
    );

    blocTest<KycCubit, KycState>(
      'emits KycFailure when API reports processStatus=Failed (KYC terminated)',
      setUp: () {
        when(() => kycService.getKycStatus()).thenAnswer(
          (_) async => _kycStatus(
            level: KycLevel.terminated,
            processStatus: KycProcessStatus.failed,
          ),
        );
        when(() => kycService.getUser()).thenAnswer((_) async => _user());
      },
      build: buildCubit,
      act: (cubit) => cubit.checkKyc(),
      expect: () => [const KycLoading(), isA<KycFailure>()],
    );

    // `KycLevel.terminated` is internally mapped to value -10, which lands in
    // the `level < 10` auto-register branch before reaching the
    // `processStatus.failed` switch. A real `Failed` from the backend ships
    // with a non-negative level (the user got far enough for compliance to
    // terminate them). Pin that branch explicitly.
    blocTest<KycCubit, KycState>(
      'emits "KYC terminated" KycFailure when level>=10 and processStatus=Failed',
      setUp: () {
        when(() => kycService.getKycStatus()).thenAnswer(
          (_) async => _kycStatus(
            level: KycLevel.level20,
            processStatus: KycProcessStatus.failed,
          ),
        );
        when(() => kycService.getUser()).thenAnswer((_) async => _user());
      },
      build: buildCubit,
      act: (cubit) => cubit.checkKyc(),
      verify: (cubit) {
        final state = cubit.state as KycFailure;
        expect(state.message, 'KYC terminated');
      },
      expect: () => [
        const KycLoading(),
        const KycFailure('KYC terminated'),
      ],
    );

    // Previously a returning user was always re-shown the disclaimer (the flag
    // reset on every cubit construction). Now the server drives the gate: an
    // already-accepted returning user (`allAccepted:true`, the default stub)
    // skips the disclaimer entirely and lands on completed.
    blocTest<KycCubit, KycState>(
      'returning user with all agreements accepted skips the disclaimer and lands on completed',
      setUp: () {
        when(() => kycService.getKycStatus()).thenAnswer(
          (_) async => _kycStatus(
            level: KycLevel.level50,
            processStatus: KycProcessStatus.completed,
          ),
        );
        when(() => kycService.getUser()).thenAnswer((_) async => _user());
      },
      build: buildCubit,
      act: (cubit) => cubit.checkKyc(),
      expect: () => [
        const KycLoading(),
        const KycCompleted(),
      ],
    );

    blocTest<KycCubit, KycState>(
      'does NOT route to twoFa on 403 without TFA_REQUIRED body code',
      setUp: () {
        when(() => kycService.getKycStatus()).thenThrow(
          const ApiException(statusCode: 403, code: 'FORBIDDEN', message: ''),
        );
        when(() => kycService.getUser()).thenAnswer((_) async => _user());
      },
      build: buildCubit,
      act: (cubit) => cubit.checkKyc(),
      expect: () => [
        const KycLoading(),
        isA<KycFailure>(),
      ],
    );

    blocTest<KycCubit, KycState>(
      "routes to twoFa step on ApiException(code: 'TFA_REQUIRED'), regardless of HTTP status",
      setUp: () {
        when(() => kycService.getKycStatus()).thenThrow(
          const ApiException(statusCode: 400, code: 'TFA_REQUIRED', message: ''),
        );
        when(() => kycService.getUser()).thenAnswer((_) async => _user());
      },
      build: buildCubit,
      act: (cubit) => cubit.checkKyc(),
      expect: () => [
        const KycLoading(),
        const KycSuccess(currentStep: KycStep.twoFa),
      ],
    );

    blocTest<KycCubit, KycState>(
      "routes to twoFa step on ApiException(statusCode: 403, code: 'TFA_REQUIRED')",
      setUp: () {
        when(() => kycService.getKycStatus()).thenThrow(
          const ApiException(statusCode: 403, code: 'TFA_REQUIRED', message: ''),
        );
        when(() => kycService.getUser()).thenAnswer((_) async => _user());
      },
      build: buildCubit,
      act: (cubit) => cubit.checkKyc(),
      expect: () => [
        const KycLoading(),
        const KycSuccess(currentStep: KycStep.twoFa),
      ],
    );

    blocTest<KycCubit, KycState>(
      'emits KycFailure on unrelated ApiException',
      setUp: () {
        when(() => kycService.getKycStatus()).thenThrow(
          const ApiException(statusCode: 500, code: 'SERVER_ERROR', message: 'boom'),
        );
        when(() => kycService.getUser()).thenAnswer((_) async => _user());
      },
      build: buildCubit,
      act: (cubit) => cubit.checkKyc(),
      expect: () => [
        const KycLoading(),
        isA<KycFailure>(),
      ],
    );

    blocTest<KycCubit, KycState>(
      'emits KycFailure on generic exception',
      setUp: () {
        when(() => kycService.getKycStatus()).thenThrow(Exception('network down'));
        when(() => kycService.getUser()).thenAnswer((_) async => _user());
      },
      build: buildCubit,
      act: (cubit) => cubit.checkKyc(),
      expect: () => [
        const KycLoading(),
        isA<KycFailure>(),
      ],
    );
  });

  // Per-arm coverage of `_mapStepName`: line coverage marks every switch-
  // expression arm as hit the moment the switch is evaluated, so it cannot
  // prove an individual arm maps its input to the right step. Drive
  // `_continueKyc` with each step name and assert the resulting step — the
  // assertion, not the line hit, pins the arm. (`ident` and `dfxApproval` are
  // already exercised by the InProgress / PendingReview tests above.)
  group('$KycCubit _mapStepName routing arms', () {
    void expectStepMapsTo(KycStepName name, KycStep expected) {
      blocTest<KycCubit, KycState>(
        '$name maps to $expected',
        setUp: () {
          when(() => kycService.getKycStatus()).thenAnswer(
            (_) async => _kycStatus(
              level: KycLevel.level20,
              processStatus: KycProcessStatus.inProgress,
            ),
          );
          when(() => kycService.getUser()).thenAnswer((_) async => _user());
          when(() => kycService.continueKyc()).thenAnswer(
            (_) async => _session(
              level: KycLevel.level20,
              steps: const [],
              currentStep: _currentStep(name, url: 'https://example.com/step'),
            ),
          );
        },
        build: buildCubit,
        act: (cubit) => cubit.checkKyc(),
        expect: () => [
          const KycLoading(),
          KycSuccess(currentStep: expected, urlOrToken: 'https://example.com/step'),
        ],
      );
    }

    expectStepMapsTo(KycStepName.contactData, KycStep.registration);
    expectStepMapsTo(KycStepName.nationalityData, KycStep.nationality);
    expectStepMapsTo(KycStepName.financialData, KycStep.financialData);
  });

  group('$KycCubit timeout & generation handling', () {
    test(
      'a late response from a timed-out call does NOT overwrite the fresh state of a retry (regression for #315 / #317)',
      () async {
        final call1Completer = Completer<KycLevelDto>();
        var firstCall = true;
        when(() => kycService.getKycStatus()).thenAnswer((_) {
          if (firstCall) {
            firstCall = false;
            return call1Completer.future;
          }
          return Future.value(
            _kycStatus(level: KycLevel.level50, processStatus: KycProcessStatus.completed),
          );
        });
        when(() => kycService.getUser()).thenAnswer((_) async => _user());

        // Server reports all agreements accepted (default stub), so the
        // disclaimer gate passes and both runs reach the completed state.
        final cubit = KycCubit(kycService, registrationService, legalService, appStore);

        final states = <KycState>[];
        final sub = cubit.stream.listen(states.add);

        final call1Future = cubit.checkKyc();

        await Future<void>.delayed(Duration.zero);

        await cubit.checkKyc();

        call1Completer.complete(
          _kycStatus(level: KycLevel.level50, processStatus: KycProcessStatus.completed),
        );
        await call1Future;
        await Future<void>.delayed(Duration.zero);

        await sub.cancel();
        await cubit.close();

        expect(states, [const KycLoading(), const KycCompleted()]);
        expect(cubit.state, const KycCompleted());
      },
    );

    blocTest<KycCubit, KycState>(
      'emits KycFailure when a backend call throws TimeoutException',
      setUp: () {
        when(() => kycService.getKycStatus()).thenAnswer(
          (_) async => throw TimeoutException('backend slow'),
        );
        when(() => kycService.getUser()).thenAnswer((_) async => _user());
      },
      build: buildCubit,
      act: (cubit) => cubit.checkKyc(),
      expect: () => [const KycLoading(), isA<KycFailure>()],
    );

    // The outer 30s timeout on `_runCheckKyc` is the watchdog that surfaces
    // a "did not respond in time" failure when the backend never resolves —
    // distinct from the inner `TimeoutException`-from-the-service path
    // above. fake_async lets us advance virtual time past the 30s budget
    // without a wallclock sleep.
    test(
      'emits "did not respond in time" KycFailure when _runCheckKyc exceeds the 30s outer timeout',
      () {
        fakeAsync((async) {
          when(() => kycService.getKycStatus()).thenAnswer((_) => Completer<KycLevelDto>().future);
          when(() => kycService.getUser()).thenAnswer((_) async => _user());

          final cubit = buildCubit();
          final states = <KycState>[];
          final sub = cubit.stream.listen(states.add);

          unawaited(cubit.checkKyc());
          async.elapse(const Duration(seconds: 31));

          expect(states, [
            const KycLoading(),
            const KycFailure('KYC backend did not respond in time'),
          ]);

          sub.cancel();
          cubit.close();
        });
      },
    );
  });

  group('$KycCubit context forwarding', () {
    blocTest<KycCubit, KycState>(
      'passes context to getKycStatus and continueKyc when provided',
      setUp: () {
        when(() => kycService.getKycStatus(context: 'RealunitBuy')).thenAnswer(
          (_) async => _kycStatus(
            level: KycLevel.level20,
            processStatus: KycProcessStatus.inProgress,
          ),
        );
        when(() => kycService.getUser()).thenAnswer((_) async => _user());
        when(() => kycService.continueKyc(context: 'RealunitBuy')).thenAnswer(
          (_) async => _session(
            level: KycLevel.level20,
            steps: const [],
            currentStep: _currentStep(
              KycStepName.ident,
              url: 'https://example.com/ident',
            ),
          ),
        );
      },
      build: buildCubit,
      act: (cubit) => cubit.checkKyc(context: 'RealunitBuy'),
      expect: () => [
        const KycLoading(),
        const KycSuccess(
          currentStep: KycStep.ident,
          urlOrToken: 'https://example.com/ident',
        ),
      ],
      verify: (_) {
        verify(() => kycService.getKycStatus(context: 'RealunitBuy')).called(1);
        verify(() => kycService.continueKyc(context: 'RealunitBuy')).called(1);
      },
    );

    blocTest<KycCubit, KycState>(
      'context is sticky — subsequent checkKyc() without context reuses the stored one',
      setUp: () {
        when(() => kycService.getKycStatus(context: 'RealunitBuy')).thenAnswer(
          (_) async => _kycStatus(
            level: KycLevel.level50,
            processStatus: KycProcessStatus.completed,
          ),
        );
        when(() => kycService.getUser()).thenAnswer((_) async => _user());
      },
      build: buildCubit,
      act: (cubit) async {
        // First call sets the context.
        await cubit.checkKyc(context: 'RealunitBuy');
        // Second call omits context — should reuse 'RealunitBuy'.
        await cubit.checkKyc();
      },
      verify: (_) {
        verify(() => kycService.getKycStatus(context: 'RealunitBuy')).called(2);
      },
      expect: () => [
        const KycLoading(),
        const KycCompleted(),
        const KycLoading(),
        const KycCompleted(),
      ],
    );
  });

  group('$KycCubit acceptLegalDisclaimer', () {
    // Happy path: the user accepts on the disclaimer page. `acceptLegalDisclaimer`
    // records acceptance server-side (`acceptLegal` with the outstanding
    // agreements), then re-runs `checkKyc()`; the server now reports
    // `allAccepted`, so the gate passes and the API drives the next routing.
    blocTest<KycCubit, KycState>(
      'records acceptance server-side, then re-checks and lets the API drive the next routing decision',
      setUp: () {
        when(() => kycService.getKycStatus()).thenAnswer(
          (_) async => _kycStatus(
            level: KycLevel.level50,
            processStatus: KycProcessStatus.completed,
          ),
        );
        when(() => kycService.getUser()).thenAnswer((_) async => _user());
        // Outstanding before acceptance, all-accepted afterwards — mirrors the
        // server stamping the version on PUT.
        var accepted = false;
        when(() => legalService.getLegalInfo()).thenAnswer(
          (_) async => accepted ? _legalInfo() : _legalInfo(allAccepted: false),
        );
        when(() => legalService.acceptLegal(any())).thenAnswer((_) async {
          accepted = true;
          return _legalInfo();
        });
      },
      build: buildCubit,
      act: (cubit) async {
        await cubit.checkKyc(); // outstanding -> disclaimer
        await cubit.acceptLegalDisclaimer(); // records + re-checks -> completed
      },
      expect: () => [
        const KycLoading(),
        const KycSuccess(currentStep: KycStep.legalDisclaimer),
        const KycLoading(),
        const KycCompleted(),
      ],
      verify: (_) {
        verify(() => legalService.acceptLegal(any())).called(1);
      },
    );

    // Pre-rollout path: both the acceptance PUT and the subsequent GET return
    // 404 (endpoint not deployed). The local per-session flag (set inside
    // `acceptLegalDisclaimer`) carries the session so the re-check passes the
    // gate — the tolerated 404 never surfaces to the user.
    blocTest<KycCubit, KycState>(
      'falls back to the local session flag when the endpoint returns 404',
      setUp: () {
        when(() => kycService.getKycStatus()).thenAnswer(
          (_) async => _kycStatus(
            level: KycLevel.level50,
            processStatus: KycProcessStatus.completed,
          ),
        );
        when(() => kycService.getUser()).thenAnswer((_) async => _user());
        when(() => legalService.getLegalInfo()).thenThrow(
          const ApiException(statusCode: 404, code: 'NOT_FOUND', message: ''),
        );
        when(() => legalService.acceptLegal(any())).thenThrow(
          const ApiException(statusCode: 404, code: 'NOT_FOUND', message: ''),
        );
      },
      build: buildCubit,
      act: (cubit) async {
        await cubit.checkKyc(); // gate falls back to local flag (false) -> disclaimer
        await cubit.acceptLegalDisclaimer(); // sets local flag -> re-check passes -> completed
      },
      expect: () => [
        const KycLoading(),
        const KycSuccess(currentStep: KycStep.legalDisclaimer),
        const KycLoading(),
        const KycCompleted(),
      ],
    );

    // Fail closed: a non-404 PUT failure (endpoint live but the write errors)
    // surfaces as KycFailure instead of being silently swallowed into a
    // re-prompt loop.
    blocTest<KycCubit, KycState>(
      'emits KycFailure when acceptLegal fails with a non-404 error',
      setUp: () {
        when(() => kycService.getKycStatus()).thenAnswer(
          (_) async => _kycStatus(
            level: KycLevel.level50,
            processStatus: KycProcessStatus.completed,
          ),
        );
        when(() => kycService.getUser()).thenAnswer((_) async => _user());
        when(() => legalService.acceptLegal(any())).thenThrow(
          const ApiException(statusCode: 500, code: 'SERVER_ERROR', message: 'boom'),
        );
      },
      build: buildCubit,
      act: (cubit) => cubit.acceptLegalDisclaimer(),
      expect: () => [isA<KycFailure>()],
    );

    // A non-ApiException failure (network/parse error) also fails closed via the
    // generic catch, surfacing as KycFailure rather than being swallowed.
    blocTest<KycCubit, KycState>(
      'emits KycFailure when acceptLegal throws a non-ApiException error',
      setUp: () {
        when(() => kycService.getKycStatus()).thenAnswer(
          (_) async => _kycStatus(
            level: KycLevel.level50,
            processStatus: KycProcessStatus.completed,
          ),
        );
        when(() => kycService.getUser()).thenAnswer((_) async => _user());
        when(() => legalService.acceptLegal(any())).thenThrow(Exception('boom'));
      },
      build: buildCubit,
      act: (cubit) => cubit.acceptLegalDisclaimer(),
      expect: () => [isA<KycFailure>()],
    );
  });
}
