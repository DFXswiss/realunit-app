import 'dart:convert';

import 'package:realunit_wallet/packages/config/api_config.dart';
import 'package:realunit_wallet/packages/service/dfx/dfx_auth_service.dart';
import 'package:realunit_wallet/packages/service/dfx/exceptions/api_exception.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/buy/buy_payment_info.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/buy/dto/real_unit_buy_confirm_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/buy/dto/real_unit_buy_dto.dart';
import 'package:realunit_wallet/packages/service/dfx/models/payment/buy/dto/real_unit_buy_payment_info_dto.dart';
import 'package:realunit_wallet/styles/currency.dart';

class RealUnitBuyPaymentInfoService extends DFXAuthService {
  static const _buyPaymentInfoPath = '/v1/realunit/buy';
  static String _confirmPaymentPath(int id) => '/v1/realunit/buy/$id/confirm';

  RealUnitBuyPaymentInfoService(super.appStore, super.walletService);

  Future<BuyPaymentInfo> getPaymentInfo(num amount, {Currency currency = Currency.chf}) async {
    final buyDto = RealUnitBuyDto(amount: amount, currency: currency);

    final uri = buildUri(host, _buyPaymentInfoPath);
    final response = await authenticatedPut(
      uri,
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode(buyDto.toJson()),
    );

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      final responseDto = RealUnitBuyPaymentInfoDto.fromJson(json);

      return BuyPaymentInfo(
        id: responseDto.id,
        iban: responseDto.iban,
        bic: responseDto.bic,
        name: responseDto.name,
        street: responseDto.street,
        number: responseDto.number,
        zip: responseDto.zip,
        city: responseDto.city,
        country: responseDto.country,
        currency: responseDto.currency,
        paymentRequest: responseDto.paymentRequest,
        remittanceInfo: responseDto.remittanceInfo,
        isValid: responseDto.isValid,
        amount: responseDto.amount,
        minVolume: responseDto.minVolume,
        maxVolume: responseDto.maxVolume,
        error: responseDto.error,
      );
    } else if (response.statusCode == 403) {
      final errorJson = jsonDecode(response.body) as Map<String, dynamic>;
      throw ApiException.fromJson(errorJson, httpStatusCode: response.statusCode);
    } else {
      final errorJson = jsonDecode(response.body) as Map<String, dynamic>;
      throw ApiException.fromJson(errorJson, httpStatusCode: response.statusCode);
    }
  }

  Future<RealUnitBuyConfirmDto> confirmPayment(int id) async {
    final uri = buildUri(host, _confirmPaymentPath(id));

    final response = await authenticatedPut(
      uri,
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      final errorJson = jsonDecode(response.body) as Map<String, dynamic>;
      throw ApiException.fromJson(errorJson, httpStatusCode: response.statusCode);
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final responseDto = RealUnitBuyConfirmDto.fromJson(json);
    return responseDto;
  }
}
