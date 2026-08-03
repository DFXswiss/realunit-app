import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/balance_service.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_auth_service.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_kyc_service.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/address_already_linked_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/bitbox_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/models/registration/registration_status.dart';
import 'package:realunit_wallet/packages/service/dfx/models/user/dto/real_unit_user_data_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/wallet/real_unit_registration_state.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_registration_service.dart';
import 'package:realunit_wallet/packages/service/wallet_service.dart';
import 'package:realunit_wallet/packages/wallet/exceptions/signing_cancelled_exception.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';

part 'migrate_bitbox_state.dart';

class MigrateBitboxCubit extends Cubit<MigrateBitboxState> {
  MigrateBitboxCubit(
    this._walletService,
    // DfxKycService is the smallest registered DFXAuthService — used only as
    // a transport for ensureSignatureFor(account); no KYC-specific calls here.
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
      final oldJwt = await _authService.getAuthToken();
      if (oldJwt == null) {
        _pendingRetry = null;
        emit(const MigrateBitboxFailure(MigrateBitboxFailureReason.generic));
        return;
      }
      _newJwt = await _authService.authenticateLinkedAccount(draft.currentAccount, oldJwt);

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
            emit(
              const MigrateBitboxFailure(
                MigrateBitboxFailureReason.generic,
                message: 'API returned addWallet without userData',
              ),
            );
            return;
          }
          _pendingRetry = null;
          emit(MigrateBitboxRegisterReady(userData, draftAddress));
        case RealUnitRegistrationState.alreadyRegistered:
          if (info.manualReview == true) {
            _pendingRetry = null;
            emit(const MigrateBitboxRegistrationPending());
            return;
          }
          await _persistAndPrepareTransfer();
        case RealUnitRegistrationState.newRegistration:
          _pendingRetry = null;
          emit(
            const MigrateBitboxFailure(MigrateBitboxFailureReason.registrationMissing),
          );
      }
    } on AddressAlreadyLinkedException {
      _pendingRetry = null;
      emit(
        const MigrateBitboxFailure(MigrateBitboxFailureReason.addressAlreadyLinked),
      );
    } on SigningCancelledException {
      _pendingRetry = () => onDevicePaired(draft);
      emit(
        const MigrateBitboxFailure(
          MigrateBitboxFailureReason.signatureCancelled,
          canRetry: true,
        ),
      );
    } on BitboxNotConnectedException {
      _pendingRetry = () => onDevicePaired(draft);
      emit(
        const MigrateBitboxFailure(
          MigrateBitboxFailureReason.bitboxNotConnected,
          canRetry: true,
        ),
      );
    } catch (e) {
      _pendingRetry = () => onDevicePaired(draft);
      emit(
        MigrateBitboxFailure(
          MigrateBitboxFailureReason.generic,
          message: e.toString(),
          canRetry: true,
        ),
      );
    }
  }

  /// Only valid while [state] is [MigrateBitboxRegisterReady].
  Future<void> register() async {
    final current = state;
    if (current is! MigrateBitboxRegisterReady) return;
    final userData = current.userData;
    emit(const MigrateBitboxRegistering());
    try {
      final status = await _registrationService.registerWalletFor(
        _draft!.currentAccount,
        userData,
        _newJwt!,
      );
      switch (status) {
        case RegistrationStatus.completed:
        case RegistrationStatus.alreadyRegistered:
          await _persistAndPrepareTransfer();
        case RegistrationStatus.pendingReview:
        case RegistrationStatus.forwardingFailed:
          _pendingRetry = null;
          emit(const MigrateBitboxRegistrationPending());
      }
    } on SigningCancelledException {
      _pendingRetry = register;
      emit(
        const MigrateBitboxFailure(
          MigrateBitboxFailureReason.signatureCancelled,
          canRetry: true,
        ),
      );
    } on BitboxNotConnectedException {
      _pendingRetry = register;
      emit(
        const MigrateBitboxFailure(
          MigrateBitboxFailureReason.bitboxNotConnected,
          canRetry: true,
        ),
      );
    } catch (e) {
      _pendingRetry = register;
      emit(
        MigrateBitboxFailure(
          MigrateBitboxFailureReason.generic,
          message: e.toString(),
          canRetry: true,
        ),
      );
    }
  }

  /// Re-runs whatever action last failed with `canRetry: true`. No-op if there
  /// is nothing to retry.
  Future<void> retry() async {
    final action = _pendingRetry;
    if (action == null) return;
    await action();
  }

  Future<void> _persistAndPrepareTransfer() async {
    _persisted = await _walletService.persistBitboxWallet(_draft!);
    final softwareAddress = _appStore.primaryAddress;
    final bitboxAddress = _persisted!.currentAccount.primaryAddress.address.hexEip55;

    await _balanceService.updateBalance(softwareAddress);
    final balance = await _balanceService.getBalance(
      _appStore.apiConfig.asset,
      softwareAddress,
    );
    if (balance == null) {
      // Fail-loud: NEVER interpret a missing balance read as zero — that would
      // silently skip the transfer and end the wizard "successfully" without
      // moving any funds.
      _pendingRetry = _persistAndPrepareTransfer;
      emit(
        const MigrateBitboxFailure(
          MigrateBitboxFailureReason.generic,
          message: 'balance unavailable',
          canRetry: true,
        ),
      );
      return;
    }

    final amount = balance.balance.toInt();
    if (amount == 0) {
      // Nothing to transfer — e.g. re-entering the wizard after a transfer that
      // already completed in a prior run.
      await finishMigration();
      return;
    }
    _pendingRetry = null;
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

  Future<void> finishMigration() async {
    emit(const MigrateBitboxCompleting());
    final persisted = _persisted!;
    await _walletService.setCurrentWallet(persisted.id);
    final signature = _bitboxSignature;
    if (signature != null) {
      final bitboxAddress = persisted.currentAccount.primaryAddress.address.hexEip55;
      // The lazy path in DFXAuthService.getSignature still recovers on the next
      // authenticated call if this is skipped — mirrors
      // ConnectBitboxCubit.continueWithoutSignature.
      await _appStore.sessionCache.saveSignature(bitboxAddress, signature);
    }
    // After setCurrentWallet, before the view's HomeBloc reload, so any sync
    // triggered by the reload is already authenticated as the new wallet.
    _appStore.sessionCache.setAuthToken(_newJwt!);
    _pendingRetry = null;
    emit(MigrateBitboxSuccess(persisted));
  }
}
