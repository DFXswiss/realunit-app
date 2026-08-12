import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/models/balance.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/balance_service.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_auth_service.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_kyc_service.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/address_already_linked_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/bitbox_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/models/user/dto/real_unit_user_data_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/wallet/real_unit_registration_state.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_registration_service.dart';
import 'package:realunit_wallet/packages/service/wallet_service.dart';
import 'package:realunit_wallet/packages/wallet/exceptions/signing_cancelled_exception.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';
import 'package:realunit_wallet/packages/wallet/wallet_account.dart';

part 'migrate_bitbox_state.dart';

class MigrateBitboxCubit extends Cubit<MigrateBitboxState> {
  MigrateBitboxCubit(
    this._walletService,
    // DfxKycService serves purely as the auth transport here
    // (refreshAuthToken / authenticateLinkedAccount); no KYC-specific calls.
    DfxKycService authService,
    this._registrationService,
    this._balanceService,
    this._appStore,
  ) : _authService = authService,
      super(const MigrateBitboxIntro());

  final WalletService _walletService;
  final DFXAuthService _authService;
  final RealUnitRegistrationService _registrationService;
  final BalanceService _balanceService;
  final AppStore _appStore;

  BitboxWallet? _draft;
  String? _newJwt;
  String? _bitboxSignature;
  BitboxWallet? _persisted;
  Future<void> Function()? _pendingRetry;
  _MigrateBitboxRetryKind? _pendingRetryKind;
  Timer? _settlingTimer;
  int _settlingGeneration = 0;
  int _settlingAttempts = 0;
  bool _settlingInFlight = false;

  static const _settlingPollInterval = Duration(seconds: 3);
  static const _settlingMaxAttempts = 20;

  /// Only valid once onDevicePaired has produced a fresh link (state reaches
  /// RegisterReady or later). Throws if accessed earlier.
  AWalletAccount get draftAccount {
    final draft = _draft;
    if (draft == null) {
      throw StateError('draftAccount accessed before onDevicePaired');
    }
    return draft.currentAccount;
  }

  /// Only valid once onDevicePaired has produced a fresh link.
  String get linkedJwt {
    final jwt = _newJwt;
    if (jwt == null) {
      throw StateError('linkedJwt accessed before onDevicePaired completed linking');
    }
    return jwt;
  }

  Future<void> startPairing() async {
    emit(const MigrateBitboxAwaitingDevice());
  }

  /// Called by the view when the ConnectBitboxPage sheet is dismissed without
  /// onFinish firing (user cancelled pairing). No-op guard so it is safe to call
  /// unconditionally after the sheet future completes.
  void cancelPairing() {
    if (state is! MigrateBitboxAwaitingDevice) return;
    emit(const MigrateBitboxIntro());
  }

  Future<void> onDevicePaired(BitboxWallet draft) async {
    emit(const MigrateBitboxLinking());
    _draft = draft;
    try {
      final sourceInfo = await _registrationService.getRegistrationInfo();
      if (sourceInfo.state != RealUnitRegistrationState.alreadyRegistered) {
        _pendingRetry = null;
        _pendingRetryKind = null;
        emit(
          const MigrateBitboxFailure(
            MigrateBitboxFailureReason.registrationMissing,
          ),
        );
        return;
      }

      final refreshed = await _authService.refreshAuthToken();
      if (refreshed == null) {
        _pendingRetry = null;
        _pendingRetryKind = null;
        emit(const MigrateBitboxFailure(MigrateBitboxFailureReason.generic));
        return;
      }
      _newJwt = await _authService.authenticateLinkedAccount(
        draft.currentAccount,
        refreshed,
      );

      final draftAddress = draft.currentAccount.primaryAddress.address.hexEip55;
      // authenticateLinkedAccount has already cached the signature via
      // sessionCache.saveSignature if it had to sign fresh; a cache hit skipped
      // that. Either way, read it back here rather than re-deriving it.
      _bitboxSignature = _appStore.sessionCache.signatureAddress == draftAddress
          ? _appStore.sessionCache.signature
          : null;

      final info = await _registrationService.getRegistrationInfoWith(_newJwt!);
      switch (info.state) {
        case RealUnitRegistrationState.addWallet:
          final userData = info.realUnitUserDataDto;
          if (userData == null) {
            _pendingRetry = null;
            _pendingRetryKind = null;
            emit(
              const MigrateBitboxFailure(
                MigrateBitboxFailureReason.generic,
                message: 'API returned addWallet without userData',
              ),
            );
            return;
          }
          _pendingRetry = null;
          _pendingRetryKind = null;
          emit(MigrateBitboxRegisterReady(userData, draftAddress));
        case RealUnitRegistrationState.alreadyRegistered:
          if (info.manualReview == true) {
            _pendingRetry = null;
            _pendingRetryKind = null;
            emit(const MigrateBitboxRegistrationPending());
            return;
          }
          await _runSafely(
            _persistAndPrepareTransfer,
            _MigrateBitboxRetryKind.transferPreparation,
          );
        case RealUnitRegistrationState.newRegistration:
          _pendingRetry = () => onDevicePaired(draft);
          _pendingRetryKind = _MigrateBitboxRetryKind.linking;
          emit(
            const MigrateBitboxFailure(
              MigrateBitboxFailureReason.generic,
              message: 'wallet link did not attach to the account',
              canRetry: true,
            ),
          );
      }
    } on AddressAlreadyLinkedException {
      _pendingRetry = null;
      _pendingRetryKind = null;
      emit(
        const MigrateBitboxFailure(MigrateBitboxFailureReason.addressAlreadyLinked),
      );
    } on SigningCancelledException {
      _pendingRetry = () => onDevicePaired(draft);
      _pendingRetryKind = _MigrateBitboxRetryKind.linking;
      emit(
        const MigrateBitboxFailure(
          MigrateBitboxFailureReason.signatureCancelled,
          canRetry: true,
        ),
      );
    } on BitboxNotConnectedException {
      _pendingRetry = () => onDevicePaired(draft);
      _pendingRetryKind = _MigrateBitboxRetryKind.linking;
      emit(
        const MigrateBitboxFailure(
          MigrateBitboxFailureReason.bitboxNotConnected,
          canRetry: true,
        ),
      );
    } catch (e) {
      _pendingRetry = () => onDevicePaired(draft);
      _pendingRetryKind = _MigrateBitboxRetryKind.linking;
      emit(
        MigrateBitboxFailure(
          MigrateBitboxFailureReason.generic,
          message: e.toString(),
          canRetry: true,
        ),
      );
    }
  }

