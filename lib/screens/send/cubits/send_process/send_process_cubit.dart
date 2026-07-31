import 'dart:developer' as developer;

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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

part 'send_process_state.dart';

/// Orchestrates the gasless wallet-to-wallet transfer once the user confirms:
/// gate the wallet's signing capability → `PUT /transfer` (prepare + EIP-7702
/// delegation data) → sign the EIP-712 delegation + EIP-7702 authorization and
/// `PUT /transfer/:id/confirm` → success (txHash) / a typed failure.
///
/// Prepare and confirm are split so a failed confirm can be retried against the
/// same server-assigned transfer `id` (DFXswiss/api#3820 keys idempotency off
/// that `id`). A new prepare would mint a second on-chain transfer intent.
///
/// The gasless EIP-7702 path can only be signed by a software wallet today;
/// debug and BitBox wallets are gated up-front (the contract's capability gate —
/// the flow is NOT otherwise branched on wallet type). Insufficient REALU and
/// invalid-address are decided by the API and rendered from its signal; a 503
/// (gas-funding-unavailable) surfaces as a dedicated "temporarily unavailable"
/// state.
class SendProcessCubit extends Cubit<SendProcessState> {
  final RealUnitTransferService _transferService;
  final AppStore _appStore;
  final String _recipient;
  final int _amount;

  /// Successfully prepared transfer intent (carries the server-assigned `id`).
  /// Stored for the lifetime of the cubit so [retryConfirm] can re-confirm the
  /// same intent without a second prepare.
  RealUnitTransferPaymentInfoDto? _preparedInfo;

  /// Guards against concurrent confirm attempts (start + retry, or double-tap).
  bool _confirmInFlight = false;

  SendProcessCubit({
    required RealUnitTransferService transferService,
    required AppStore appStore,
    required String recipient,
    required int amount,
  }) : _transferService = transferService,
       _appStore = appStore,
       _recipient = recipient,
       _amount = amount,
       super(const SendProcessInitial());

  /// Entry point — called by the view once the user confirms the summary.
  Future<void> start() async {
    // Capability gate BEFORE any network/sign action: only a software wallet can
    // produce the EIP-712 delegation + EIP-7702 authorization the gasless
    // transfer requires. Surface the dedicated unsupported state otherwise.
    if (_appStore.wallet.walletType != WalletType.software) {
      emit(const SendProcessFailure(SendProcessFailureReason.signatureUnsupported));
      return;
    }

    // Phase 1 — prepare. Failures here are terminal and non-retryable: no
    // transfer `id` was ever obtained, so there is nothing safe to retry.
    // Classification into a local failure state happens in the try/catch;
    // emission is gated once after so a closed cubit never emits.
    SendProcessState? prepareFailure;
    try {
      emit(const SendProcessPreparing());
      final info = await _transferService.prepareTransfer(
        RealUnitTransferDto(toAddress: _recipient, amount: _amount),
      );
      if (isClosed) {
        return;
      }
      _preparedInfo = info;
    } on TransferSignatureUnsupportedException {
      prepareFailure = const SendProcessFailure(SendProcessFailureReason.signatureUnsupported);
    } on TransferGasFundingUnavailableException {
      prepareFailure = const SendProcessFailure(SendProcessFailureReason.gasFundingUnavailable);
    } on SigningCancelledException {
      prepareFailure = const SendProcessFailure(SendProcessFailureReason.signatureCancelled);
    } on BitboxNotConnectedException {
      prepareFailure = const SendProcessFailure(SendProcessFailureReason.signatureUnsupported);
    } on RegistrationRequiredException catch (e) {
      prepareFailure = SendProcessFailure(
        SendProcessFailureReason.registrationOrKycRequired,
        message: e.message,
      );
    } on KycLevelRequiredException catch (e) {
      prepareFailure = SendProcessFailure(
        SendProcessFailureReason.registrationOrKycRequired,
        message: e.message,
      );
    } on ApiException catch (e) {
      // The API is the authority on recipient/amount/eligibility. Render its
      // signaled reason rather than re-deriving limits locally.
      prepareFailure = SendProcessFailure(_reasonForApi(e), message: e.message);
    } catch (e) {
      prepareFailure = SendProcessFailure(SendProcessFailureReason.generic, message: e.toString());
    }

    if (prepareFailure != null) {
      if (isClosed) {
        return;
      }
      emit(prepareFailure);
      return;
    }

    // Phase 2 — confirm against the stored prepare result.
    await _confirmPrepared();
  }

  /// Re-signs and re-PUTs `/confirm` for the same prepared transfer `id`.
  ///
  /// Safe because the backend is idempotent per id: re-signing the same message
  /// is not a new transfer. Fails loud when there is nothing prepared, when a
  /// confirm is already in flight, or when the cubit is not in a retryable
  /// failure state.
  Future<void> retryConfirm() async {
    if (_preparedInfo == null) {
      throw StateError('Cannot retry confirm: no prepared transfer info is stored');
    }
    if (_confirmInFlight) {
      throw StateError('Cannot retry confirm: a confirm is already in flight');
    }
    final current = state;
    if (current is! SendProcessFailure || !current.canRetry) {
      throw StateError('Cannot retry confirm: cubit is not in a retryable failure state');
    }
    await _confirmPrepared();
  }

