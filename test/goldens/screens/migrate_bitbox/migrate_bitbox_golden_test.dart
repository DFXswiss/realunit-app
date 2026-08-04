import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/models/balance.dart';
import 'package:realunit_wallet/packages/config/api_config.dart';
import 'package:realunit_wallet/packages/repository/balance_repository.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/transfer/dto/real_unit_transfer_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/transfer/dto/real_unit_transfer_payment_info_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/registration/kyc/kyc_personal_data.dart';
import 'package:realunit_wallet/packages/service/dfx/models/user/dto/real_unit_user_data_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_registration_service.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_transfer_service.dart';
import 'package:realunit_wallet/packages/utils/default_assets.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';
import 'package:realunit_wallet/packages/wallet/wallet_account.dart';
import 'package:realunit_wallet/screens/migrate_bitbox/cubits/migrate_bitbox/migrate_bitbox_cubit.dart';
import 'package:realunit_wallet/screens/migrate_bitbox/migrate_bitbox_page.dart';
import 'package:realunit_wallet/screens/migrate_bitbox/widgets/migrate_result_views.dart';
import 'package:realunit_wallet/screens/migrate_bitbox/widgets/migrate_transfer_view.dart';
import 'package:realunit_wallet/screens/send/cubits/send_process/send_process_cubit.dart';

import '../../../helper/helper.dart';

class _MockMigrateBitboxCubit extends MockCubit<MigrateBitboxState>
    implements MigrateBitboxCubit {}

class _MockApiConfig extends Mock implements ApiConfig {}

class _MockAppStore extends Mock implements AppStore {}

class _MockBalanceRepository extends Mock implements BalanceRepository {}

class _MockRegistrationService extends Mock implements RealUnitRegistrationService {}

class _MockSoftwareWallet extends Mock implements SoftwareWallet {}

class _MockTransferService extends Mock implements RealUnitTransferService {}

class _MockWalletAccount extends Mock implements AWalletAccount {}

const _softwareAddress = '0x0000000000000000000000000000000000000001';
const _bitboxAddress = '0x1234567890abcdef1234567890abcdef12345678';

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

Balance _balance(int shares) => Balance(
  chainId: realUnitAsset.chainId,
  contractAddress: realUnitAsset.address,
  walletAddress: _softwareAddress,
  balance: BigInt.from(shares),
  asset: realUnitAsset,
);

