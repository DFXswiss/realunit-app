import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
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
import 'package:realunit_wallet/screens/send/cubits/send_process/send_process_cubit.dart';

class _MockTransferService extends Mock implements RealUnitTransferService {}

class _MockAppStore extends Mock implements AppStore {}

class _MockWallet extends Mock implements AWallet {}

RealUnitTransferPaymentInfoDto _info({int id = 42}) => RealUnitTransferPaymentInfoDto.fromJson({
  'id': id,
  'uid': 'RTabc',
  'toAddress': '0xRecipient',
  'amount': 5,
  'tokenAddress': '0xRealu',
  'chainId': 1,
  'eip7702': {
    'relayerAddress': '0xrelay',
    'delegationManagerAddress': '0xmanager',
    'delegatorAddress': '0xdelegator',
    'userNonce': 0,
    'domain': {'name': 'd', 'version': '1', 'chainId': 1, 'verifyingContract': '0xmanager'},
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
  late _MockTransferService service;
  late _MockAppStore appStore;
  late _MockWallet wallet;

  setUpAll(() {
    registerFallbackValue(const RealUnitTransferDto(toAddress: '0x', amount: 1));
    registerFallbackValue(_info());
  });

  setUp(() {
    service = _MockTransferService();
    appStore = _MockAppStore();
    wallet = _MockWallet();
    when(() => appStore.wallet).thenReturn(wallet);
    when(() => wallet.walletType).thenReturn(WalletType.software);
  });

  SendProcessCubit build() => SendProcessCubit(
    transferService: service,
    appStore: appStore,
    recipient: '0xRecipient',
    amount: 5,
  );

  /// Stubs `confirmTransfer` with the required named user-confirmed params.
  void stubConfirm([Object? answerOrThrow]) {
    Future<String> invocation() => service.confirmTransfer(
      any(),
      confirmedRecipient: any(named: 'confirmedRecipient'),
      confirmedAmount: any(named: 'confirmedAmount'),
    );
    if (answerOrThrow is Exception) {
      when(invocation).thenThrow(answerOrThrow);
    } else {
      when(invocation).thenAnswer((_) async => (answerOrThrow as String?) ?? '0xdeadbeef');
    }
  }

  void verifyConfirmCalled({int times = 1}) {
    verify(
      () => service.confirmTransfer(
        any(),
        confirmedRecipient: any(named: 'confirmedRecipient'),
        confirmedAmount: any(named: 'confirmedAmount'),
      ),
    ).called(times);
  }

  void wireHappyPath() {
    when(() => service.prepareTransfer(any())).thenAnswer((_) async => _info());
    stubConfirm();
  }

  test('debug wallet → signatureUnsupported before any network call', () async {
    when(() => wallet.walletType).thenReturn(WalletType.debug);

    final cubit = build();
    await cubit.start();

    final state = cubit.state as SendProcessFailure;
    expect(state.reason, SendProcessFailureReason.signatureUnsupported);
    verifyNever(() => service.prepareTransfer(any()));
    await cubit.close();
  });

  test('bitbox wallet → signatureUnsupported before any network call', () async {
    when(() => wallet.walletType).thenReturn(WalletType.bitbox);

    final cubit = build();
    await cubit.start();

    final state = cubit.state as SendProcessFailure;
    expect(state.reason, SendProcessFailureReason.signatureUnsupported);
    verifyNever(() => service.prepareTransfer(any()));
    await cubit.close();
  });

  test('happy path: prepare → confirm → success with txHash', () async {
    wireHappyPath();
    RealUnitTransferDto? sentDto;
    when(() => service.prepareTransfer(any())).thenAnswer((invocation) async {
      sentDto = invocation.positionalArguments.first as RealUnitTransferDto;
      return _info();
    });

    final cubit = build();
    await cubit.start();

    expect(sentDto!.toAddress, '0xRecipient');
    expect(sentDto!.amount, 5);
    final state = cubit.state as SendProcessSuccess;
    expect(state.txHash, '0xdeadbeef');
    verify(
      () => service.confirmTransfer(
        any(),
        confirmedRecipient: '0xRecipient',
        confirmedAmount: 5,
      ),
    ).called(1);
    await cubit.close();
  });

  test('emits Preparing then Signing then Success', () async {
    wireHappyPath();

    final cubit = build();
    final emitted = <SendProcessState>[];
    final sub = cubit.stream.listen(emitted.add);
    await cubit.start();
    // Let the final Success microtask flush before cancelling the subscription.
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    expect(emitted.map((s) => s.runtimeType).toList(), [
      SendProcessPreparing,
      SendProcessSigning,
      SendProcessSuccess,
    ]);
    await cubit.close();
  });

  test('service-reported unsupported signature → signatureUnsupported', () async {
    when(() => service.prepareTransfer(any())).thenAnswer((_) async => _info());
    stubConfirm(const TransferSignatureUnsupportedException());

    final cubit = build();
    await cubit.start();

    final state = cubit.state as SendProcessFailure;
    expect(state.reason, SendProcessFailureReason.signatureUnsupported);
    expect(state.canRetry, isFalse);
    await cubit.close();
  });

  test('gas funding unavailable exception → gasFundingUnavailable', () async {
    when(
      () => service.prepareTransfer(any()),
    ).thenThrow(const TransferGasFundingUnavailableException());

    final cubit = build();
    await cubit.start();

    expect(
      (cubit.state as SendProcessFailure).reason,
      SendProcessFailureReason.gasFundingUnavailable,
    );
    await cubit.close();
  });

  test('prepare-phase TransferSignatureUnsupportedException → signatureUnsupported', () async {
    when(
      () => service.prepareTransfer(any()),
    ).thenThrow(const TransferSignatureUnsupportedException());

    final cubit = build();
    await cubit.start();

    final state = cubit.state as SendProcessFailure;
    expect(state.reason, SendProcessFailureReason.signatureUnsupported);
    expect(state.canRetry, isFalse);
    verifyNever(
      () => service.confirmTransfer(
        any(),
        confirmedRecipient: any(named: 'confirmedRecipient'),
        confirmedAmount: any(named: 'confirmedAmount'),
      ),
    );
    await cubit.close();
  });

  test('prepare-phase SigningCancelledException → signatureCancelled', () async {
    when(() => service.prepareTransfer(any())).thenThrow(const SigningCancelledException());

    final cubit = build();
    await cubit.start();

    final state = cubit.state as SendProcessFailure;
    expect(state.reason, SendProcessFailureReason.signatureCancelled);
    expect(state.canRetry, isFalse);
    verifyNever(
      () => service.confirmTransfer(
        any(),
        confirmedRecipient: any(named: 'confirmedRecipient'),
        confirmedAmount: any(named: 'confirmedAmount'),
      ),
    );
    await cubit.close();
  });

  test('prepare-phase BitboxNotConnectedException → signatureUnsupported', () async {
    when(() => service.prepareTransfer(any())).thenThrow(const BitboxNotConnectedException());

    final cubit = build();
    await cubit.start();

    final state = cubit.state as SendProcessFailure;
    expect(state.reason, SendProcessFailureReason.signatureUnsupported);
    expect(state.canRetry, isFalse);
    verifyNever(
      () => service.confirmTransfer(
        any(),
        confirmedRecipient: any(named: 'confirmedRecipient'),
        confirmedAmount: any(named: 'confirmedAmount'),
      ),
    );
    await cubit.close();
  });

  test('signing cancelled → signatureCancelled', () async {
    when(() => service.prepareTransfer(any())).thenAnswer((_) async => _info());
    stubConfirm(const SigningCancelledException());

    final cubit = build();
    await cubit.start();

    final state = cubit.state as SendProcessFailure;
    expect(state.reason, SendProcessFailureReason.signatureCancelled);
    expect(state.canRetry, isFalse);
    await cubit.close();
  });

  test('bitbox not connected (defensive) → signatureUnsupported', () async {
    when(() => service.prepareTransfer(any())).thenAnswer((_) async => _info());
    stubConfirm(const BitboxNotConnectedException());

    final cubit = build();
    await cubit.start();

    expect(
      (cubit.state as SendProcessFailure).reason,
      SendProcessFailureReason.signatureUnsupported,
    );
    await cubit.close();
  });

  test('API 400 (invalid recipient / insufficient REALU) → invalidRequest', () async {
    when(() => service.prepareTransfer(any())).thenThrow(
      const ApiException(statusCode: 400, code: 'X', message: 'Invalid recipient address'),
    );

    final cubit = build();
    await cubit.start();

    final state = cubit.state as SendProcessFailure;
    expect(state.reason, SendProcessFailureReason.invalidRequest);
    expect(state.message, 'Invalid recipient address');
    expect(state.canRetry, isFalse);
    await cubit.close();
  });

  test('API 404 → invalidRequest', () async {
    when(
      () => service.prepareTransfer(any()),
    ).thenThrow(const ApiException(statusCode: 404, code: 'X', message: 'not found'));

    final cubit = build();
    await cubit.start();

    expect((cubit.state as SendProcessFailure).reason, SendProcessFailureReason.invalidRequest);
    await cubit.close();
  });

  test('API 503 → gasFundingUnavailable', () async {
    when(
      () => service.prepareTransfer(any()),
    ).thenThrow(const ApiException(statusCode: 503, code: 'X', message: 'unavailable'));

    final cubit = build();
    await cubit.start();

    expect(
      (cubit.state as SendProcessFailure).reason,
      SendProcessFailureReason.gasFundingUnavailable,
    );
    await cubit.close();
  });

  test('API 500 → generic', () async {
    when(
      () => service.prepareTransfer(any()),
    ).thenThrow(const ApiException(statusCode: 500, code: 'X', message: 'boom'));

    final cubit = build();
    await cubit.start();

    final state = cubit.state as SendProcessFailure;
    expect(state.reason, SendProcessFailureReason.generic);
    // Prepare-phase failures are never retryable (no transfer id stored).
    expect(state.canRetry, isFalse);
    await cubit.close();
  });

  test('RegistrationRequiredException → registrationOrKycRequired with message', () async {
    when(() => service.prepareTransfer(any())).thenThrow(
      const RegistrationRequiredException(
        code: 'REGISTRATION_REQUIRED',
        message: 'Please register first',
      ),
    );

    final cubit = build();
    await cubit.start();

    final state = cubit.state as SendProcessFailure;
    expect(state.reason, SendProcessFailureReason.registrationOrKycRequired);
    expect(state.message, 'Please register first');
    await cubit.close();
  });

  test('KycLevelRequiredException → registrationOrKycRequired with message', () async {
    when(() => service.prepareTransfer(any())).thenThrow(
      const KycLevelRequiredException(
        code: 'KYC_LEVEL_REQUIRED',
        message: 'KYC level 2 required',
        requiredLevel: 2,
        currentLevel: 1,
      ),
    );

    final cubit = build();
    await cubit.start();

    final state = cubit.state as SendProcessFailure;
    expect(state.reason, SendProcessFailureReason.registrationOrKycRequired);
    expect(state.message, 'KYC level 2 required');
    await cubit.close();
  });

  test('API 403 → registrationOrKycRequired', () async {
    when(() => service.prepareTransfer(any())).thenThrow(
      const ApiException(statusCode: 403, code: 'X', message: 'forbidden'),
    );

    final cubit = build();
    await cubit.start();

    expect(
      (cubit.state as SendProcessFailure).reason,
      SendProcessFailureReason.registrationOrKycRequired,
    );
    await cubit.close();
  });

  test('closing the cubit before prepareTransfer resolves does not throw and does not emit', () async {
    final completer = Completer<RealUnitTransferPaymentInfoDto>();
    when(() => service.prepareTransfer(any())).thenAnswer((_) => completer.future);

    final cubit = build();
    final future = cubit.start();
    await cubit.close();
    completer.complete(_info());
    await future; // must not throw StateError, and must not attempt to emit after close
  });

  test('closing the cubit before prepareTransfer rejects does not throw and does not emit', () async {
    final completer = Completer<RealUnitTransferPaymentInfoDto>();
    when(() => service.prepareTransfer(any())).thenAnswer((_) => completer.future);

    final cubit = build();
    final emitted = <SendProcessState>[];
    final sub = cubit.stream.listen(emitted.add);
    final future = cubit.start();
    await cubit.close();
    completer.completeError(Exception('boom'));
    await future; // must not throw StateError, and must not attempt to emit after close
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    expect(emitted.map((s) => s.runtimeType).toList(), [SendProcessPreparing]);
  });

  test('closing the cubit before confirmTransfer resolves does not throw and does not emit', () async {
    when(() => service.prepareTransfer(any())).thenAnswer((_) async => _info());
    final completer = Completer<String>();
    when(
      () => service.confirmTransfer(
        any(),
        confirmedRecipient: any(named: 'confirmedRecipient'),
        confirmedAmount: any(named: 'confirmedAmount'),
      ),
    ).thenAnswer((_) => completer.future);

    final cubit = build();
    final future = cubit.start();
    await cubit.close();
    completer.complete('0xdeadbeef');
    await future; // must not throw StateError, and must not attempt to emit after close
  });

  test(
    'closing the cubit while confirmTransfer is in flight → does not emit regardless of outcome',
    () async {
      when(() => service.prepareTransfer(any())).thenAnswer((_) async => _info());
      final completer = Completer<String>();
      when(
        () => service.confirmTransfer(
          any(),
          confirmedRecipient: any(named: 'confirmedRecipient'),
          confirmedAmount: any(named: 'confirmedAmount'),
        ),
      ).thenAnswer((_) => completer.future);

      final cubit = build();
      final emitted = <SendProcessState>[];
      final sub = cubit.stream.listen(emitted.add);
      final future = cubit.start();
      // Let prepare resolve and start() reach the in-flight confirm await
      // (SendProcessSigning) before closing.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state, isA<SendProcessSigning>());

      final countAtClose = emitted.length;
      await cubit.close();
      // Representative reject path — centralized isClosed guard must suppress
      // emit for every catch branch, not only success.
      completer.completeError(Exception('socket hung up'));
      await future; // must not throw StateError
      // Let any residual microtask that might have emitted flush.
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      // No state after close (Signing was already emitted before close).
      expect(emitted.length, countAtClose);
      expect(emitted.map((s) => s.runtimeType).toList(), [
        SendProcessPreparing,
        SendProcessSigning,
      ]);
    },
  );

  test(
    'closing the cubit while confirmTransfer is in flight, then it resolves successfully → does not emit but logs the missed success',
    () async {
      when(() => service.prepareTransfer(any())).thenAnswer((_) async => _info());
      final completer = Completer<String>();
      when(
        () => service.confirmTransfer(
          any(),
          confirmedRecipient: any(named: 'confirmedRecipient'),
          confirmedAmount: any(named: 'confirmedAmount'),
        ),
      ).thenAnswer((_) => completer.future);

      final cubit = build();
      final emitted = <SendProcessState>[];
      final sub = cubit.stream.listen(emitted.add);
      final future = cubit.start();
      // Let prepare resolve and start() reach the in-flight confirm await
      // (SendProcessSigning) before closing.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state, isA<SendProcessSigning>());

      final countAtClose = emitted.length;
      await cubit.close();
      // Direct success path after close — isClosed guard must suppress emit
      // and take the developer.log branch for the missed txHash.
      completer.complete('0xdeadbeef');
      await future; // must not throw StateError
      // Let any residual microtask that might have emitted flush.
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      // No state after close (Signing was already emitted before close).
      expect(emitted.length, countAtClose);
      expect(emitted.map((s) => s.runtimeType).toList(), [
        SendProcessPreparing,
        SendProcessSigning,
      ]);
    },
  );

  test('unexpected error on prepare → generic (non-retryable)', () async {
    when(() => service.prepareTransfer(any())).thenThrow(Exception('weird'));

    final cubit = build();
    await cubit.start();

    final state = cubit.state as SendProcessFailure;
    expect(state.reason, SendProcessFailureReason.generic);
    expect(state.canRetry, isFalse);
    await cubit.close();
  });

  test(
    'unclassified/transport error on confirm → retryable failure; prepare called once',
    () async {
      when(() => service.prepareTransfer(any())).thenAnswer((_) async => _info());
      stubConfirm(Exception('socket hung up'));

      final cubit = build();
      await cubit.start();

      final state = cubit.state as SendProcessFailure;
      expect(state.reason, SendProcessFailureReason.generic);
      expect(state.canRetry, isTrue);
      verify(() => service.prepareTransfer(any())).called(1);
      verifyConfirmCalled();
      await cubit.close();
    },
  );

  test(
    'retryConfirm re-invokes confirmTransfer with the same stored info/id (no new prepare)',
    () async {
      final prepared = _info(id: 42);
      when(() => service.prepareTransfer(any())).thenAnswer((_) async => prepared);

      var confirmCalls = 0;
      RealUnitTransferPaymentInfoDto? confirmedInfo;
      when(
        () => service.confirmTransfer(
          any(),
          confirmedRecipient: any(named: 'confirmedRecipient'),
          confirmedAmount: any(named: 'confirmedAmount'),
        ),
      ).thenAnswer((invocation) async {
        confirmCalls++;
        confirmedInfo = invocation.positionalArguments.first as RealUnitTransferPaymentInfoDto;
        if (confirmCalls == 1) {
          throw Exception('transport lost');
        }
        return '0xretryhash';
      });

      final cubit = build();
      await cubit.start();

      expect((cubit.state as SendProcessFailure).canRetry, isTrue);

      await cubit.retryConfirm();

      expect(cubit.state, isA<SendProcessSuccess>());
      expect((cubit.state as SendProcessSuccess).txHash, '0xretryhash');
      expect(confirmCalls, 2);
      expect(confirmedInfo!.id, 42);
      // prepareTransfer must never have been called again on retry.
      verify(() => service.prepareTransfer(any())).called(1);
      await cubit.close();
    },
  );

  test('409 already confirmed on start() → SendProcessSuccess', () async {
    when(() => service.prepareTransfer(any())).thenAnswer((_) async => _info());
    stubConfirm(
      const TransferAlreadyConfirmedException(
        statusCode: 409,
        code: 'CONFLICT',
        message: 'Transaction request is already confirmed',
        txHash: '0xalready',
      ),
    );

    final cubit = build();
    await cubit.start();

    final state = cubit.state as SendProcessSuccess;
    expect(state.txHash, '0xalready');
    await cubit.close();
  });

  test('409 already confirmed on retryConfirm() → SendProcessSuccess', () async {
    when(() => service.prepareTransfer(any())).thenAnswer((_) async => _info());

    var confirmCalls = 0;
    when(
      () => service.confirmTransfer(
        any(),
        confirmedRecipient: any(named: 'confirmedRecipient'),
        confirmedAmount: any(named: 'confirmedAmount'),
      ),
    ).thenAnswer((_) async {
      confirmCalls++;
      if (confirmCalls == 1) {
        throw Exception('timeout after server accepted');
      }
      throw const TransferAlreadyConfirmedException(
        statusCode: 409,
        code: 'CONFLICT',
        message: 'Transaction request is already confirmed',
      );
    });

    final cubit = build();
    await cubit.start();
    expect((cubit.state as SendProcessFailure).canRetry, isTrue);

    await cubit.retryConfirm();

    // No txHash on the 409 body → empty string (success sheet does not show it).
    expect(cubit.state, isA<SendProcessSuccess>());
    expect((cubit.state as SendProcessSuccess).txHash, '');
    await cubit.close();
  });

  test('retryConfirm with nothing prepared → throws StateError', () async {
    final cubit = build();

    expect(() => cubit.retryConfirm(), throwsA(isA<StateError>()));
    await cubit.close();
  });

  test('retryConfirm after a non-retryable failure → throws StateError', () async {
    when(() => service.prepareTransfer(any())).thenAnswer((_) async => _info());
    stubConfirm(const TransferSignatureUnsupportedException());

    final cubit = build();
    await cubit.start();

    expect((cubit.state as SendProcessFailure).canRetry, isFalse);
    expect(() => cubit.retryConfirm(), throwsA(isA<StateError>()));
    await cubit.close();
  });

  test('retryConfirm while a confirm is already in flight → throws StateError', () async {
    when(() => service.prepareTransfer(any())).thenAnswer((_) async => _info());
    final completer = Completer<String>();
    when(
      () => service.confirmTransfer(
        any(),
        confirmedRecipient: any(named: 'confirmedRecipient'),
        confirmedAmount: any(named: 'confirmedAmount'),
      ),
    ).thenAnswer((_) => completer.future);

    final cubit = build();
    final startFuture = cubit.start();
    // Let prepare resolve and start() reach the in-flight confirm await (SendProcessSigning).
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(cubit.state, isA<SendProcessSigning>());
    expect(() => cubit.retryConfirm(), throwsA(isA<StateError>()));

    completer.complete('0xdone');
    await startFuture;
    await cubit.close();
  });

  test(
    'concurrent start while confirm is already in flight → throws StateError',
    () async {
      when(() => service.prepareTransfer(any())).thenAnswer((_) async => _info());
      final completer = Completer<String>();
      when(
        () => service.confirmTransfer(
          any(),
          confirmedRecipient: any(named: 'confirmedRecipient'),
          confirmedAmount: any(named: 'confirmedAmount'),
        ),
      ).thenAnswer((_) => completer.future);

      final cubit = build();
      final firstStart = cubit.start();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state, isA<SendProcessSigning>());

      // Second start re-prepares then hits _confirmPrepared's in-flight guard.
      await expectLater(cubit.start(), throwsA(isA<StateError>()));

      completer.complete('0xdone');
      await firstStart;
      await cubit.close();
    },
  );

  test(
    'TransferConfirmMismatchException → confirmMismatch, non-retryable',
    () async {
      when(() => service.prepareTransfer(any())).thenAnswer((_) async => _info());
      stubConfirm(const TransferConfirmMismatchException('toAddress mismatch'));

      final cubit = build();
      await cubit.start();

      final state = cubit.state as SendProcessFailure;
      expect(state.reason, SendProcessFailureReason.confirmMismatch);
      expect(state.canRetry, isFalse);
      expect(() => cubit.retryConfirm(), throwsA(isA<StateError>()));
      await cubit.close();
    },
  );

  test(
    'confirm-phase TransferGasFundingUnavailableException → gasFundingUnavailable',
    () async {
      when(() => service.prepareTransfer(any())).thenAnswer((_) async => _info());
      stubConfirm(const TransferGasFundingUnavailableException());

      final cubit = build();
      await cubit.start();

      final state = cubit.state as SendProcessFailure;
      expect(state.reason, SendProcessFailureReason.gasFundingUnavailable);
      expect(state.canRetry, isFalse);
      await cubit.close();
    },
  );

  test(
    'confirm-phase RegistrationRequiredException → registrationOrKycRequired',
    () async {
      when(() => service.prepareTransfer(any())).thenAnswer((_) async => _info());
      stubConfirm(
        const RegistrationRequiredException(
          code: 'REGISTRATION_REQUIRED',
          message: 'Please register first',
        ),
      );

      final cubit = build();
      await cubit.start();

      final state = cubit.state as SendProcessFailure;
      expect(state.reason, SendProcessFailureReason.registrationOrKycRequired);
      expect(state.message, 'Please register first');
      expect(state.canRetry, isFalse);
      await cubit.close();
    },
  );

  test(
    'confirm-phase KycLevelRequiredException → registrationOrKycRequired',
    () async {
      when(() => service.prepareTransfer(any())).thenAnswer((_) async => _info());
      stubConfirm(
        const KycLevelRequiredException(
          code: 'KYC_LEVEL_REQUIRED',
          message: 'KYC level 2 required',
          requiredLevel: 2,
          currentLevel: 1,
        ),
      );

      final cubit = build();
      await cubit.start();

      final state = cubit.state as SendProcessFailure;
      expect(state.reason, SendProcessFailureReason.registrationOrKycRequired);
      expect(state.message, 'KYC level 2 required');
      expect(state.canRetry, isFalse);
      await cubit.close();
    },
  );

  test(
    'confirm-phase API 500 → generic (retryable via _isDefinitiveApiFailure)',
    () async {
      when(() => service.prepareTransfer(any())).thenAnswer((_) async => _info());
      stubConfirm(const ApiException(statusCode: 500, code: 'X', message: 'boom'));

      final cubit = build();
      await cubit.start();

      final state = cubit.state as SendProcessFailure;
      expect(state.reason, SendProcessFailureReason.generic);
      expect(state.message, 'boom');
      expect(state.canRetry, isTrue);
      await cubit.close();
    },
  );

  test(
    'confirm-phase API 400 → invalidRequest (non-retryable definitive failure)',
    () async {
      when(() => service.prepareTransfer(any())).thenAnswer((_) async => _info());
      stubConfirm(
        const ApiException(statusCode: 400, code: 'X', message: 'bad request'),
      );

      final cubit = build();
      await cubit.start();

      final state = cubit.state as SendProcessFailure;
      expect(state.reason, SendProcessFailureReason.invalidRequest);
      expect(state.message, 'bad request');
      expect(state.canRetry, isFalse);
      await cubit.close();
    },
  );

  test(
    'confirm-phase API 403 → registrationOrKycRequired (non-retryable)',
    () async {
      when(() => service.prepareTransfer(any())).thenAnswer((_) async => _info());
      stubConfirm(const ApiException(statusCode: 403, code: 'X', message: 'forbidden'));

      final cubit = build();
      await cubit.start();

      final state = cubit.state as SendProcessFailure;
      expect(state.reason, SendProcessFailureReason.registrationOrKycRequired);
      expect(state.canRetry, isFalse);
      await cubit.close();
    },
  );

  test(
    'confirm-phase API 404 → invalidRequest (non-retryable)',
    () async {
      when(() => service.prepareTransfer(any())).thenAnswer((_) async => _info());
      stubConfirm(const ApiException(statusCode: 404, code: 'X', message: 'not found'));

      final cubit = build();
      await cubit.start();

      final state = cubit.state as SendProcessFailure;
      expect(state.reason, SendProcessFailureReason.invalidRequest);
      expect(state.canRetry, isFalse);
      await cubit.close();
    },
  );

  test(
    'confirm-phase API 503 → gasFundingUnavailable (non-retryable)',
    () async {
      when(() => service.prepareTransfer(any())).thenAnswer((_) async => _info());
      stubConfirm(
        const ApiException(statusCode: 503, code: 'X', message: 'unavailable'),
      );

      final cubit = build();
      await cubit.start();

      final state = cubit.state as SendProcessFailure;
      expect(state.reason, SendProcessFailureReason.gasFundingUnavailable);
      expect(state.canRetry, isFalse);
      await cubit.close();
    },
  );
}
