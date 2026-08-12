import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/bitbox_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/payment/buy_exceptions.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/payment/transfer_exceptions.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/transfer/dto/real_unit_transfer_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/transfer/dto/real_unit_transfer_payment_info_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_transfer_service.dart';
import 'package:realunit_wallet/packages/wallet/exceptions/signing_cancelled_exception.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';
import 'package:realunit_wallet/screens/migrate_bitbox/cubits/migrate_bitbox/migrate_bitbox_cubit.dart';
import 'package:realunit_wallet/screens/migrate_bitbox/widgets/migrate_transfer_view.dart';
import 'package:realunit_wallet/widgets/buttons/app_filled_button.dart';

import '../../../helper/pump_app.dart';

class _MockMigrateBitboxCubit extends MockCubit<MigrateBitboxState>
    implements MigrateBitboxCubit {}

class _MockTransferService extends Mock implements RealUnitTransferService {}

class _MockAppStore extends Mock implements AppStore {}

class _MockSoftwareWallet extends Mock implements SoftwareWallet {}

RealUnitTransferPaymentInfoDto _info() => RealUnitTransferPaymentInfoDto.fromJson({
  'id': 42,
  'uid': 'RTmigration',
  'toAddress': '0xRecipient',
  'amount': 5,
  'tokenAddress': '0xRealu',
  'chainId': 1,
  'eip7702': {
    'relayerAddress': '0xrelay',
    'delegationManagerAddress': '0xmanager',
    'delegatorAddress': '0xdelegator',
    'userNonce': 0,
    'domain': {
      'name': 'd',
      'version': '1',
      'chainId': 1,
      'verifyingContract': '0xmanager',
    },
    'types': {
      'Delegation': <Map<String, dynamic>>[],
      'Caveat': <Map<String, dynamic>>[],
    },
    'message': {
      'delegate': '0xrelay',
      'delegator': '0xsender',
      'authority': '0xroot',
      'caveats': <Map<String, dynamic>>[],
      'salt': 0,
    },
    'tokenAddress': '0xRealu',
    'amountWei': '5',
    'recipient': '0xRecipient',
  },
});

