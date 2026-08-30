import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_created_invite_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_invite_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_summary_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_terms_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_referral_service.dart';
import 'package:realunit_wallet/screens/referral/referral_error_message.dart';
import 'package:realunit_wallet/screens/referral/referral_limits.dart';

part 'referral_state.dart';

class ReferralCubit extends Cubit<ReferralState> {
  final RealUnitReferralService _service;
  bool _refreshing = false;
  int _invitesGeneration = 0;

  ReferralCubit(this._service) : super(const ReferralInitial());

  Future<void> load() async {
    final current = state;
    if (current is ReferralLoading) return;
    if (current is ReferralFailure && current.retrying) return;
    if (current is ReferralNeedsTerms && current.retrying) return;
    if (current is ReferralFailure) {
      emit(ReferralFailure(message: current.message, retrying: true));
    } else if (current is ReferralNeedsTerms) {
      emit(
        ReferralNeedsTerms(
          summary: current.summary,
          errorMessage: current.errorMessage,
          retrying: true,
        ),
      );
    } else {
      emit(const ReferralLoading());
    }
    try {
      await _emitFromSummary(await _service.getSummary());
    } on ApiException catch (e) {
      emit(ReferralFailure(message: referralErrorMessage(e)));
    } catch (e) {
      emit(ReferralFailure(message: referralErrorMessage(e)));
    }
  }

  Future<void> acceptTerms({
    String version = ReferralTermsDto.bundledVersion,
  }) async {
    final current = state;
    if (current is! ReferralNeedsTerms) return;
    final summary = current.summary;

    emit(
      ReferralTermsAccepting(
        summary: summary,
        errorMessage: current.errorMessage,
      ),
    );
    try {
      await _service.acceptTerms(version: version);
    } on ApiException catch (e) {
      emit(
        ReferralNeedsTerms(
          summary: summary,
          errorMessage: referralErrorMessage(e),
        ),
      );
      return;
    } catch (e) {
      emit(
        ReferralNeedsTerms(
          summary: summary,
          errorMessage: referralErrorMessage(e),
        ),
      );
      return;
    }
    // Accept already posted. A later summary/invite-list failure must not
    // send the user back to the checkbox as if they still need to accept.
    try {
      await _emitFromSummary(await _service.getSummary());
    } on ApiException catch (e) {
      emit(ReferralFailure(message: referralErrorMessage(e)));
    } catch (e) {
      emit(ReferralFailure(message: referralErrorMessage(e)));
    }
  }

  Future<void> createInvite({required String guestName}) async {
    final name = sanitizeReferralGuestName(guestName);
    if (name.isEmpty) return;
    final current = state;
    if (current is! ReferralOverviewLoaded && current is! ReferralCreateReady) {
      return;
    }
    final summary = switch (current) {
      ReferralOverviewLoaded(:final summary) => summary,
      ReferralCreateReady(:final summary) => summary,
      _ => null,
    };
    if (summary == null) return;

    emit(
      ReferralCreating(
        summary: summary,
        guestName: name,
        errorMessage: current is ReferralCreateReady
            ? current.errorMessage
            : null,
      ),
    );
    try {
      final created = await _service.createInvite(guestName: name);
      emit(ReferralInviteCreated(summary: summary, invite: created));
    } on ApiException catch (e) {
      if (e.code == 'NOT_ELIGIBLE') {
        emit(const ReferralNotEligible());
        return;
      }
      if (e.code == 'NEEDS_TERMS') {
        emit(ReferralNeedsTerms(summary: summary));
        return;
      }
      emit(
        ReferralCreateReady(
          summary: summary,
          errorMessage: referralErrorMessage(e),
        ),
      );
    } catch (e) {
      emit(
        ReferralCreateReady(
          summary: summary,
          errorMessage: referralErrorMessage(e),
        ),
      );
    }
  }

  void openCreate() {
    final current = state;
    if (current is ReferralOverviewLoaded) {
      emit(ReferralCreateReady(summary: current.summary));
    } else if (current is ReferralInviteCreated) {
      emit(ReferralCreateReady(summary: current.summary));
    }
  }

  Future<void> refreshOverview() async {
    if (state is ReferralLoading || _refreshing) return;
    _refreshing = true;
    final previous = state;
    try {
      await _emitFromSummary(await _service.getSummary());
    } on ApiException catch (e) {
      if (previous is ReferralOverviewLoaded) return;
      emit(ReferralFailure(message: referralErrorMessage(e)));
    } catch (e) {
      if (previous is ReferralOverviewLoaded) return;
      emit(ReferralFailure(message: referralErrorMessage(e)));
    } finally {
      _refreshing = false;
    }
  }

  /// Refetches open-invite rows without dropping the summary tiles.
  Future<void> reloadInvites() async {
    final current = state;
    if (current is! ReferralOverviewLoaded) return;
    if (current.invitesLoading) return;
    if (_refreshing) return;
    final generation = ++_invitesGeneration;
    emit(
      ReferralOverviewLoaded(
        summary: current.summary,
        invites: current.invites,
        invitesError: current.invitesError,
        invitesLoading: true,
      ),
    );
    try {
      final invites = await _service.getInvites();
      if (generation != _invitesGeneration) return;
      final latest = state;
      if (latest is! ReferralOverviewLoaded) return;
      emit(ReferralOverviewLoaded(summary: latest.summary, invites: invites));
    } on ApiException catch (e) {
      if (generation != _invitesGeneration) return;
      final latest = state;
      if (latest is! ReferralOverviewLoaded) return;
      emit(
        ReferralOverviewLoaded(
          summary: latest.summary,
          invites: latest.invites,
          invitesError: referralErrorMessage(e),
        ),
      );
    } catch (e) {
      if (generation != _invitesGeneration) return;
      final latest = state;
      if (latest is! ReferralOverviewLoaded) return;
      emit(
        ReferralOverviewLoaded(
          summary: latest.summary,
          invites: latest.invites,
          invitesError: referralErrorMessage(e),
        ),
      );
    }
  }

  Future<void> _emitFromSummary(ReferralSummaryDto summary) async {
    _invitesGeneration++;
    if (!summary.eligible) {
      emit(const ReferralNotEligible());
      return;
    }
    if (!summary.termsAccepted) {
      emit(ReferralNeedsTerms(summary: summary));
      return;
    }
    // Counts come from summary. Open-invite copy/share is best-effort so a
    // list outage cannot hide the programme after terms are accepted.
    var invites = const <ReferralInviteDto>[];
    String? invitesError;
    try {
      invites = await _service.getInvites();
    } on ApiException catch (e) {
      invitesError = referralErrorMessage(e);
    } catch (e) {
      invitesError = referralErrorMessage(e);
    }
    emit(
      ReferralOverviewLoaded(
        summary: summary,
        invites: invites,
        invitesError: invitesError,
      ),
    );
  }
}
