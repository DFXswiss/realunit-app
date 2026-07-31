import 'package:flutter/widgets.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/packages/hardware_wallet/bitbox.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_kyc_service.dart';
import 'package:realunit_wallet/packages/service/dfx/models/kyc/dto/kyc_level_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/kyc/dto/kyc_session_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/kyc/dto/kyc_step_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/kyc/kyc_level.dart';
import 'package:realunit_wallet/packages/service/dfx/models/legal/dto/real_unit_legal_info_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/user/dto/user_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/wallet/real_unit_registration_info_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/wallet/real_unit_registration_state.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_legal_service.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_registration_service.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';
import 'package:realunit_wallet/screens/kyc/cubits/kyc/kyc_cubit.dart';
import 'package:realunit_wallet/screens/kyc/kyc_page_manager.dart';
import 'package:realunit_wallet/screens/kyc/subpages/kyc_failure_page.dart';
import 'package:realunit_wallet/screens/kyc/subpages/kyc_manual_review_page.dart';
import 'package:realunit_wallet/screens/kyc/subpages/kyc_pending_page.dart';
import 'package:realunit_wallet/screens/legal/legal_disclaimer_page.dart';

import '../../helper/helper.dart';

class _MockDfxKycService extends Mock implements DfxKycService {}

class _MockRealUnitRegistrationService extends Mock implements RealUnitRegistrationService {}

class _MockRealUnitLegalService extends Mock implements RealUnitLegalService {}

class _MockAppStore extends Mock implements AppStore {}

class _MockAWallet extends Mock implements AWallet {}

class _MockKycCubit extends MockCubit<KycState> implements KycCubit {}

class _MockBitboxService extends Mock implements BitboxService {}

UserKycDto _kycHeader({KycLevel level = KycLevel.level0}) =>
    UserKycDto(hash: 'h', level: level, dataComplete: false);

UserDto _user({String? mail = 'test@example.com'}) => UserDto(mail: mail, kyc: _kycHeader());

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
}) => KycStepSessionDto(
  session: KycSessionInfoDto(url: url, type: urlType),
  name: name,
  status: status,
  sequenceNumber: 0,
  isCurrent: true,
);

