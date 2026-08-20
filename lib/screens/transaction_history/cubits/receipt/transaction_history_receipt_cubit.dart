import 'dart:convert';
import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realunit_wallet/packages/io/documents_directory_port.dart';
import 'package:realunit_wallet/packages/io/path_provider_adapter.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/real_unit_pdf_service.dart';
import 'package:realunit_wallet/styles/currency.dart';
import 'package:realunit_wallet/styles/language.dart';

part 'transaction_history_receipt_state.dart';

class TransactionHistoryReceiptCubit extends Cubit<TransactionHistoryReceiptState> {
  final RealUnitPdfService _pdfService;
  final DocumentsDirectoryPort _directory;

  TransactionHistoryReceiptCubit(
    RealUnitPdfService pdfService, {
    DocumentsDirectoryPort? directory,
  }) : _pdfService = pdfService,
       _directory = directory ?? const PathProviderAdapter(),
       super(const TransactionHistoryReceiptInitial());

  Future<void> generateReceipt(
    String txId, {
    Currency currency = Currency.chf,
    required Language language,
  }) async {
    try {
      emit(const TransactionHistoryReceiptLoading());

      final response = await _pdfService.getTransactionReceipt(
        txId,
        currency: currency,
        language: language,
      );
      if (isClosed) return;
      final file = await _createFileFromBytes(response.pdfData, txId);
      if (isClosed) return;

      emit(TransactionHistoryReceiptSuccess(file.path));
    } catch (e) {
      if (isClosed) return;
      emit(TransactionHistoryReceiptFailure(ApiException.userFacingMessage(e)));
    }
  }

  Future<File> _createFileFromBytes(String data, String dfxId) async {
    final bytes = base64Decode(data);
    final tempDir = await _directory.getTemporaryDirectory();
    final file = File('${tempDir.path}/receipt_$dfxId.pdf');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }
}