void main() {
  late _MockMigrateBitboxCubit migrateCubit;
  late _MockTransferService transferService;
  late _MockAppStore appStore;
  late _MockSoftwareWallet wallet;

  setUpAll(() {
    registerFallbackValue(const RealUnitTransferDto(toAddress: '0x', amount: 1));
    registerFallbackValue(_info());
  });

  setUp(() {
    migrateCubit = _MockMigrateBitboxCubit();
    transferService = _MockTransferService();
    appStore = _MockAppStore();
    wallet = _MockSoftwareWallet();
    when(() => migrateCubit.state).thenReturn(
      const MigrateBitboxTransferring(toAddress: '0xRecipient', amount: 5),
    );
    whenListen(
      migrateCubit,
      const Stream<MigrateBitboxState>.empty(),
      initialState: const MigrateBitboxTransferring(
        toAddress: '0xRecipient',
        amount: 5,
      ),
    );
    when(() => migrateCubit.startTransfer()).thenReturn(null);
    when(() => migrateCubit.onTransferBroadcast()).thenAnswer((_) async {});
    when(
      () => migrateCubit.onTransferFailedTerminally(any()),
    ).thenReturn(null);
    when(() => wallet.walletType).thenReturn(WalletType.software);
    when(() => appStore.wallet).thenReturn(wallet);
    GetIt.instance.registerSingleton<RealUnitTransferService>(transferService);
    GetIt.instance.registerSingleton<AppStore>(appStore);
  });

  tearDown(() async {
    await GetIt.instance.unregister<RealUnitTransferService>();
    await GetIt.instance.unregister<AppStore>();
  });

  Future<void> pumpReady(
    WidgetTester tester, {
    String from = '0x1234567890abcdef',
    String to = '0xabcdef1234567890',
  }) => tester.pumpApp(
    BlocProvider<MigrateBitboxCubit>.value(
      value: migrateCubit,
      child: MigrateTransferReadyView(
        fromAddress: from,
        toAddress: to,
        amount: 5,
      ),
    ),
  );

  Future<void> pumpTransferring(WidgetTester tester) async {
    await tester.pumpApp(
      BlocProvider<MigrateBitboxCubit>.value(
        value: migrateCubit,
        child: const MigrateTransferringView(
          toAddress: '0xRecipient',
          amount: 5,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  testWidgets('TransferReady truncates long addresses and starts transfer', (
    tester,
  ) async {
    await pumpReady(tester);

    expect(find.text('0x1234…cdef'), findsOneWidget);
    expect(find.text('0xabcd…7890'), findsOneWidget);
    expect(find.text('5 REALU'), findsOneWidget);
    await tester.tap(find.byType(AppFilledButton));

    verify(() => migrateCubit.startTransfer()).called(1);
  });

  testWidgets('TransferReady keeps short addresses unchanged', (tester) async {
    await pumpReady(tester, from: '0x1234', to: '0xabcd');

    expect(find.text('0x1234'), findsOneWidget);
    expect(find.text('0xabcd'), findsOneWidget);
  });

  testWidgets('embedded process renders preparing, signing, then starts settling on success', (
    tester,
  ) async {
    final prepare = Completer<RealUnitTransferPaymentInfoDto>();
    final confirm = Completer<String>();
    when(() => transferService.prepareTransfer(any())).thenAnswer((_) => prepare.future);
    when(
      () => transferService.confirmTransfer(
        any(),
        confirmedRecipient: any(named: 'confirmedRecipient'),
        confirmedAmount: any(named: 'confirmedAmount'),
      ),
    ).thenAnswer((_) => confirm.future);

    await pumpTransferring(tester);
    expect(find.text(S.current.sendPreparing), findsOneWidget);
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);

    prepare.complete(_info());
    await tester.pump();
    await tester.pump();
    expect(find.text(S.current.sendSigning), findsOneWidget);

    confirm.complete('0xtx');
    await tester.pump();
    await tester.pump();

    verify(() => migrateCubit.onTransferBroadcast()).called(1);
  });

  testWidgets('retryable failure CTA reconfirms the retained transfer intent', (
    tester,
  ) async {
    when(() => transferService.prepareTransfer(any())).thenAnswer((_) async => _info());
    var confirms = 0;
    when(
      () => transferService.confirmTransfer(
        any(),
        confirmedRecipient: any(named: 'confirmedRecipient'),
        confirmedAmount: any(named: 'confirmedAmount'),
      ),
    ).thenAnswer((_) async {
      confirms++;
      if (confirms == 1) throw Exception('transport lost');
      return '0xretry';
    });

    await pumpTransferring(tester);
    expect(find.text(S.current.retry), findsOneWidget);

    await tester.tap(find.byType(AppFilledButton));
    await tester.pump();
    await tester.pump();

    verify(
      () => transferService.confirmTransfer(
        any(),
        confirmedRecipient: '0xRecipient',
        confirmedAmount: 5,
      ),
    ).called(2);
    verify(() => migrateCubit.onTransferBroadcast()).called(1);
  });

  final terminalCases = <(String, Exception, String)>[
    (
      'signature unsupported',
      const TransferSignatureUnsupportedException(),
      'signatureUnsupported',
    ),
    (
      'signature cancelled',
      const SigningCancelledException(),
      'signatureCancelled',
    ),
    (
      'gas unavailable',
      const TransferGasFundingUnavailableException(),
      'gasFundingUnavailable',
    ),
    (
      'invalid request',
      const ApiException(statusCode: 400, code: 'BAD', message: 'bad'),
      'invalidRequest',
    ),
    (
      'registration required',
      const RegistrationRequiredException(
        code: 'REGISTRATION_REQUIRED',
        message: 'register',
      ),
      'registrationOrKycRequired',
    ),
    (
      'bitbox disconnected',
      const BitboxNotConnectedException(),
      'signatureUnsupported',
    ),
    ('generic', Exception('boom'), 'generic'),
  ];

  for (final (label, error, reasonName) in terminalCases) {
    testWidgets('$label automatically exits the embedded dead end', (tester) async {
      when(
        () => transferService.prepareTransfer(any()),
      ).thenAnswer((_) async => throw error);

      await pumpTransferring(tester);

      final expectedMessage = switch (reasonName) {
        'signatureUnsupported' => S.current.sendFailureSignatureUnsupported,
        'signatureCancelled' => S.current.sendFailureSignatureCancelled,
        'gasFundingUnavailable' => S.current.sendFailureGasUnavailable,
        'invalidRequest' => S.current.sendFailureInvalidRequest,
        'registrationOrKycRequired' => S.current.sendFailureRegistrationOrKycRequired,
        _ => S.current.sendFailureGeneric,
      };
      expect(find.text(expectedMessage), findsOneWidget);
      verify(
        () => migrateCubit.onTransferFailedTerminally(expectedMessage),
      ).called(1);
    });
  }

  testWidgets('confirm mismatch resolves its localized terminal message', (
    tester,
  ) async {
    when(() => transferService.prepareTransfer(any())).thenAnswer((_) async => _info());
    when(
      () => transferService.confirmTransfer(
        any(),
        confirmedRecipient: any(named: 'confirmedRecipient'),
        confirmedAmount: any(named: 'confirmedAmount'),
      ),
    ).thenThrow(const TransferConfirmMismatchException('mismatch'));

    await pumpTransferring(tester);

    expect(find.text(S.current.sendFailureConfirmMismatch), findsOneWidget);
    verify(
      () => migrateCubit.onTransferFailedTerminally(
        S.current.sendFailureConfirmMismatch,
      ),
    ).called(1);
  });
}