  Future<void> onRegisterCompleted() async {
    if (state is! MigrateBitboxRegisterReady) return;
    await _runSafely(
      _persistAndPrepareTransfer,
      _MigrateBitboxRetryKind.transferPreparation,
    );
  }

  void onRegisterPending() {
    if (state is! MigrateBitboxRegisterReady) return;
    _pendingRetry = null;
    _pendingRetryKind = null;
    emit(const MigrateBitboxRegistrationPending());
  }

  /// Re-runs whatever action last failed with `canRetry: true`. No-op if there
  /// is nothing to retry.
  Future<void> retry() async {
    final action = _pendingRetry;
    final kind = _pendingRetryKind;
    if (action == null) return;
    final retryKind = kind!;
    _pendingRetry = null;
    _pendingRetryKind = null;
    emit(
      switch (retryKind) {
        _MigrateBitboxRetryKind.linking => const MigrateBitboxLinking(),
        _MigrateBitboxRetryKind.transferPreparation =>
          const MigrateBitboxPreparingTransfer(),
      },
    );
    await _runSafely(action, retryKind);
  }

  /// Runs a fallible wizard action without losing its retry affordance. The
  /// action is re-installed before the failure is exposed, so a second retry
  /// remains possible even when the first retry attempt itself throws.
  Future<void> _runSafely(
    Future<void> Function() action,
    _MigrateBitboxRetryKind kind, {
    Future<void> Function()? retryAction,
  }) async {
    try {
      await action();
    } catch (e) {
      if (isClosed) return;
      _pendingRetry = retryAction ?? action;
      _pendingRetryKind = kind;
      emit(
        MigrateBitboxFailure(
          MigrateBitboxFailureReason.generic,
          message: e.toString(),
          canRetry: true,
        ),
      );
    }
  }

  Future<void> _persistAndPrepareTransfer() async {
    _persisted = await _walletService.persistBitboxWallet(_draft!);
    final softwareAddress = _appStore.primaryAddress;
    final bitboxAddress = _persisted!.currentAccount.primaryAddress.address.hexEip55;

    late final Balance balance;
    try {
      balance = await _balanceService.fetchBalance(softwareAddress);
    } catch (_) {
      if (isClosed) return;
      _pendingRetry = _persistAndPrepareTransfer;
      _pendingRetryKind = _MigrateBitboxRetryKind.transferPreparation;
      emit(
        const MigrateBitboxFailure(
          MigrateBitboxFailureReason.generic,
          message: 'balance unavailable',
          canRetry: true,
        ),
      );
      return;
    }
    if (isClosed) return;

    final amount = balance.balance.toInt();
    if (amount == 0) {
      // Nothing to transfer — e.g. re-entering the wizard after a transfer
      // that already completed in a prior run.
      await finishMigration();
      return;
    }
    _pendingRetry = null;
    _pendingRetryKind = null;
    emit(
      MigrateBitboxTransferReady(
        fromAddress: softwareAddress,
        toAddress: bitboxAddress,
        amount: amount,
      ),
    );
  }