void main() {
  late _MockDfxKycService kycService;
  late _MockRealUnitRegistrationService registrationService;
  late _MockRealUnitLegalService legalService;
  late _MockAppStore appStore;
  late _MockAWallet wallet;

  setUp(() {
    kycService = _MockDfxKycService();
    registrationService = _MockRealUnitRegistrationService();
    legalService = _MockRealUnitLegalService();
    appStore = _MockAppStore();
    wallet = _MockAWallet();
    when(() => appStore.wallet).thenReturn(wallet);
    when(() => wallet.walletType).thenReturn(WalletType.software);
    when(() => registrationService.getRegistrationInfo()).thenAnswer(
      (_) async => RealUnitRegistrationInfoDto(
        state: RealUnitRegistrationState.alreadyRegistered,
      ),
    );
    // Default: server reports all legal agreements accepted, so the disclaimer
    // gate passes and tests exercise downstream routing.
    when(() => legalService.getLegalInfo()).thenAnswer(
      (_) async => const RealUnitLegalInfoDto(agreements: [], allAccepted: true),
    );
  });

  // An in-progress `dfxApproval` step used to land on a blank white Scaffold
  // (the `(_) => const Scaffold()` fallback in KycViewManager). It must render
  // the existing pending page instead.
  testWidgets(
    'KycSuccess(dfxApproval) renders KycPendingPage, not a blank Scaffold',
    (tester) async {
      when(() => kycService.getKycStatus()).thenAnswer(
        (_) async => _kycStatus(
          level: KycLevel.level50,
          processStatus: KycProcessStatus.inProgress,
        ),
      );
      when(() => kycService.getUser()).thenAnswer((_) async => _user());
      when(() => kycService.continueKyc()).thenAnswer(
        (_) async => _session(
          level: KycLevel.level50,
          steps: const [],
          currentStep: _currentStep(KycStepName.dfxApproval),
        ),
      );

      final bitboxService = _MockBitboxService();
      when(() => bitboxService.refusesRegistrationSignature).thenReturn(false);
      when(() => bitboxService.firmwareVersion).thenReturn(null);
      final cubit =
          KycCubit(kycService, registrationService, legalService, appStore, bitboxService);
      await tester.pumpApp(
        BlocProvider<KycCubit>.value(
          value: cubit,
          child: const KycViewManager(),
        ),
      );

      // Server reports all agreements accepted (default stub), so the disclaimer
      // gate passes and the cubit reaches the dfxApproval routing under test.
      await cubit.checkKyc();
      await tester.pumpAndSettle();

      // Sanity: the cubit really reached the bug-triggering state.
      expect(cubit.state, isA<KycSuccess>());
      expect((cubit.state as KycSuccess).currentStep, KycStep.dfxApproval);

      // Regression assertion: the pending page renders (not a blank screen).
      expect(find.byType(KycPendingPage), findsOneWidget);

      await cubit.close();
    },
  );

  Widget viewWithState(KycCubit cubit) => BlocProvider<KycCubit>.value(
    value: cubit,
    child: const KycViewManager(),
  );

  // Exercises the KycPageManager DI wrapper itself (not just KycViewManager):
  // the create closure must build a KycCubit from getIt and kick off checkKyc
  // with the passed context.
  testWidgets(
    'KycPageManager builds the KycCubit from getIt and runs checkKyc with the context',
    (tester) async {
      final getIt = GetIt.instance;
      getIt.registerSingleton<DfxKycService>(kycService);
      getIt.registerSingleton<RealUnitRegistrationService>(registrationService);
      getIt.registerSingleton<RealUnitLegalService>(legalService);
      getIt.registerSingleton<AppStore>(appStore);
      final bitboxService = _MockBitboxService();
      when(() => bitboxService.refusesRegistrationSignature).thenReturn(false);
      when(() => bitboxService.firmwareVersion).thenReturn(null);
      getIt.registerSingleton<BitboxService>(bitboxService);
      addTearDown(() async => getIt.reset());

      // Fail fast so the created cubit settles into KycFailure without leaving a
      // pending 30s timeout timer — the assertion is on the DI wiring, not the
      // resulting state.
      when(() => kycService.getKycStatus(context: 'RealunitBuy')).thenThrow(
        Exception('boom'),
      );
      when(() => kycService.getUser()).thenAnswer((_) async => _user());

      // Non-const construction so the constructor runs at runtime instead of
      // folding to a compile-time constant.
      // ignore: prefer_const_constructors
      await tester.pumpApp(KycPageManager(kycContext: 'RealunitBuy'));
      await tester.pumpAndSettle();

      // Proves both halves of the wiring: the cubit was built from getIt (else
      // this mock is never reached) and checkKyc forwarded the context.
      verify(() => kycService.getKycStatus(context: 'RealunitBuy')).called(1);
      expect(find.byType(KycFailurePage), findsOneWidget);
    },
  );

  // The KycUnsupportedStepFailure arm renders a KycFailurePage with the
  // unsupported step name — a state no page test drives directly.
  testWidgets(
    'KycViewManager renders KycFailurePage for KycUnsupportedStepFailure',
    (tester) async {
      final cubit = _MockKycCubit();
      when(() => cubit.state).thenReturn(
        const KycUnsupportedStepFailure(KycStepName.personalData),
      );

      await tester.pumpApp(viewWithState(cubit));

      expect(find.byType(KycFailurePage), findsOneWidget);
    },
  );

  // The KycManualReview arm renders the dedicated registration-under-review
  // waiting page — a state no page test drives directly.
  testWidgets(
    'KycViewManager renders KycManualReviewPage for KycManualReview',
    (tester) async {
      final cubit = _MockKycCubit();
      when(() => cubit.state).thenReturn(const KycManualReview());

      await tester.pumpApp(viewWithState(cubit));

      expect(find.byType(KycManualReviewPage), findsOneWidget);
    },
  );

  // The legalDisclaimer arm wires LegalDisclaimerPage.onCompleted to
  // acceptLegalDisclaimer (which records acceptance server-side and re-checks);
  // drive that callback directly.
  testWidgets(
    'KycViewManager legalDisclaimer onCompleted records acceptance',
    (tester) async {
      final cubit = _MockKycCubit();
      when(() => cubit.state).thenReturn(
        const KycSuccess(currentStep: KycStep.legalDisclaimer),
      );
      when(() => cubit.acceptLegalDisclaimer()).thenAnswer((_) async {});

      await tester.pumpApp(viewWithState(cubit));
      await tester.pumpAndSettle();

      // Drive the disclaimer's completion callback exactly as the page would on
      // acceptance, without exercising the disclaimer UI itself.
      final page = tester.widget<LegalDisclaimerPage>(find.byType(LegalDisclaimerPage));
      page.onCompleted!();

      verify(() => cubit.acceptLegalDisclaimer()).called(1);
    },
  );
}
