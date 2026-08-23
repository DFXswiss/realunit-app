import 'dart:async';

import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/packages/service/app_store.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_kyc_service.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/unsupported_kyc_step_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/models/kyc/dto/kyc_level_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/kyc/kyc_level.dart';
import 'package:realunit_wallet/packages/service/dfx/models/legal/real_unit_legal_agreement.dart';
import 'package:realunit_wallet/packages/service/dfx/models/user/dto/real_unit_user_data_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/user/dto/user_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/wallet/real_unit_registration_state.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_legal_service.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_registration_service.dart';
import 'package:realunit_wallet/packages/wallet/wallet.dart';
import 'package:realunit_wallet/setup/error_handling/crash_reporting.dart';

part 'kyc_state.dart';

class KycCubit extends Cubit<KycState> {
  static const _checkKycTimeout = Duration(seconds: 30);

  final DfxKycService _kycService;
  final RealUnitRegistrationService _registrationService;
  final RealUnitLegalService _legalService;
  final AppStore _appStore;

  /// Sink for the unmapped-step report — see [_emitUnsupportedStep]. Injectable
  /// so tests can observe the report without the crash reporter running.
  final NonFatalReporter _report;

  /// Offline fallback ONLY. The legal disclaimer gate is server-driven via
  /// `_legalService.getLegalInfo()`; this per-session flag is used solely when
  /// that endpoint is unreachable (pre-rollout backend or outage) so the
  /// disclaimer is not re-shown for the rest of the session — see the gate in
  /// `_runCheckKyc` and CONTRIBUTING.md "API as Decision Authority" (legacy
  /// tolerance).
  bool _legalDisclaimerAccepted = false;
  bool _emailRegistrationAttempted = false;
  String? _kycContext;

  /// Agreements the server last reported as outstanding, remembered so
  /// `acceptLegalDisclaimer` records exactly those on `PUT /v1/realunit/legal`.
  /// `null` until the first successful `getLegalInfo()` — the accept path then
  /// falls back to all agreements.
  List<RealUnitLegalAgreement>? _outstandingLegalAgreements;

  // `Future.timeout` does not cancel the underlying work, so a late HTTP
  // response from an earlier call can still resume and emit state after a
  // retry. Each `checkKyc()` captures its own generation; the run body and
  // any continuations bail when their generation no longer matches the
  // current one. Acts as a cancellation token for non-cancellable work.
  int _runGeneration = 0;

  KycCubit(
    DfxKycService kycService,
    RealUnitRegistrationService registrationService,
    RealUnitLegalService legalService,
    AppStore appStore, {
    NonFatalReporter report = reportNonFatal,
  }) : _kycService = kycService,
       _registrationService = registrationService,
       _legalService = legalService,
       _appStore = appStore,
       _report = report,
       super(const KycInitial());

  Future<void> checkKyc({String? context}) async {
    _kycContext = context ?? _kycContext;
    final generation = ++_runGeneration;
    try {
      await _runCheckKyc(generation).timeout(_checkKycTimeout);
    } on TimeoutException {
      if (isClosed || generation != _runGeneration) return;
      emit(const KycFailure('KYC backend did not respond in time'));
    } catch (e) {
      if (isClosed || generation != _runGeneration) return;
      emit(KycFailure(ApiException.userFacingMessage(e)));
    }
  }