  /// Only valid while [state] is [MigrateBitboxTransferReady].
  void startTransfer() {
    final current = state;
    if (current is! MigrateBitboxTransferReady) return;
    emit(
      MigrateBitboxTransferring(
        toAddress: current.toAddress,
        amount: current.amount,
      ),
    );
  }

  /// Leaves the embedded transfer flow after a DEFINITIVE (non-retryable)
  /// SendProcessFailure. Re-entering via retry runs a fresh
  /// _persistAndPrepareTransfer — the dead intent is discarded and the balance
  /// re-read, so a partially-executed transfer surfaces as a reduced (or zero)
  /// remaining amount instead of a blind re-send.
  void onTransferFailedTerminally(String message) {
    if (state is! MigrateBitboxTransferring) return;
    _pendingRetry = _persistAndPrepareTransfer;
    _pendingRetryKind = _MigrateBitboxRetryKind.transferPreparation;
    emit(
      MigrateBitboxFailure(
        MigrateBitboxFailureReason.generic,
        message: message,
        canRetry: true,
      ),
    );
  }

  Future<void> onTransferBroadcast() async {
    final current = state;
    if (current is! MigrateBitboxTransferring) return;
    emit(const MigrateBitboxSettling());
    _startSettlingPoll(current.amount);
  }

  void _startSettlingPoll(int expectedAmount) {
    _settlingTimer?.cancel();
    final generation = ++_settlingGeneration;
    _settlingAttempts = 0;
    _settlingInFlight = false;
    _settlingTimer = Timer.periodic(_settlingPollInterval, (_) async {
      if (generation != _settlingGeneration || _settlingInFlight) return;
      _settlingInFlight = true;
      try {
        final balance = await _balanceService.fetchBalance(
          _appStore.primaryAddress,
        );
        if (isClosed || generation != _settlingGeneration) return;
        _settlingAttempts++;
        final amount = balance.balance.toInt();
        if (amount == 0) {
          await _runSafely(
            finishMigration,
            _MigrateBitboxRetryKind.transferPreparation,
            retryAction: _persistAndPrepareTransfer,
          );
          if (isClosed || generation != _settlingGeneration) return;
          _settlingTimer?.cancel();
          return;
        }
        if (amount < expectedAmount) {
          await _runSafely(
            _persistAndPrepareTransfer,
            _MigrateBitboxRetryKind.transferPreparation,
          );
          if (isClosed || generation != _settlingGeneration) return;
          _settlingTimer?.cancel();
          return;
        }
        if (_settlingAttempts >= _settlingMaxAttempts) {
          _settlingTimer?.cancel();
          emit(const MigrateBitboxSettlingTimeout());
        }
      } catch (_) {
        if (isClosed || generation != _settlingGeneration) return;
        _settlingAttempts++;
        if (_settlingAttempts >= _settlingMaxAttempts) {
          _settlingTimer?.cancel();
          emit(const MigrateBitboxSettlingTimeout());
        }
      } finally {
        if (generation == _settlingGeneration) {
          _settlingInFlight = false;
        }
      }
    });
  }

  Future<void> finishMigration() async {
    if (isClosed) return;
    emit(const MigrateBitboxCompleting());
    final persisted = _persisted!;
    await _walletService.setCurrentWallet(persisted.id);
    if (isClosed) return;
    final signature = _bitboxSignature;
    if (signature != null) {
      final bitboxAddress = persisted.currentAccount.primaryAddress.address.hexEip55;
      // The lazy path in DFXAuthService.getSignature still recovers on the next
      // authenticated call if this is skipped — mirrors
      // ConnectBitboxCubit.continueWithoutSignature.
      await _appStore.sessionCache.saveSignature(
        bitboxAddress,
        signature,
        _authService.buildSignMessage(bitboxAddress),
      );
      if (isClosed) return;
    }
    // After setCurrentWallet, before the view's HomeBloc reload, so any sync
    // triggered by the reload is already authenticated as the new wallet.
    _appStore.sessionCache.setAuthToken(
      _newJwt!,
      persisted.currentAccount.primaryAddress.address.hexEip55,
    );
    if (isClosed) return;
    _pendingRetry = null;
    _pendingRetryKind = null;
    emit(MigrateBitboxSuccess(persisted));
  }

  @override
  Future<void> close() {
    // Invalidate settling callbacks already awaiting a balance/finish
    // operation: steps that have not run yet are skipped after close.
    // Already-completed side effects (e.g. a finished setCurrentWallet) are
    // not rolled back — a later re-entry completes the migration cleanly
    // via the zero-balance skip.
    _settlingGeneration++;
    _settlingTimer?.cancel();
    return super.close();
  }
}

enum _MigrateBitboxRetryKind { linking, transferPreparation }
