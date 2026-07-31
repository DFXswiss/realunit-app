import 'dart:convert';

import 'package:realunit_wallet/packages/config/api_config.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_auth_service.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/pay/dto/lnurlp_payment_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/pay/dto/real_unit_ocp_pay_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/pay/dto/real_unit_ocp_pay_result_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/pay/dto/real_unit_ocp_pay_status_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/pay/dto/real_unit_ocp_pay_submit_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/pay/dto/real_unit_ocp_pay_unsigned_transaction_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/pay/dto/real_unit_swap_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/pay/dto/real_unit_swap_payment_info_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/pay/dto/real_unit_swap_unsigned_transaction_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/pay/swap_payment_info.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/dto/broadcast_transaction_request_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/sell/dto/broadcast_transaction_response_dto.dart';

/// Backend client for the Open CryptoPay pay flow (DFXswiss/api #3819, all under
/// `/v1/realunit/...`). Subclasses [DFXAuthService] for the JWT handshake +
/// retry-on-401 the sell flow already uses; the public lnurlp read is the only
/// unauthenticated call.
class RealUnitPayService extends DFXAuthService {
  static const _lnurlpPath = '/v1/lnurlp';
  static const _swapPath = '/v1/realunit/swap';
  static String _swapUnsignedTxPath(int id) => '/v1/realunit/swap/$id/unsigned-transaction';
  static String _swapBroadcastPath(int id) => '/v1/realunit/swap/$id/broadcast';
  static const _payUnsignedTxPath = '/v1/realunit/pay/unsigned-transaction';
  static const _paySubmitPath = '/v1/realunit/pay/submit';
  static String _payStatusPath(String id) => '/v1/realunit/pay/$id/status';

  static const _httpTimeout = Duration(seconds: 20);

  RealUnitPayService(super.appStore, super.walletService);

  /// Public OCP payment-link read (no auth). Returns the requested fiat amount,
  /// the active quote (id + expiration) and the per-method transfer amounts.
  Future<LnurlpPaymentDto> getPaymentDetails(String id) async {
    final uri = buildUri(host, '$_lnurlpPath/$id');
    final response = await appStore.httpClient
        .get(uri, headers: {'accept': 'application/json'})
        .timeout(_httpTimeout);

    if (response.statusCode != 200) {
      _throwApi(response.body, response.statusCode);
    }
    return LnurlpPaymentDto.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  // --- Swap (REALU → ZCHF, proceeds stay in the user wallet) ---

  Future<SwapPaymentInfo> getSwapPaymentInfo(RealUnitSwapDto dto) async {
    final uri = buildUri(host, _swapPath);
    final response = await authenticatedPut(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(dto.toJson()),
    ).timeout(_httpTimeout);

    if (response.statusCode != 200 && response.statusCode != 201) {
      _throwApi(response.body, response.statusCode);
    }
    final responseDto = RealUnitSwapPaymentInfoDto.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
    return SwapPaymentInfo.fromDto(responseDto);
  }

  Future<RealUnitSwapUnsignedTransactionDto> createSwapUnsignedTransaction(int id) async {
    final uri = buildUri(host, _swapUnsignedTxPath(id));
    final response = await authenticatedPut(
      uri,
      headers: {'Content-Type': 'application/json'},
    ).timeout(_httpTimeout);

    if (response.statusCode != 200 && response.statusCode != 201) {
      _throwApi(response.body, response.statusCode);
    }
    return RealUnitSwapUnsignedTransactionDto.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<String> broadcastSwapTransaction(int id, BroadcastTransactionRequestDto dto) async {
    final uri = buildUri(host, _swapBroadcastPath(id));
    final response = await authenticatedPut(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(dto.toJson()),
    ).timeout(_httpTimeout);

    if (response.statusCode != 200 && response.statusCode != 201) {
      _throwApi(response.body, response.statusCode);
    }
    return BroadcastTransactionResponseDto.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    ).txHash;
  }

  // --- OCP pay (settle a ZCHF payment-link quote via the lnurlp flow) ---

  Future<RealUnitOcpPayUnsignedTransactionDto> createPayUnsignedTransaction(
    RealUnitOcpPayDto dto,
  ) async {
    final uri = buildUri(host, _payUnsignedTxPath);
    final response = await authenticatedPut(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(dto.toJson()),
    ).timeout(_httpTimeout);

    if (response.statusCode != 200 && response.statusCode != 201) {
      _throwApi(response.body, response.statusCode);
    }
    return RealUnitOcpPayUnsignedTransactionDto.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<String> submitPay(RealUnitOcpPaySubmitDto dto) async {
    final uri = buildUri(host, _paySubmitPath);
    final response = await authenticatedPut(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(dto.toJson()),
    ).timeout(_httpTimeout);

    if (response.statusCode != 200 && response.statusCode != 201) {
      _throwApi(response.body, response.statusCode);
    }
    return RealUnitOcpPayResultDto.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    ).txId;
  }

  Future<RealUnitOcpPayStatusDto> getPayStatus(String id) async {
    final uri = buildUri(host, _payStatusPath(id));
    final response = await authenticatedGet(uri).timeout(_httpTimeout);

    if (response.statusCode != 200) {
      _throwApi(response.body, response.statusCode);
    }
    return RealUnitOcpPayStatusDto.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Never _throwApi(String body, int statusCode) {
    final errorJson = jsonDecode(body) as Map<String, dynamic>;
    throw ApiException.fromJson(errorJson, httpStatusCode: statusCode);
  }
}
