import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:realunit_wallet/packages/io/documents_directory_port.dart';
import 'package:realunit_wallet/packages/io/path_provider_adapter.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_pdf_service.dart';
import 'package:realunit_wallet/styles/currency.dart';
import 'package:realunit_wallet/styles/language.dart';

part 'settings_tax_report_state.dart';

class SettingsTaxReportCubit extends Cubit<SettingsTaxReportState> {
  final RealUnitPdfService _pdfService;
  final DocumentsDirectoryPort _directory;

  SettingsTaxReportCubit(
    RealUnitPdfService pdfService, {
    DocumentsDirectoryPort? directory,
  }) : _pdfService = pdfService,
       _directory = directory ?? const PathProviderAdapter(),
       super(const SettingsTaxReportInitial());

  Future<void> generateTaxReport({
    required DateTime date,
    required Currency currency,
    required Language language,
  }) async {
    try {
      emit(const SettingsTaxReportLoading());

      final dateWithLatestTime = _getDateWithLatestTime(date);
      final response = await _pdfService.getBalanceReport(
        date: dateWithLatestTime,
        currency: currency,
        language: language,
      );
      if (isClosed) return;
      final file = await _createFileFromBytes(response.pdfData, date);
      if (isClosed) return;

      emit(SettingsTaxReportSuccess(file.path));
    } catch (e) {
      if (isClosed) return;
      emit(SettingsTaxReportFailure(ApiException.userFacingMessage(e)));
    }
  }

  Future<File> _createFileFromBytes(String data, DateTime date) async {
    final bytes = base64Decode(data);
    final tempDir = await _directory.getTemporaryDirectory();
    final file = File(
      '${tempDir.path}/balance_report_${DateFormat('dd_MM_yyyy').format(date)}.pdf',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// If today's date use current time minus 1 minute, for past dates use end of day
  DateTime _getDateWithLatestTime(DateTime selectedDate) {
    final now = clock.now();
    final today = DateTime(now.year, now.month, now.day);
    final selected = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);

    if (selected.isAtSameMomentAs(today)) {
      return now.subtract(const Duration(minutes: 1)).toUtc();
    } else {
      return DateTime(selectedDate.year, selectedDate.month, selectedDate.day, 23, 59, 59).toUtc();
    }
  }
}
