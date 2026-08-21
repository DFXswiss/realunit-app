import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_kyc_service.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/models/kyc/dto/kyc_financial_data_dto.dart';
import 'package:realunit_wallet/styles/language.dart';

part 'kyc_financial_data_state.dart';

class KycFinancialDataCubit extends Cubit<KycFinancialDataState> {
  final DfxKycService _kycService;

  KycFinancialDataCubit(DfxKycService kycService)
    : _kycService = kycService,
      super(const KycFinancialDataInitial());

  Future<void> loadQuestions(
    String url, {
    Language language = Language.de,
  }) async {
    try {
      emit(const KycFinancialDataLoading());

      final data = await _kycService.getFinancialData(url, language: language);
      final responseMap = Map.fromEntries(data.responses.map((r) => MapEntry(r.key, r.value)));
      final visibleQuestions = _filterVisibleQuestions(data.questions, responseMap);
      emit(
        KycFinancialDataLoadedSuccess(
          allQuestions: data.questions,
          visibleQuestions: visibleQuestions,
          responses: responseMap,
          currentIndex: 0,
          url: url,
        ),
      );
    } catch (e) {
      emit(KycFinancialDataFailure(ApiException.userFacingMessage(e)));
    }
  }

  void answerQuestion(String key, String value) {
    final current = state;
    if (current is! KycFinancialDataLoadedSuccess) return;

    final updatedResponses = Map<String, String>.from(current.responses);
    updatedResponses[key] = value;

    final visibleQuestions = _filterVisibleQuestions(current.allQuestions, updatedResponses);

    emit(
      KycFinancialDataLoadedSuccess(
        allQuestions: current.allQuestions,
        visibleQuestions: visibleQuestions,
        responses: updatedResponses,
        currentIndex: current.currentIndex,
        url: current.url,
      ),
    );
  }

  Future<void> submitAndNext() async {
    final current = state;
    if (current is! KycFinancialDataLoadedSuccess) return;

    if (current.isLastQuestion) {
      await _submitAll(current);
    } else {
      emit(
        KycFinancialDataLoadedSuccess(
          allQuestions: current.allQuestions,
          visibleQuestions: current.visibleQuestions,
          responses: current.responses,
          currentIndex: current.currentIndex + 1,
          url: current.url,
        ),
      );
    }
  }

  Future<void> _submitAll(KycFinancialDataLoadedSuccess current) async {
    try {
      emit(const KycFinancialDataSubmitting());

      final responses = current.responses.entries
          .map((e) => KycFinancialResponse(key: e.key, value: e.value))
          .toList();

      await _kycService.setFinancialData(current.url, responses);
      emit(const KycFinancialDataSubmitSuccess());
    } catch (e) {
      // 404 = the step is no longer pending (an earlier submit landed but the
      // response was lost) — treat as success so checkKyc advances the flow.
      if (e is ApiException && e.statusCode == 404) {
        emit(const KycFinancialDataSubmitSuccess());
        return;
      }
      // Keep the answers and stay on the questions UI so the user can retry,
      // instead of dropping them onto a dead-end failure page.
      emit(KycFinancialDataSubmitFailure.from(current, ApiException.userFacingMessage(e)));
    }
  }

  void goBack() {
    final current = state;
    if (current is! KycFinancialDataLoadedSuccess) return;
    if (current.currentIndex <= 0) return;

    emit(
      KycFinancialDataLoadedSuccess(
        allQuestions: current.allQuestions,
        visibleQuestions: current.visibleQuestions,
        responses: current.responses,
        currentIndex: current.currentIndex - 1,
        url: current.url,
      ),
    );
  }

  List<KycFinancialQuestion> _filterVisibleQuestions(
    List<KycFinancialQuestion> allQuestions,
    Map<String, String> responseMap,
  ) {
    return allQuestions.where((question) {
      if (question.conditions == null || question.conditions!.isEmpty) return true;
      return question.conditions!.any(
        (condition) => responseMap[condition.question] == condition.response,
      );
    }).toList();
  }
}