  Future<void> _runCheckKyc(int generation) async {
    try {
      if (isClosed || generation != _runGeneration) return;
      emit(const KycLoading());

      final results = await Future.wait([
        _kycService.getKycStatus(context: _kycContext),
        _kycService.getUser(),
      ]);

      if (isClosed || generation != _runGeneration) return;

      final kycStatus = results.elementAt(0) as KycLevelDto;
      final user = results.elementAt(1) as UserDto;
      final level = kycStatus.kycLevel.value;

      if (user.mail == null) {
        emit(const KycSuccess(currentStep: KycStep.email));
        return;
      }

      // Edge case: email exists but level is < 10. Backend hasn't bumped the
      // level after a prior auto-registration attempt — re-fire it once.
      if (level < 10) {
        if (_emailRegistrationAttempted) {
          // Backend did not bump the level after registration; surface the
          // current state instead of recursing forever.
          emit(const KycSuccess(currentStep: KycStep.email));
          return;
        }
        _emailRegistrationAttempted = true;
        await _registrationService.registerEmail(user.mail!);
        if (isClosed || generation != _runGeneration) return;
        await _runCheckKyc(generation);
        return;
      }

      // The legal disclaimer gate is server-driven: the API is the single
      // source of truth for whether this user still has outstanding agreements
      // to accept — see CONTRIBUTING.md "API as Decision Authority". A 404 means
      // the `/legal` endpoint is not deployed yet (pre-rollout backend): fall
      // back to the local per-session `_legalDisclaimerAccepted` ceremony
      // (legacy tolerance, mirrors the `emailConfirmed` gate below). Any OTHER
      // error must fail closed on this compliance gate — rethrow so it surfaces
      // as a KycFailure instead of silently letting the user past the disclaimer.
      bool showDisclaimer;
      try {
        final legalInfo = await _legalService.getLegalInfo();
        if (isClosed || generation != _runGeneration) return;
        showDisclaimer = !legalInfo.allAccepted;
        _outstandingLegalAgreements = legalInfo.outstandingAgreements;
      } on ApiException catch (e) {
        if (isClosed || generation != _runGeneration) return;
        if (e.statusCode != 404) rethrow;
        showDisclaimer = !_legalDisclaimerAccepted;
      }
      if (showDisclaimer) {
        emit(const KycSuccess(currentStep: KycStep.legalDisclaimer));
        return;
      }

      // The server-side registration state is the single source of truth for
      // whether this wallet needs a full registration form, a one-tap
      // "add wallet" confirmation, or can skip the step entirely. Replaces
      // the previous client-side `_registrationSignProduced` flag — the cubit
      // re-fetches state after every successful registration round-trip and
      // routes from whatever the API now reports.
      final registrationInfo = await _registrationService.getRegistrationInfo();
      if (isClosed || generation != _runGeneration) return;

      // Signing capability is a physical property of the wallet implementation
      // (debug mode is address-only, cannot produce EIP-712 signatures) and
      // cannot be derived from the server — see CONTRIBUTING.md "API as
      // Decision Authority" exception list for "physical security boundary"
      // gates. Surface a tailored failure instead of letting the sign call
      // throw `UnsupportedError` deep inside the registration flow.
      if (_appStore.wallet.walletType == WalletType.debug &&
          (registrationInfo.state == RealUnitRegistrationState.newRegistration ||
              registrationInfo.state == RealUnitRegistrationState.addWallet)) {
        emit(const KycSignatureUnsupportedFailure());
        return;
      }

      switch (registrationInfo.state) {
        case RealUnitRegistrationState.alreadyRegistered:
          // The API owns the manual-review gate. When the Aktionariat forward
          // failed and staff must re-forward the registration, the backend
          // reports `manualReview == true` and we park the user on a dedicated
          // waiting screen. Takes precedence over the e-mail gate below. `false`
          // and `null` (pre-rollout backend) both mean "no gate" — proceed
          // exactly as before. Purely additive, API-driven; see CONTRIBUTING.md
          // "API as Decision Authority" (legacy tolerance).
          if (registrationInfo.manualReview == true) {
            emit(const KycManualReview());
            return;
          }
          // The API owns the confirmation gate. When it reports the account
          // e-mail is not yet confirmed, route to the confirm step. `true`
          // (confirmed, or a grandfathered account) and `null` (pre-rollout
          // backend) both mean "no gate" — proceed exactly as before. Purely
          // additive, API-driven; see CONTRIBUTING.md "API as Decision
          // Authority" (legacy tolerance).
          if (registrationInfo.emailConfirmed == false) {
            emit(const KycSuccess(currentStep: KycStep.confirmEmail));
            return;
          }
          // Fall through to the processStatus dispatch below — the sign
          // gate is satisfied and the user proceeds to the next KYC step.
          break;
        case RealUnitRegistrationState.addWallet:
          // Forward the server-supplied userData so `KycLinkWalletPage` does
          // not have to re-fetch — see CONTRIBUTING.md "Single round-trip per
          // decision". The backend always populates this for `AddWallet`.
          // `emailConfirmed` is deliberately not gated here: in `AddWallet` it
          // describes the *other* wallet's registration, not this one. After the
          // link-wallet round-trip `checkKyc()` re-fetches and the gate then
          // applies to the resulting `AlreadyRegistered` registration.
          emit(
            KycSuccess(
              currentStep: KycStep.linkWallet,
              realUnitUserData: registrationInfo.realUnitUserDataDto,
            ),
          );
          return;
        case RealUnitRegistrationState.newRegistration:
          // userData may be `null` for first-time registrations (no prior
          // record to pre-fill from); `KycRegistrationPage` renders an empty
          // form in that case.
          emit(
            KycSuccess(
              currentStep: KycStep.registration,
              realUnitUserData: registrationInfo.realUnitUserDataDto,
            ),
          );
          return;
      }

      // Account-merge invitation is still surfaced from the step list because
      // it is delivered as a step `reason`, not as `currentStep`. Render
      // verbatim what the backend tagged.
      final hasMergeRequest = kycStatus.kycSteps.any(
        (step) => step.reason == KycStepReason.accountMergeRequested,
      );
      if (hasMergeRequest) {
        emit(const KycAccountMergeRequested());
        return;
      }

      // From here on the API is the authority. Render `processStatus` plus
      // the matching `currentStep` from the session response; no local
      // iteration over `kycSteps`, no local "what counts as actionable"
      // set, no local level threshold.
      switch (kycStatus.processStatus) {
        case KycProcessStatus.completed:
          emit(const KycCompleted());
          return;
        case KycProcessStatus.failed:
          emit(const KycFailure('KYC terminated'));
          return;
        case KycProcessStatus.pendingReview:
          // PendingReview is authoritative: the API says "do not let the user
          // through". Never collapse this branch to `KycCompleted` — that
          // would be the same class of misroute, just in the opposite
          // direction (API: review pending → app: completed). If we cannot
          // identify a required step we surface `KycUnsupportedStepFailure`
          // so the user gets an explicit error instead of a silent dashboard
          // handoff.
          final pending = kycStatus.kycSteps.firstWhereOrNull(
            (s) => s.isRequired && s.status != KycStepStatus.completed,
          );
          if (pending == null) {
            _emitUnsupportedStep(null);
            return;
          }
          final step = _mapStepName(pending.name);
          if (step == null) {
            _emitUnsupportedStep(pending.name);
            return;
          }
          emit(KycPending(step));
          return;
        case KycProcessStatus.inProgress:
          await _continueKyc(generation, registrationInfo.realUnitUserDataDto);
          return;
        case KycProcessStatus.mergeProcessing:
          // The user confirmed a merge and the backend is still processing it.
          // Render a waiting state; do not treat the polling timeout as failure.
          emit(const KycMergeProcessing());
          return;
      }
    } on ApiException catch (e) {
      if (isClosed || generation != _runGeneration) return;
      // The body `code` is the authoritative signal — `TfaRequiredException`
      // on the API sets `{code: 'TFA_REQUIRED', level, message}` and happens
      // to use HTTP 403 as transport. Matching on status alone would also
      // capture unrelated forbidden errors and misroute them to 2FA.
      if (e.code == 'TFA_REQUIRED') {
        emit(const KycSuccess(currentStep: KycStep.twoFa));
      } else {
        rethrow;
      }
    } catch (e) {
      if (isClosed || generation != _runGeneration) return;
      emit(KycFailure(ApiException.userFacingMessage(e)));
    }
  }

