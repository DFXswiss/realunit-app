import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_bind_result_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_created_invite_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_invite_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/referral/dto/referral_summary_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_referral_service.dart';

part 'referral_state.dart';

class ReferralCubit extends Cubit<ReferralState> {
  final RealUnitReferralService _service;

  ReferralCubit(this._service) : super(const ReferralInitial());

  Future<void> load() async {
    emit(const ReferralLoading());
    try {
      final summary = await _service.getSummary();
      if (!summary.eligible) {
        emit(const ReferralNotEligible());
        return;
      }
      if (!summary.termsAccepted) {
        emit(ReferralNeedsTerms(summary: summary));
        return;
      }
      final invites = await _service.getInvites();
      emit(ReferralOverviewLoaded(summary: summary, invites: invites));
    } on ApiException catch (e) {
      emit(ReferralFailure(message: e.message));
    } catch (e) {
      emit(ReferralFailure(message: e.toString()));
    }
  }

  Future<void> acceptTerms() async {
    final current = state;
    if (current is! ReferralNeedsTerms && current is! ReferralTermsAccepting) {
      return;
    }
    final summary = switch (current) {
      ReferralNeedsTerms(:final summary) => summary,
      ReferralTermsAccepting(:final summary) => summary,
      _ => null,
    };
    if (summary == null) return;

    emit(ReferralTermsAccepting(summary: summary));
    try {
      await _service.acceptTerms();
      final refreshed = await _service.getSummary();
      final invites = await _service.getInvites();
      emit(ReferralOverviewLoaded(summary: refreshed, invites: invites));
    } on ApiException catch (e) {
      emit(ReferralNeedsTerms(summary: summary, errorMessage: e.message));
    } catch (e) {
      emit(ReferralNeedsTerms(summary: summary, errorMessage: e.toString()));
    }
  }

  Future<void> createInvite({required String guestName}) async {
    final current = state;
    if (current is! ReferralOverviewLoaded && current is! ReferralCreateReady) {
      return;
    }
    final summary = switch (current) {
      ReferralOverviewLoaded(:final summary) => summary,
      ReferralCreateReady(:final summary) => summary,
      ReferralCreating(:final summary) => summary,
      _ => null,
    };
    if (summary == null) return;

    emit(ReferralCreating(summary: summary, guestName: guestName));
    try {
      final created = await _service.createInvite(guestName: guestName);
      emit(ReferralInviteCreated(summary: summary, invite: created));
    } on ApiException catch (e) {
      emit(ReferralCreateReady(summary: summary, errorMessage: e.message));
    } catch (e) {
      emit(ReferralCreateReady(summary: summary, errorMessage: e.toString()));
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
    try {
      final summary = await _service.getSummary();
      final invites = await _service.getInvites();
      emit(ReferralOverviewLoaded(summary: summary, invites: invites));
    } on ApiException catch (e) {
      emit(ReferralFailure(message: e.message));
    } catch (e) {
      emit(ReferralFailure(message: e.toString()));
    }
  }

  Future<ReferralBindResultDto?> bindCode(String code) async {
    try {
      return await _service.bind(code: code);
    } on ApiException {
      rethrow;
    }
  }
}