  /// Shared confirm path used by [start] and [retryConfirm]. Never calls
  /// prepare — only signs + PUTs against [_preparedInfo].
  ///
  /// Callers ([start] after a successful prepare, [retryConfirm] after its own
  /// null-check) guarantee [_preparedInfo] is non-null. Classification of the
  /// confirm outcome into a single [SendProcessState] happens in the try/catch;
  /// emission is gated once after [finally] so a closed cubit never emits.
  Future<void> _confirmPrepared() async {
    final info = _preparedInfo!;
    if (_confirmInFlight) {
      throw StateError('Cannot confirm: a confirm is already in flight');
    }

    _confirmInFlight = true;
    late SendProcessState nextState;
    // Set only on the direct success path (confirmTransfer resolves); used for
    // the diagnostic log when the cubit closed before that success could emit.
    String? directSuccessTxHash;
    try {
      emit(const SendProcessSigning());
      final txHash = await _transferService.confirmTransfer(
        info,
        confirmedRecipient: _recipient,
        confirmedAmount: _amount,
      );
      directSuccessTxHash = txHash;
      nextState = SendProcessSuccess(txHash);
    } on TransferAlreadyConfirmedException catch (e) {
      // An earlier confirm for this id landed; treat as success. Prefer the
      // server-supplied txHash when present; empty string when the 409 body
      // carried none (the success sheet does not display the hash — empty is
      // the intentional "no hash available" representation, not a fake hash).
      final alreadyConfirmedTxHash = e.txHash;
      if (alreadyConfirmedTxHash != null) {
        nextState = SendProcessSuccess(alreadyConfirmedTxHash);
      } else {
        nextState = const SendProcessSuccess('');
      }
    } on TransferConfirmMismatchException catch (e) {
      nextState = SendProcessFailure(
        SendProcessFailureReason.confirmMismatch,
        message: e.toString(),
      );
    } on TransferSignatureUnsupportedException {
      nextState = const SendProcessFailure(SendProcessFailureReason.signatureUnsupported);
    } on TransferGasFundingUnavailableException {
      nextState = const SendProcessFailure(SendProcessFailureReason.gasFundingUnavailable);
    } on SigningCancelledException {
      nextState = const SendProcessFailure(SendProcessFailureReason.signatureCancelled);
    } on BitboxNotConnectedException {
      nextState = const SendProcessFailure(SendProcessFailureReason.signatureUnsupported);
    } on RegistrationRequiredException catch (e) {
      nextState = SendProcessFailure(
        SendProcessFailureReason.registrationOrKycRequired,
        message: e.message,
      );
    } on KycLevelRequiredException catch (e) {
      nextState = SendProcessFailure(
        SendProcessFailureReason.registrationOrKycRequired,
        message: e.message,
      );
    } on ApiException catch (e) {
      // Definitive client/server business failures are terminal. Other API
      // status codes (e.g. 500) may be transient after a confirm that already
      // has a known-good id — offer retry against the same intent.
      nextState = SendProcessFailure(
        _reasonForApi(e),
        message: e.message,
        canRetry: !_isDefinitiveApiFailure(e),
      );
    } catch (e) {
      // Transport/timeout/unclassified: id is known-good; allow retryConfirm.
      nextState = SendProcessFailure(
        SendProcessFailureReason.generic,
        message: e.toString(),
        canRetry: true,
      );
    } finally {
      _confirmInFlight = false;
    }

    if (isClosed) {
      if (directSuccessTxHash != null) {
        developer.log(
          'SendProcessCubit: transfer succeeded (txHash=$directSuccessTxHash) after the cubit was closed — '
          'result could not be emitted',
        );
      }
      return;
    }
    emit(nextState);
  }

  /// Maps an API error to a typed failure reason. A 400 from `PUT /transfer`
  /// covers both an invalid recipient and insufficient REALU; both render a
  /// generic "could not prepare the transfer" message keyed off the API text,
  /// so they share [SendProcessFailureReason.invalidRequest]. A 403 (including
  /// unmapped compliance codes) maps to [registrationOrKycRequired].
  static SendProcessFailureReason _reasonForApi(ApiException e) {
    if (e.statusCode == 503) {
      return SendProcessFailureReason.gasFundingUnavailable;
    }
    if (e.statusCode == 403) {
      return SendProcessFailureReason.registrationOrKycRequired;
    }
    if (e.statusCode == 400 || e.statusCode == 404) {
      return SendProcessFailureReason.invalidRequest;
    }
    return SendProcessFailureReason.generic;
  }

  /// Definitive API failures that must not be retried via [retryConfirm].
  static bool _isDefinitiveApiFailure(ApiException e) {
    final statusCode = e.statusCode;
    return statusCode == 400 ||
        statusCode == 403 ||
        statusCode == 404 ||
        statusCode == 503;
  }
}