  /// Records acceptance of the legal disclaimer. Sets the local per-session
  /// flag first (the offline fallback for a pre-rollout backend), then durably
  /// records acceptance server-side via `PUT /v1/realunit/legal` for whatever
  /// the server last reported as outstanding (all agreements when we never got
  /// a successful `getLegalInfo()`). A 404 (endpoint not deployed yet) is
  /// tolerated — the local flag carries the session; any other PUT failure
  /// surfaces as `KycFailure` rather than being swallowed into a silent
  /// re-prompt loop. On success the following `checkKyc()` re-reads the
  /// authoritative server state, which drives the next routing decision.
  Future<void> acceptLegalDisclaimer() async {
    _legalDisclaimerAccepted = true;
    try {
      await _legalService.acceptLegal(
        _outstandingLegalAgreements ?? RealUnitLegalAgreement.values,
      );
    } on ApiException catch (e) {
      if (isClosed) return;
      if (e.statusCode != 404) {
        emit(KycFailure(ApiException.userFacingMessage(e)));
        return;
      }
    } catch (e) {
      if (isClosed) return;
      emit(KycFailure(ApiException.userFacingMessage(e)));
      return;
    }
    await checkKyc();
  }

  /// should only be called after realunit registration was completed
  Future<void> _continueKyc(int generation, [RealUnitUserDataDto? realUnitUserData]) async {
    final kycStatus = await _kycService.continueKyc(context: _kycContext);
    if (isClosed || generation != _runGeneration) return;

    // `KycSessionDto.currentStep` is the authoritative source. Never
    // iterate `kycSteps` here: the local filter is the same anti-pattern
    // just eliminated in `_runCheckKyc`. If the session response has no
    // `currentStep` we surface
    // `KycUnsupportedStepFailure` instead of throwing a bare `StateError`
    // through the outer catch (which used to land as raw stack trace text
    // in the i18n message).
    final currentStep = kycStatus.currentStep;
    if (currentStep == null) {
      _emitUnsupportedStep(null);
      return;
    }

    final kycStep = _mapStepName(currentStep.name);
    if (kycStep == null) {
      _emitUnsupportedStep(currentStep.name);
      return;
    }

    emit(
      KycSuccess(
        currentStep: kycStep,
        urlOrToken: currentStep.session.url,
        realUnitUserData: realUnitUserData,
      ),
    );
  }

  /// Routes an unmapped step to the generic handoff page and reports the
  /// occurrence.
  ///
  /// The report is the only trace this leaves: every call in the flow returned
  /// 200 and the user sees a handoff screen, so a step name missing from
  /// [_mapStepName] is otherwise invisible until someone writes in. Reporting
  /// before the emit keeps the event even when the user leaves the flow on this
  /// screen.
  void _emitUnsupportedStep(KycStepName? stepName) {
    _report(UnsupportedKycStepException(stepName));
    emit(KycUnsupportedStepFailure(stepName));
  }

  KycStep? _mapStepName(KycStepName name) => switch (name) {
    KycStepName.contactData => KycStep.registration,
    KycStepName.personalData => KycStep.personalData,
    KycStepName.nationalityData => KycStep.nationality,
    KycStepName.ident => KycStep.ident,
    KycStepName.financialData => KycStep.financialData,
    KycStepName.dfxApproval => KycStep.dfxApproval,
    _ => null,
  };
}
