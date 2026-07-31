import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/config/api_config.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_transfer_service.dart';
import 'package:realunit_wallet/packages/utils/default_assets.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';
import 'package:realunit_wallet/screens/send/cubits/send_process/send_process_cubit.dart';
import 'package:realunit_wallet/screens/send/send_process_page.dart';

import '../../helper/helper.dart';

class _MockSendProcessCubit extends MockCubit<SendProcessState> implements SendProcessCubit {}

class _MockTransferService extends Mock implements RealUnitTransferService {}

class _MockAppStore extends Mock implements AppStore {}

class _MockApiConfig extends Mock implements ApiConfig {}

class _MockWallet extends Mock implements SoftwareWallet {}

void main() {
  late _MockSendProcessCubit processCubit;

  setUpAll(() {
    final getIt = GetIt.instance;
    // SendProcessPage resolves the service + AppStore from getIt and calls
    // start(). A debug wallet makes start() settle immediately
    // (signatureUnsupported) without touching the network.
    getIt.registerSingleton<RealUnitTransferService>(_MockTransferService());
    final appStore = _MockAppStore();
    final apiConfig = _MockApiConfig();
    when(() => apiConfig.asset).thenReturn(realUnitAsset);
    final wallet = _MockWallet();
    when(() => wallet.walletType).thenReturn(WalletType.debug);
    when(() => appStore.wallet).thenReturn(wallet);
    when(() => appStore.apiConfig).thenReturn(apiConfig);
    getIt.registerSingleton<AppStore>(appStore);
  });

  tearDownAll(() async => GetIt.instance.reset());

  setUp(() {
    processCubit = _MockSendProcessCubit();
    when(() => processCubit.state).thenReturn(const SendProcessInitial());
  });

  Widget buildSubject() => BlocProvider<SendProcessCubit>.value(
    value: processCubit,
    child: const SendProcessView(),
  );

  group('$SendProcessPage', () {
    testWidgets('builds its own cubit and renders $SendProcessView', (tester) async {
      await tester.pumpApp(const SendProcessPage(recipient: '0xRecipient', amount: 5));
      await tester.pump();

      expect(find.byType(SendProcessView), findsOne);
    });
  });

  group('$SendProcessView progress labels', () {
    Future<void> expectLabel(WidgetTester tester, SendProcessState state, String label) async {
      when(() => processCubit.state).thenReturn(state);
      await tester.pumpApp(buildSubject());

      expect(find.byType(CupertinoActivityIndicator), findsOne);
      expect(find.text(label), findsOne);
    }

    testWidgets('initial shows preparing', (tester) async {
      await expectLabel(tester, const SendProcessInitial(), S.current.sendPreparing);
    });

    testWidgets('preparing label', (tester) async {
      await expectLabel(tester, const SendProcessPreparing(), S.current.sendPreparing);
    });

    testWidgets('signing label', (tester) async {
      await expectLabel(tester, const SendProcessSigning(), S.current.sendSigning);
    });

    testWidgets('success label', (tester) async {
      await expectLabel(tester, const SendProcessSuccess('0xtx'), S.current.sendSuccess);
    });

    testWidgets('failure label', (tester) async {
      await expectLabel(
        tester,
        const SendProcessFailure(SendProcessFailureReason.generic),
        S.current.sendFailureTitle,
      );
    });
  });

  group('$SendProcessView PopScope canPop', () {
    testWidgets('blocks back navigation while signing (non-terminal)', (tester) async {
      when(() => processCubit.state).thenReturn(const SendProcessSigning());
      await tester.pumpApp(buildSubject());

      final popScope = tester.widget<PopScope>(find.byType(PopScope));
      expect(popScope.canPop, isFalse);
    });

    testWidgets('allows back navigation on success (terminal)', (tester) async {
      when(() => processCubit.state).thenReturn(const SendProcessSuccess('0xtx'));
      await tester.pumpApp(buildSubject());

      final popScope = tester.widget<PopScope>(find.byType(PopScope));
      expect(popScope.canPop, isTrue);
    });

    testWidgets('blocks back navigation on failure (closes the retry stale-window)', (
      tester,
    ) async {
      when(() => processCubit.state).thenReturn(
        const SendProcessFailure(SendProcessFailureReason.generic),
      );
      await tester.pumpApp(buildSubject());

      final popScope = tester.widget<PopScope>(find.byType(PopScope));
      expect(popScope.canPop, isFalse);
    });

    testWidgets('blocks back navigation while preparing (non-terminal)', (tester) async {
      when(() => processCubit.state).thenReturn(const SendProcessPreparing());
      await tester.pumpApp(buildSubject());

      final popScope = tester.widget<PopScope>(find.byType(PopScope));
      expect(popScope.canPop, isFalse);
    });
  });

  // The result sheet is a modal bottom sheet shown from the listener. The view
  // keeps a CupertinoActivityIndicator animating behind it, so pumpAndSettle
  // never settles; pump fixed frames to open the sheet.
  Future<void> pumpWithState(WidgetTester tester, SendProcessState terminal) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    whenListen(
      processCubit,
      Stream<SendProcessState>.fromIterable([terminal]),
      initialState: const SendProcessSigning(),
    );
    await tester.pumpApp(buildSubject());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('$SendProcessView result sheet', () {
    testWidgets('success emits a success sheet with title + description', (tester) async {
      await pumpWithState(tester, const SendProcessSuccess('0xtx'));

      expect(find.text(S.current.sendSuccessDescription), findsOne);
      expect(find.byIcon(Icons.check_circle_rounded), findsOne);
      expect(find.text(S.current.close), findsOne);
      // Non-retryable terminal states never offer Retry.
      expect(find.text(S.current.retry), findsNothing);

      await tester.tap(find.text(S.current.close));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
    });

    testWidgets('signature-unsupported failure message', (tester) async {
      await pumpWithState(
        tester,
        const SendProcessFailure(SendProcessFailureReason.signatureUnsupported),
      );

      expect(find.text(S.current.sendFailureSignatureUnsupported), findsOne);
      expect(find.byIcon(Icons.error_rounded), findsOne);
      expect(find.text(S.current.retry), findsNothing);
    });

    testWidgets('signature-cancelled failure message', (tester) async {
      await pumpWithState(
        tester,
        const SendProcessFailure(SendProcessFailureReason.signatureCancelled),
      );

      expect(find.text(S.current.sendFailureSignatureCancelled), findsOne);
    });

    testWidgets('gas-unavailable failure message', (tester) async {
      await pumpWithState(
        tester,
        const SendProcessFailure(SendProcessFailureReason.gasFundingUnavailable),
      );

      expect(find.text(S.current.sendFailureGasUnavailable), findsOne);
    });

    testWidgets('invalid-request failure message', (tester) async {
      await pumpWithState(
        tester,
        const SendProcessFailure(SendProcessFailureReason.invalidRequest),
      );

      expect(find.text(S.current.sendFailureInvalidRequest), findsOne);
    });

    testWidgets(
      'registration/KYC failure always shows localized copy, never raw API message',
      (tester) async {
        await pumpWithState(
          tester,
          const SendProcessFailure(
            SendProcessFailureReason.registrationOrKycRequired,
            message: 'Please complete KYC',
          ),
        );

        expect(find.text(S.current.sendFailureRegistrationOrKycRequired), findsOne);
        expect(find.text('Please complete KYC'), findsNothing);
      },
    );

    testWidgets('registration/KYC failure falls back to localized copy without message', (
      tester,
    ) async {
      await pumpWithState(
        tester,
        const SendProcessFailure(SendProcessFailureReason.registrationOrKycRequired),
      );

      expect(find.text(S.current.sendFailureRegistrationOrKycRequired), findsOne);
    });

    testWidgets('generic failure message', (tester) async {
      await pumpWithState(
        tester,
        const SendProcessFailure(SendProcessFailureReason.generic),
      );

      expect(find.text(S.current.sendFailureGeneric), findsOne);
      expect(find.text(S.current.retry), findsNothing);
    });

    testWidgets('confirm-mismatch failure message (non-retryable)', (tester) async {
      await pumpWithState(
        tester,
        const SendProcessFailure(SendProcessFailureReason.confirmMismatch),
      );

      expect(find.text(S.current.sendFailureConfirmMismatch), findsOne);
      expect(find.text(S.current.retry), findsNothing);
      expect(find.text(S.current.close), findsOne);
    });

    testWidgets(
      'retryable failure shows Retry; tapping it calls retryConfirm and keeps the page',
      (tester) async {
        when(() => processCubit.retryConfirm()).thenAnswer((_) async {});

        await pumpWithState(
          tester,
          const SendProcessFailure(
            SendProcessFailureReason.generic,
            message: 'socket hung up',
            canRetry: true,
          ),
        );

        expect(find.text(S.current.retry), findsOne);
        expect(find.text(S.current.close), findsOne);
        expect(find.byType(SendProcessView), findsOne);

        await tester.tap(find.text(S.current.retry));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        verify(() => processCubit.retryConfirm()).called(1);
        // Retry must dismiss only the sheet — the SendProcessPage/View stays.
        expect(find.byType(SendProcessView), findsOne);
        expect(find.text(S.current.retry), findsNothing);
      },
    );

    testWidgets('non-retryable failure: Close only, no Retry button', (tester) async {
      await pumpWithState(
        tester,
        const SendProcessFailure(SendProcessFailureReason.signatureUnsupported),
      );

      expect(find.text(S.current.retry), findsNothing);
      expect(find.text(S.current.close), findsOne);

      await tester.tap(find.text(S.current.close));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byIcon(Icons.error_rounded), findsNothing);
    });
  });
}
