import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:realunit_wallet/generated/i18n.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/referral_lookup_status.dart';

/// Cubit token for a timed-out referral GET/POST. UI maps it to
/// [S.referralCodeUnavailable] so `TimeoutException.toString()` never
/// reaches the gate, overview, or create screens. Same token for an
/// unmounted NestJS route (`Cannot GET …`), 503 persist failure, and
/// 503 holding lookup failed (TB Ziff. 2: do not show «not eligible»
/// from a stale snapshot) so live api.dfx.swiss does not show Nest
/// internals before the controller is copied into DFXswiss/backend.
const referralUnavailableMessage = 'unavailable';
const referralNotEligibleMessage = 'not_eligible';
const referralNeedsTermsMessage = 'needs_terms';
const referralGuestNameMessage = 'guest_name';
const referralInvalidMessage = 'invalid';
const referralSpentMessage = 'spent';
const referralSelfReferralMessage = 'self_referral';
const referralAlreadyBoundMessage = 'already_bound';
const referralAlreadyRegisteredMessage = 'already_registered';
const referralQuotaMessage = 'quota';

String referralErrorMessage(Object error) {
  if (error is TimeoutException) return referralUnavailableMessage;
  if (error is ApiException) {
    if (isReferralRouteMissing(error.message)) {
      return referralUnavailableMessage;
    }
    if (error.code == 'UNAVAILABLE') return referralUnavailableMessage;
    if (error.code == 'NOT_ELIGIBLE') return referralNotEligibleMessage;
    if (error.code == 'NEEDS_TERMS') return referralNeedsTermsMessage;
    if (error.code == 'SPENT') return referralSpentMessage;
    if (error.code == 'SELF_REFERRAL') return referralSelfReferralMessage;
    if (error.code == 'ALREADY_BOUND') return referralAlreadyBoundMessage;
    if (error.code == 'ALREADY_REGISTERED') {
      return referralAlreadyRegisteredMessage;
    }
    if (error.code == 'EXPIRED' || error.code == 'NOT_FOUND') {
      return referralInvalidMessage;
    }
    if (error.code == 'INVALID') {
      final msg = error.message.toLowerCase();
      if (msg.contains('guestname')) return referralGuestNameMessage;
      if (msg.contains('accepted')) return referralNeedsTermsMessage;
      return referralInvalidMessage;
    }
    if (error.code == 'QUOTA') return referralQuotaMessage;
    final status = error.statusCode;
    if (status != null &&
        (status >= 500 || status == 401 || status == 408 || status == 429)) {
      return referralUnavailableMessage;
    }
    if (status == 410) return referralInvalidMessage;
    if (status != null && status >= 400 && status < 500) {
      return referralInvalidMessage;
    }
    return referralUnavailableMessage;
  }
  return referralUnavailableMessage;
}

String localizedReferralError(BuildContext context, String message) {
  if (message == referralUnavailableMessage) {
    return S.of(context).referralCodeUnavailable;
  }
  if (message == referralNotEligibleMessage) {
    return S.of(context).referralNotEligible;
  }
  if (message == referralNeedsTermsMessage) {
    return S.of(context).referralTermsRequired;
  }
  if (message == referralGuestNameMessage) {
    return S.of(context).referralGuestNameRequired;
  }
  if (message == referralSpentMessage) {
    return S.of(context).referralCodeSpent;
  }
  if (message == referralSelfReferralMessage) {
    return S.of(context).referralSelfReferral;
  }
  if (message == referralAlreadyBoundMessage) {
    return S.of(context).referralAlreadyBound;
  }
  if (message == referralAlreadyRegisteredMessage) {
    return S.of(context).referralAlreadyRegistered;
  }
  if (message == referralInvalidMessage) {
    return S.of(context).referralCodeInvalid;
  }
  if (message == referralQuotaMessage) {
    return S.of(context).referralQuarterCap;
  }
  return S.of(context).referralCodeUnavailable;
}

String localizedReferralErrorTitle(BuildContext context, String message) {
  if (message == referralSpentMessage) {
    return S.of(context).referralCodeSpentTitle;
  }
  return S.of(context).referralCodeInvalidTitle;
}