void main() {
  late _MockMigrateBitboxCubit migrateCubit;
  late _MockWalletAccount draftAccount;

  setUpAll(() {
    registerFallbackValue(_balance(0));
    registerFallbackValue(
      const RealUnitTransferDto(toAddress: _bitboxAddress, amount: 1),
    );

    final apiConfig = _MockApiConfig();
    final appStore = _MockAppStore();
    final balanceRepository = _MockBalanceRepository();
    final registrationService = _MockRegistrationService();
    final softwareWallet = _MockSoftwareWallet();
    final transferService = _MockTransferService();
    final pendingPrepare = Completer<RealUnitTransferPaymentInfoDto>();

    when(() => apiConfig.asset).thenReturn(realUnitAsset);
    when(() => appStore.apiConfig).thenReturn(apiConfig);
    when(() => appStore.primaryAddress).thenReturn(_softwareAddress);
    when(() => appStore.wallet).thenReturn(softwareWallet);
    when(() => softwareWallet.walletType).thenReturn(WalletType.software);
    when(
      () => balanceRepository.watchBalance(any()),
    ).thenAnswer((_) => Stream.value(_balance(42)));
    when(
      () => transferService.prepareTransfer(any()),
    ).thenAnswer((_) => pendingPrepare.future);

    GetIt.instance.registerSingleton<AppStore>(appStore);
    GetIt.instance.registerSingleton<BalanceRepository>(balanceRepository);
    GetIt.instance.registerSingleton<RealUnitRegistrationService>(
      registrationService,
    );
    GetIt.instance.registerSingleton<RealUnitTransferService>(transferService);
  });

  tearDownAll(() async => GetIt.instance.reset());

  setUp(() {
    migrateCubit = _MockMigrateBitboxCubit();
    draftAccount = _MockWalletAccount();
    when(() => migrateCubit.state).thenReturn(const MigrateBitboxIntro());
    when(() => migrateCubit.draftAccount).thenReturn(draftAccount);
    when(() => migrateCubit.linkedJwt).thenReturn('linked-jwt');
  });

  Widget buildManager(MigrateBitboxState state) {
    when(() => migrateCubit.state).thenReturn(state);
    whenListen(
      migrateCubit,
      const Stream<MigrateBitboxState>.empty(),
      initialState: state,
    );
    return wrapForGolden(
      BlocProvider<MigrateBitboxCubit>.value(
        value: migrateCubit,
        child: const MigrateBitboxViewManager(),
      ),
    );
  }

  group('$MigrateBitboxViewManager', () {
    goldenTest(
      'intro with the current REALU balance',
      fileName: 'migrate_bitbox_intro',
      constraints: phoneConstraints,
      builder: () => buildManager(const MigrateBitboxIntro()),
    );

    goldenTest(
      'registration ready with user data and BitBox address',
      fileName: 'migrate_bitbox_register_ready',
      constraints: phoneConstraints,
      builder: () => buildManager(
        const MigrateBitboxRegisterReady(_userData, _bitboxAddress),
      ),
    );

    goldenTest(
      'transfer summary with source, destination, and amount',
      fileName: 'migrate_bitbox_transfer_ready',
      constraints: phoneConstraints,
      builder: () => buildManager(
        const MigrateBitboxTransferReady(
          fromAddress: _softwareAddress,
          toAddress: _bitboxAddress,
          amount: 42,
        ),
      ),
    );

    goldenTest(
      'transfer preparation in progress',
      fileName: 'migrate_bitbox_transferring',
      constraints: phoneConstraints,
      pumpBeforeTest: pumpOnce,
      builder: () => buildManager(
        const MigrateBitboxTransferring(
          toAddress: _bitboxAddress,
          amount: 42,
        ),
      ),
    );

    goldenTest(
      'settling in progress',
      fileName: 'migrate_bitbox_settling',
      constraints: phoneConstraints,
      pumpBeforeTest: pumpOnce,
      builder: () => buildManager(const MigrateBitboxSettling()),
    );
  });

  group('standalone migration result views', () {
    goldenTest(
      'registration pending manual review',
      fileName: 'migrate_bitbox_registration_pending',
      constraints: phoneConstraints,
      builder: () => wrapForGolden(
        const MigrateBitboxRegistrationPendingPage(),
      ),
    );

    goldenTest(
      'retryable transfer failure with unavailable gas funding',
      fileName: 'migrate_bitbox_transfer_failure',
      constraints: phoneConstraints,
      builder: () => wrapForGolden(
        Builder(
          builder: (context) => Scaffold(
            appBar: AppBar(title: Text(S.of(context).migrateBitbox)),
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SafeArea(
                child: MigrateTransferFailureView(
                  reason: SendProcessFailureReason.gasFundingUnavailable,
                  canRetry: true,
                  onRetry: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    goldenTest(
      'settling timeout',
      fileName: 'migrate_bitbox_settling_timeout',
      constraints: phoneConstraints,
      builder: () => wrapForGolden(
        const MigrateBitboxSettlingTimeoutPage(),
      ),
    );

    goldenTest(
      'successful migration',
      fileName: 'migrate_bitbox_success',
      constraints: phoneConstraints,
      builder: () => wrapForGolden(const MigrateBitboxSuccessPage()),
    );

    goldenTest(
      'retryable generic migration failure',
      fileName: 'migrate_bitbox_failure_retryable',
      constraints: phoneConstraints,
      builder: () => wrapForGolden(
        const MigrateBitboxFailurePage(
          reason: MigrateBitboxFailureReason.generic,
          canRetry: true,
        ),
      ),
    );

    goldenTest(
      'already-linked migration failure without retry',
      fileName: 'migrate_bitbox_failure_already_linked',
      constraints: phoneConstraints,
      builder: () => wrapForGolden(
        const MigrateBitboxFailurePage(
          reason: MigrateBitboxFailureReason.addressAlreadyLinked,
          canRetry: false,
        ),
      ),
    );
  });
}
